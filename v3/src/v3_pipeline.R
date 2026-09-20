#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, warn = 1)

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
stage <- arg_value("--stage", "preflight")
script_file <- sub("^--file=", "", commandArgs()[grep("^--file=", commandArgs())][1L])
if (!length(script_file) || is.na(script_file)) script_file <- "src/v3_pipeline.R"
root <- normalizePath(arg_value("--root", file.path(dirname(dirname(script_file)))), winslash = "/", mustWork = FALSE)
module_root <- normalizePath(file.path(root, "R"), winslash = "/", mustWork = TRUE)
source(file.path(module_root, "config.R"), local = TRUE)
force <- "--force" %in% args
iter <- as.integer(arg_value("--iter", V3_SAMPLING$iter))
warmup <- as.integer(arg_value("--warmup", V3_SAMPLING$warmup))
chains <- as.integer(arg_value("--chains", V3_SAMPLING$chains))
cores <- as.integer(arg_value("--cores", V3_SAMPLING$cores))
seed <- as.integer(arg_value("--seed", V3_SEED))
source(file.path(module_root, "data_encoding.R"), local = TRUE)
source(file.path(module_root, "weights.R"), local = TRUE)
source(file.path(module_root, "metrics.R"), local = TRUE)
source(file.path(module_root, "applicability.R"), local = TRUE)
source(file.path(module_root, "cache_io.R"), local = TRUE)
source(file.path(module_root, "fitting.R"), local = TRUE)
source(file.path(module_root, "prediction.R"), local = TRUE)
source(file.path(module_root, "cross_validation.R"), local = TRUE)
source(file.path(module_root, "comparison.R"), local = TRUE)
source(file.path(module_root, "plotting.R"), local = TRUE)

input_dir <- file.path(root, "input")
run_dir <- file.path(root, "runs")
result_dir <- file.path(root, "results")
review_dir <- file.path(root, "review")
stan_path <- file.path(root, "stan", "joint_bb.stan")
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)

log_msg <- function(...) cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), ..., "\n")

load_state_v3 <- function() {
  p <- file.path(run_dir, "prepared_v3.rds")
  if (!file.exists(p)) stop("prepared_v3.rds is missing; run --stage prepare first")
  state <- readRDS(p)
  if (!identical(state$version, V3_VERSION)) stop("Prepared state belongs to another v3 version")
  for (nm in names(state$input_hashes)) {
    pth <- file.path(input_dir, paste0(nm, ".csv"))
    if (!file.exists(pth) || !identical(sha256_file(pth), state$input_hashes[[nm]])) {
      stop("Input hash changed for ", nm, "; cached fits are not reusable")
    }
  }
  state
}

read_analysis_config <- function() {
  p <- arg_value("--config", file.path(root, "config", "analysis.json"))
  if (!file.exists(p)) stop("Config file not found: ", p)
  jsonlite::read_json(p, simplifyVector = TRUE)
}

verify_input_contract_v3 <- function(cfg) {
  contract_path <- file.path(root, "input", "contract.json")
  if (!file.exists(contract_path)) stop("input/contract.json is missing")
  contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
  if (!identical(as.character(contract$version), V3_VERSION)) stop("Input contract version mismatch")
  actual <- c(observations.csv = sha256_file(file.path(input_dir, "observations.csv")),
              sites.csv = sha256_file(file.path(input_dir, "sites.csv")))
  expected <- unlist(contract$input_hashes)
  if (!identical(unname(actual), unname(expected))) stop("Input SHA-256 does not match input/contract.json")
  if (!identical(as.integer(contract$records), as.integer(cfg$expected_records)) ||
      !identical(as.integer(contract$panel_species), as.integer(cfg$expected_panel_species))) {
    stop("Input contract counts do not match config/analysis.json")
  }
  if (!setequal(as.character(contract$models), as.character(cfg$models)) ||
      !setequal(as.character(contract$routes), as.character(cfg$routes)) ||
      !setequal(as.character(contract$train_weightings), as.character(cfg$train_weightings)) ||
      !setequal(as.character(contract$eval_weightings), as.character(cfg$eval_weightings))) {
    stop("Input contract model/route/weight grid does not match config/analysis.json")
  }
  if (isTRUE(contract$scheme_a) || isTRUE(contract$phylogeny)) stop("Input contract enables a forbidden v3 component")
  invisible(contract)
}

write_run_plan <- function(state) {
  rows <- list(); j <- 0L
  for (route in V3_ROUTES) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
    rows[[j <- j + 1L]] <- data.frame(FitID = paste("full", route, model, tw, sep = "__"),
      Route = route, Model = model, TrainWeighting = tw, Design = "full", K = NA_integer_, Fold = NA_integer_,
      TrainingDataHash = sha256_object(state$observations$Species), WeightHash = NA_character_,
      ConfigHash = sha256_object(list(version = V3_VERSION, priors = V3_PRIORS)),
      stringsAsFactors = FALSE)
    for (design in names(list(fivefold = 5L, tenfold = 10L))) for (fold in seq_len(list(fivefold = 5L, tenfold = 10L)[[design]])) {
      rows[[j <- j + 1L]] <- data.frame(FitID = paste(design, fold, route, model, tw, sep = "__"),
        Route = route, Model = model, TrainWeighting = tw, Design = design, K = list(fivefold = 5L, tenfold = 10L)[[design]], Fold = fold,
        TrainingDataHash = NA_character_, WeightHash = NA_character_,
        ConfigHash = sha256_object(list(version = V3_VERSION, priors = V3_PRIORS)), stringsAsFactors = FALSE)
    }
  }
  plan <- do.call(rbind, rows)
  write_csv_atomic(plan, file.path(run_dir, "run_plan.csv"))
  plan
}

run_preflight_v3 <- function() {
  require_v3_packages(FALSE)
  cfg <- read_analysis_config()
  if (!identical(as.character(cfg$version), V3_VERSION)) stop("Config version mismatch")
  if (isTRUE(cfg$scheme_a) || isTRUE(cfg$phylogeny)) stop("Scheme A and phylogeny must be disabled in v3")
  verify_input_contract_v3(cfg)
  state <- prepare_state(input_dir, expected_species = cfg$expected_panel_species,
                         expected_records = cfg$expected_records, output_dir = run_dir)
  plan <- write_run_plan(state)
  if (nrow(plan) != 256L) stop("v3 run plan must contain 256 formal tasks")
  source_files <- list.files(module_root, pattern = "\\.R$", full.names = TRUE)
  source_text <- paste(unlist(lapply(source_files, readLines, warn = FALSE)), collapse = "\n")
  if (grepl("schemeA_tobit|crch::|tree\\.nwk|Phylogeny_only|random effect", source_text, ignore.case = TRUE)) {
    stop("v3 source contains a forbidden Scheme A, phylogeny, or random-effect dependency")
  }
  report <- list(status = "PASS", version = V3_VERSION,
    panel_species = nrow(state$encoded), records = nrow(state$observations),
    binary_species = length(state$binary_species), joint_species = length(state$joint_species),
    fit_count_full = v3_expected_fit_count(), fit_count_cv = v3_expected_cv_fit_count(),
    input_hashes = as.list(state$input_hashes), package_versions = list(digest = as.character(packageVersion("digest")),
      jsonlite = as.character(packageVersion("jsonlite"))))
  write_json_atomic(report, file.path(review_dir, "preflight_v3.json"))
  log_msg("PREFLIGHT_PASS")
  invisible(state)
}

run_smoke_v3 <- function(state) {
  require_v3_packages(TRUE)
  smoke_root <- file.path(run_dir, "smoke")
  dir.create(smoke_root, recursive = TRUE, showWarnings = FALSE)
  out <- list()
  for (route in V3_ROUTES) {
    model <- "M1"; tw <- "species_equal"
    train_species <- if (route == "binary") state$binary_species else state$joint_species
    b <- fit_bundle_v3(state, route, model, train_species, tw, smoke_root, "smoke", 1L,
                       stan_path, iter = 300L, warmup = 150L, chains = 2L, cores = 2L,
                       seed = seed, force = force)
    if (route == "binary") {
      dr <- binary_prediction_draws(b, state)
      if (!all(is.finite(dr)) || any(dr < 0 | dr > 1)) stop("Binary smoke prediction failed")
    } else {
      dr <- joint_expected_draws(b, state)
      pi <- joint_predictive_draws(b, state, seed = seed)
      if (!all(is.finite(dr)) || !all(is.finite(pi)) || any(dr < 0 | dr > 1) || any(pi < 0 | pi > 1)) {
        stop("Joint smoke prediction failed")
      }
    }
    out[[route]] <- b$diagnostics
  }
  smoke_status <- if (all(vapply(out, function(x) identical(as.character(x$Status[[1L]]), "PASS"), logical(1))))
    "PASS" else "PASS_WITH_DIAGNOSTIC_WARNINGS"
  write_json_atomic(list(status = smoke_status, version = V3_VERSION, diagnostics = out),
                    file.path(review_dir, "smoke_v3.json"))
  invisible(TRUE)
}

run_full_fits_v3 <- function(state) {
  require_v3_packages(TRUE)
  rows <- list(); weight_rows <- list(); j <- 0L; wj <- 0L
  for (route in V3_ROUTES) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
    train_species <- if (route == "binary") state$binary_species else state$joint_species
    log_msg("FIT", route, model, tw)
    b <- fit_bundle_v3(state, route, model, train_species, tw, root, "full", NULL,
                       stan_path, iter, warmup, chains, cores, seed, force)
    d <- b$diagnostics; d$Route <- route; d$Model <- model; d$TrainWeighting <- tw; d$Key <- b$key
    rows[[j <- j + 1L]] <- d
    active <- if (route == "binary") state$observations$Species %in% train_species & !is.na(state$observations$High) else
      state$observations$Species %in% train_species & state$observations$Informative
    wf <- build_train_weights(state$observations[active, "Species", drop = FALSE], tw)
    wf$Route <- route; wf$Model <- model; wf$TrainWeighting <- tw; wf$Design <- "full"; wf$Stage <- "full"; wf$FitKey <- b$key
    weight_rows[[wj <- wj + 1L]] <- wf
  }
  diagnostics <- do.call(rbind, rows)
  write_csv_atomic(diagnostics, file.path(result_dir, "full_diagnostics.csv"))
  full_weights <- do.call(rbind, weight_rows); rownames(full_weights) <- NULL
  write_csv_atomic(full_weights, file.path(result_dir, "training_weights_full.csv"))
  if (any(diagnostics$Status != "PASS")) stop("At least one full fit failed diagnostics")
  diagnostics
}

make_fold_tables_v3 <- function(state) {
  b5 <- make_binary_folds_v3(state, 5L, seed + 5L)
  b10 <- make_binary_folds_v3(state, 10L, seed + 10L)
  j5 <- make_joint_folds_v3(state, 5L, seed + 15L)
  j10 <- make_joint_folds_v3(state, 10L, seed + 20L)
  write_csv_atomic(b5, file.path(result_dir, "folds_binary_species_5.csv"))
  write_csv_atomic(b10, file.path(result_dir, "folds_binary_species_10.csv"))
  write_csv_atomic(j5, file.path(result_dir, "folds_joint_species_5.csv"))
  write_csv_atomic(j10, file.path(result_dir, "folds_joint_species_10.csv"))
  list(fivefold = list(binary = b5, joint = j5), tenfold = list(binary = b10, joint = j10))
}

run_cv_stage_v3 <- function(state) {
  require_v3_packages(TRUE)
  folds <- make_fold_tables_v3(state)
  ans <- run_cv_v3(state, root, folds, stan_path, iter, warmup, chains, cores, seed, force)
  roc <- make_roc_outputs(ans$evidence, result_dir)
  cal <- list()
  for (ew in V3_EVAL_WEIGHTINGS) {
    z <- ans$evidence[ans$evidence$Route == "binary", , drop = FALSE]
    for (design in unique(z$Design)) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
      q <- z[z$Design == design & z$Model == model & z$TrainWeighting == tw, , drop = FALSE]
      if (nrow(q)) cal[[length(cal) + 1L]] <- cbind(data.frame(Design = design, Model = model,
        TrainWeighting = tw, stringsAsFactors = FALSE), calibration_bins(q, ew))
    }
  }
  calibration <- if (length(cal)) do.call(rbind, cal) else data.frame()
  write_csv_atomic(calibration, file.path(result_dir, "calibration_bins.csv"))
  mod <- compare_evidence_models(ans$evidence, "species_equal")
  train <- compare_training_methods(ans$evidence, "species_equal")
  write_csv_atomic(mod, file.path(result_dir, "model_vs_null.csv"))
  write_csv_atomic(train, file.path(result_dir, "training_method_comparisons.csv"))
  invisible(ans)
}

run_prediction_stage_v3 <- function(state) {
  bundles <- list()
  for (route in V3_ROUTES) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
    p <- fit_path_v3(root, route, model, tw, "full", NULL)
    if (!file.exists(p)) stop("Missing full fit for prediction: ", p)
    bundles[[paste(route, model, tw, sep = "|")]] <- readRDS(p)
  }
  make_prediction_table(state, bundles, file.path(result_dir, "full_panel_predictions.csv"))
}

run_visual_report_stage_v3 <- function() {
  dir.create(file.path(root, "figures"), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(file.path(result_dir, "roc_coordinates.csv"))) {
    roc <- utils::read.csv(file.path(result_dir, "roc_coordinates.csv"), stringsAsFactors = FALSE)
    if (nrow(roc)) plot_roc_base(roc, file.path(root, "figures", "ROC_curves.pdf"))
  }
  if (file.exists(file.path(result_dir, "calibration_bins.csv"))) {
    cal <- utils::read.csv(file.path(result_dir, "calibration_bins.csv"), stringsAsFactors = FALSE)
    if (nrow(cal)) plot_calibration_base(cal, file.path(root, "figures", "calibration_bins.pdf"))
  }
  pred_path <- file.path(result_dir, "full_panel_predictions.csv")
  if (file.exists(pred_path)) plot_species_predictions_base(utils::read.csv(pred_path, stringsAsFactors = FALSE), file.path(root, "figures"))
  cv_path <- file.path(result_dir, "cv_metrics_summary.csv")
  pred <- if (file.exists(pred_path)) utils::read.csv(pred_path, stringsAsFactors = FALSE) else data.frame()
  cv <- if (file.exists(cv_path)) utils::read.csv(cv_path, stringsAsFactors = FALSE) else data.frame()
  lines <- c("# v3 analysis report", "", paste0("Version: `", V3_VERSION, "`"),
    "", "This report describes computed artifacts; it does not convert diagnostic completion into scientific proof.",
    "", paste0("Panel species: ", if (nrow(pred)) length(unique(pred$Species)) else NA_integer_),
    paste0("Prediction rows: ", nrow(pred)), paste0("CV metric rows: ", nrow(cv)),
    "", "Train weightings: record_equal and species_equal.",
    "Evaluation weightings: record_equal and species_equal.",
    "Site151 is metadata only; Site315 remains inside M1/M2/M3; Scheme A and phylogeny are excluded.")
  dir.create(file.path(root, "reports"), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(root, "reports", "REPORT_v3.md"), useBytes = TRUE)
}

run_audit_stage_v3 <- function(state) {
  plan <- utils::read.csv(file.path(run_dir, "run_plan.csv"), stringsAsFactors = FALSE)
  expected <- v3_expected_fit_count() + v3_expected_cv_fit_count()
  missing <- character()
  if (nrow(plan) == expected && !anyDuplicated(plan$FitID)) for (i in seq_len(nrow(plan))) {
    p <- fit_path_v3(root, plan$Route[[i]], plan$Model[[i]], plan$TrainWeighting[[i]],
                     plan$Design[[i]], if (is.na(plan$Fold[[i]])) NULL else plan$Fold[[i]])
    if (!file.exists(p)) missing <- c(missing, p)
  }
  status <- if (nrow(plan) != expected || anyDuplicated(plan$FitID)) "FAILED_PLAN" else
    if (length(missing)) "INCOMPLETE" else "PASS"
  write_json_atomic(list(status = status, expected_tasks = expected, plan_rows = nrow(plan),
                         missing_fit_files = missing, version = V3_VERSION), file.path(review_dir, "audit_v3.json"))
  if (status != "PASS") stop("Formal fit audit failed: ", status)
  invisible(TRUE)
}

if (stage == "preflight") {
  run_preflight_v3()
} else if (stage == "prepare") {
  run_preflight_v3()
} else if (stage == "smoke") {
  state <- load_state_v3(); run_smoke_v3(state)
} else if (stage == "fit") {
  state <- load_state_v3(); run_full_fits_v3(state)
} else if (stage == "cv") {
  state <- load_state_v3(); run_cv_stage_v3(state)
} else if (stage == "predict") {
  state <- load_state_v3(); run_prediction_stage_v3(state)
} else if (stage == "all") {
  run_preflight_v3(); state <- load_state_v3(); run_smoke_v3(state); run_full_fits_v3(state)
  run_cv_stage_v3(state); run_prediction_stage_v3(state); run_visual_report_stage_v3(); run_audit_stage_v3(state)
  write_json_atomic(list(status = "COMPLETE", version = V3_VERSION,
                         formal_full_fits = v3_expected_fit_count(), formal_cv_fits = v3_expected_cv_fit_count()),
                    file.path(review_dir, "final_v3_status.json"))
} else {
  stop("Unknown stage: ", stage)
}
