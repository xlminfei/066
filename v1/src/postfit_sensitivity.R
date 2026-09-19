# Postprocessing only. All inferential blocks are read from the frozen manual.
options(warn = 1) # Print each warning immediately to the task log; statistical settings are unchanged.
source("/project/work/ratio_analysis_20260914/scripts/common.R", local = .GlobalEnv)

sensitivity_block <- function(variant) {
  switch(variant, b_sd_025 = "04_STRONG_PRIOR", b_sd_100 = "04_WEAK_PRIOR",
    rho_beta22 = "04_ENDPOINT_PRIOR", beta_binomial = "04_COUNT_DISPERSION",
    stop("Unknown sensitivity variant: ", variant))
}

sensitivity_manual_check <- function() {
  manifest_path <- file.path(manual_dir, "MANIFEST.csv")
  anchor <- readLines(file.path(manual_dir, "MANIFEST.sha256"), warn = FALSE)
  anchor <- anchor[grepl("  MANIFEST[.]csv$", anchor)]
  if (length(anchor) != 1L || !identical(substr(anchor, 1L, 64L),
      digest::digest(file = manifest_path, algo = "sha256"))) stop("Manual manifest anchor changed.")
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  files <- c("00_开始与使用顺序.md", "02_独立分类模型.md", "03_联合比率模型.md",
             "04_模型检查与敏感性.md", "05_诊断与模型比较.md")
  rows <- match(files, manifest$File)
  actual <- vapply(files, function(file) digest::digest(file = file.path(manual_dir, file),
    algo = "sha256"), character(1))
  if (anyNA(rows) || !identical(unname(actual), manifest$SHA256[rows])) stop("Frozen manual content changed.")
  actual
}

sensitivity_selection <- function(run_dir, jobs) {
  index <- utils::read.csv(file.path(run_dir, "fit_index.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  columns <- c("Outcome", "Variant", "Model", "Key", "RelativeFile", "FileSHA256", "SelectedAt")
  if (!all(columns %in% names(index)) || anyNA(index[, columns, drop = FALSE])) stop("Invalid selected fit index.")
  key <- paste(index$Outcome, index$Model, index$Variant, sep = "/")
  index <- index[!duplicated(key, fromLast = TRUE), columns, drop = FALSE]
  actual <- paste(index$Outcome, index$Model, index$Variant, sep = "/")
  expected <- paste(jobs$outcome, jobs$model, jobs$variant, sep = "/")
  if (anyDuplicated(expected) || !all(expected %in% actual)) {
    stop("Missing selected fits: ", paste(setdiff(expected, actual), collapse = ", "))
  }
  index <- index[match(expected, actual), , drop = FALSE]
  rownames(index) <- NULL
  if (any(!grepl("^[0-9a-f]{64}$", index$Key)) || any(!grepl("^[0-9a-f]{64}$", index$FileSHA256)) ||
      !identical(index$RelativeFile, file.path("fits", index$Outcome, index$Variant,
        paste0(index$Model, "_", substr(index$Key, 1L, 16L), ".rds")))) stop("Fit identity path is invalid.")
  index
}

sensitivity_selection_key <- function(index) {
  digest::digest(index[, setdiff(names(index), "SelectedAt"), drop = FALSE], algo = "sha256")
}

sensitivity_load <- function(run_dir, outcome, variant, selected) {
  context <- new.env(parent = .GlobalEnv)
  context$RUN_DIR <- run_dir
  run_block("05_诊断与模型比较.md", "05_LOAD", target = context,
    overrides = list(OUTCOME = outcome, VARIANT = variant, fit_index = selected))
  expected <- selected$Model[selected$Outcome == outcome & selected$Variant == variant]
  if (anyDuplicated(expected) || !setequal(names(context$bundles), expected) ||
      length(context$bundles) != length(expected)) stop("05_LOAD did not return the planned group.")
  context
}

sensitivity_verify_request <- function(bundle, outcome, model, variant, run_dir) {
  if (!identical(bundle$request$outcome, outcome) || !identical(bundle$request$model, model) ||
      !identical(bundle$request$variant, variant)) stop("Indexed fit and embedded request disagree.")
  context <- new.env(parent = .GlobalEnv)
  run_block("00_开始与使用顺序.md", "00_SETTINGS", target = context)
  context$RUN_DIR <- run_dir
  context$MODEL_NAME <- model
  context$VARIANT <- variant
  if (variant != "primary") run_block("04_模型检查与敏感性.md", sensitivity_block(variant),
    overrides = list(MODEL_NAME = model), target = context)
  sampling <- bundle$request$sampling
  map <- c(seed = "SEED", chains = "CHAINS", cores = "CORES", iter = "ITER", warmup = "WARMUP",
           adapt_delta = "ADAPT_DELTA", max_treedepth = "MAX_TREEDEPTH")
  if (!setequal(names(sampling), names(map)) || any(lengths(sampling) != 1L) ||
      any(!is.finite(unlist(sampling))) || sampling$chains != 4L || sampling$cores != 4L ||
      sampling$iter <= sampling$warmup) stop("Invalid sampling identity.")
  for (name in names(map)) assign(map[[name]], sampling[[name]], envir = context)
  if (outcome == "binary") {
    run_block("02_独立分类模型.md", "02_PREPARE", target = context)
  } else {
    run_block("03_联合比率模型.md", "03_STAN_MODEL", target = context)
    context$joint_code_hash <- digest::digest(context$joint_model_code, algo = "sha256", serialize = FALSE)
    run_block("03_联合比率模型.md", "03_PREPARE", target = context)
  }
  if (!identical(context$request, bundle$request) || !identical(context$request_key, bundle$key)) {
    stop("Selected request is not the manual's specified variant: ", outcome, "/", model, "/", variant)
  }
  invisible(TRUE)
}

sensitivity_ppc_data <- function(context, rng_before, rng_after) {
  outcome <- context$OUTCOME; model <- context$CHECK_MODEL; variant <- context$VARIANT
  key <- context$obj$key
  observed <- statistics <- ecdfs <- sources <- list()
  for (kind in names(context$ppc_sets)) {
    data <- context$ppc_sets[[kind]]
    source <- if (outcome == "binary") context$obj$request$training else {
      context$obj$request$source_rows[context$obj$request$source_rows$Type == kind, , drop = FALSE]
    }
    if (length(data$observed) != nrow(source) || ncol(data$replicated) != nrow(source) ||
        any(!is.finite(data$observed)) || any(!is.finite(data$replicated)) ||
        any(data$observed < 0 | data$observed > 1) || any(data$replicated < 0 | data$replicated > 1)) {
      stop("Sensitivity PPC source mapping or generated values failed.")
    }
    sources[[kind]] <- source
    observed[[kind]] <- data.frame(Outcome = outcome, Model = model, Variant = variant, Key = key,
      Subset = kind, RecordID = if (outcome == "binary") source$BinaryID else source$RecordID,
      Species = as.character(source$Species), Observed = data$observed)
    statistics[[kind]] <- data.frame(Outcome = outcome, Model = model, Variant = variant, Key = key,
      Subset = kind, Replicate = seq_len(nrow(data$replicated)), Mean = rowMeans(data$replicated),
      SD = if (ncol(data$replicated) > 1L) apply(data$replicated, 1L, stats::sd) else NA_real_,
      ZeroFraction = rowMeans(data$replicated == 0), OneFraction = rowMeans(data$replicated == 1))
    count <- min(50L, nrow(data$replicated))
    curves <- c(list(data$observed), lapply(seq_len(count), function(i) data$replicated[i, ]))
    ecdfs[[kind]] <- do.call(rbind, lapply(seq_along(curves), function(i) {
      x <- sort(unique(c(0, curves[[i]], 1)))
      data.frame(Outcome = outcome, Model = model, Variant = variant, Key = key, Subset = kind,
        Replicate = i - 1L, X = x, ECDF = stats::ecdf(curves[[i]])(x),
        Type = if (i == 1L) "observed" else "replicated")
    }))
  }
  intervals <- if (exists("interval_check", envir = context, inherits = FALSE)) {
    list(summary = context$interval_check, source_rows = context$obs[context$ir, , drop = FALSE],
         probability_draws = context$probabilities)
  } else NULL
  if (!is.null(intervals) && (any(!is.finite(intervals$probability_draws)) ||
      any(intervals$probability_draws < 0 | intervals$probability_draws > 1))) {
    stop("Sensitivity interval probabilities are invalid.")
  }
  draw_selection <- if (outcome == "joint") data.frame(DrawMatrixRow = context$use,
    Chain = (context$use - 1L) %/% dim(context$da)[1L] + 1L,
    PostWarmupIteration = (context$use - 1L) %% dim(context$da)[1L] + 1L) else NULL
  list(outcome = outcome, model = model, variant = variant, key = key,
    source_hashes = context$prepared$input_hashes, ppc_sets = context$ppc_sets, source_rows = sources,
    joint_draw_selection = draw_selection, intervals = intervals,
    selection = context$selected[context$selected$Model == model, , drop = FALSE],
    rng_before_ppc = rng_before, rng_after_ppc = rng_after,
    quantity = "in-sample posterior predictive diagnostic; not held-out validation",
    ecdf_selection_rule = "observed=0; unchanged first min(50,nrep) rows of 04_PPC replicated; no resampling",
    ecdf_plot_rule = "right-continuous post/after steps; curve support plus endpoints 0 and 1",
    observed_plot_data = do.call(rbind, observed), statistic_plot_data = do.call(rbind, statistics),
    ecdf_plot_data = do.call(rbind, ecdfs))
}

run_sensitivity_postfit <- function() {
  initialize_manual()
  run_dir <- RUN_DIR
  manual_hashes <- sensitivity_manual_check()
  plan_path <- file.path(analysis_root, "provenance", "fit_plan.json")
  plan_hash <- digest::digest(file = plan_path, algo = "sha256")
  plan <- jsonlite::read_json(plan_path, simplifyVector = TRUE)
  jobs <- plan$main_jobs[plan$main_jobs$variant != "primary", , drop = FALSE]
  if (nrow(jobs) != 16L || plan$sensitivity_fits != 16L || sum(jobs$variant == "beta_binomial") != 4L ||
      any(!jobs$outcome %in% c("binary", "joint")) || nrow(prepared$species) != 365L) {
    stop("Fit plan is not the prescribed 16-sensitivity / 365-species contract.")
  }
  invisible(lapply(unique(jobs$variant), sensitivity_block))
  primary_jobs <- unique(jobs[, c("outcome", "model"), drop = FALSE])
  primary_jobs$variant <- "primary"
  all_jobs <- rbind(primary_jobs, jobs)
  selected <- sensitivity_selection(run_dir, all_jobs)
  selected_key <- sensitivity_selection_key(selected)
  prepared_hash <- digest::digest(file = file.path(run_dir, "prepared.rds"), algo = "sha256")
  results_dir <- file.path(run_dir, "results")
  audit_dir <- file.path(results_dir, "sensitivity_postfit_audit",
    paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_", Sys.getpid()))
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  status <- list(status = "RUNNING", pid = Sys.getpid(), started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    fit_plan_sha256 = plan_hash, selected_identity = selected_key, audit_directory = audit_dir,
    interpretation = "Expected-value sensitivity and training-data PPC; no cross-family LOO ranking")
  produced <- character()
  write_status <- function() {
    atomic_json(status, file.path(audit_dir, "status.json"))
    atomic_json(status, file.path(results_dir, "postfit_sensitivity_status.json"))
  }
  register <- function(paths) {
    if (any(!file.exists(paths)) || any(file.info(paths)$size <= 0)) stop("Required sensitivity output missing.")
    produced <<- unique(c(produced, paths))
  }
  current <- function() {
    if (!identical(sensitivity_manual_check(), manual_hashes) ||
        !identical(digest::digest(file = plan_path, algo = "sha256"), plan_hash) ||
        !identical(digest::digest(file = file.path(run_dir, "prepared.rds"), algo = "sha256"), prepared_hash) ||
        !identical(sensitivity_selection_key(sensitivity_selection(run_dir, all_jobs)), selected_key)) {
      stop("Manual, plan, prepared data, or selected fits changed during sensitivity postfit.")
    }
    for (name in names(prepared$input_paths)) if (!identical(
      digest::digest(file = prepared$input_paths[[name]], algo = "sha256"), prepared$input_hashes[[name]])) {
      stop("Original input changed: ", name)
    }
  }
  write_status()
  tryCatch({
    utils::write.csv(selected, file.path(audit_dir, "selected_fits.csv"), row.names = FALSE)
    # Baseline primary diagnostics must already exist for the exact selected keys.
    for (outcome in unique(primary_jobs$outcome)) {
      context <- sensitivity_load(run_dir, outcome, "primary", selected)
      dg <- utils::read.csv(file.path(results_dir, paste0("diagnostics_", outcome, "_primary.csv")), stringsAsFactors = FALSE)
      for (model in names(context$bundles)) {
        bundle <- context$bundles[[model]]
        sensitivity_verify_request(bundle, outcome, model, "primary", run_dir)
        row <- dg[dg$Model == model & dg$Key == bundle$key, , drop = FALSE]
        if (nrow(row) != 1L || is.na(row$Status) || row$Status != "PASS") {
          stop("Run primary 05 diagnostics first for the current fit: ", outcome, "/", model)
        }
      }
      rm(context); invisible(gc())
    }
    groups <- unique(jobs[, c("outcome", "variant"), drop = FALSE])
    diagnostic_tables <- list()
    for (i in seq_len(nrow(groups))) {
      current()
      outcome <- groups$outcome[i]; variant <- groups$variant[i]
      status$stage <- paste("diagnostics", outcome, variant, sep = "/"); write_status()
      context <- sensitivity_load(run_dir, outcome, variant, selected)
      for (model in names(context$bundles)) sensitivity_verify_request(context$bundles[[model]],
        outcome, model, variant, run_dir)
      run_block("05_诊断与模型比较.md", "05_DIAGNOSTICS", target = context)
      diagnostic_tables[[paste(outcome, variant)]] <- context$diagnostics
      register(file.path(results_dir, paste0(c("diagnostics_", "parameter_summary_"), outcome, "_", variant, ".csv")))
      rm(context); invisible(gc())
    }
    diagnostics <- do.call(rbind, diagnostic_tables)
    if (nrow(diagnostics) != 16L || anyNA(diagnostics$Status) || any(diagnostics$Status != "PASS")) {
      stop("All 16 selected sensitivities must pass original 05 diagnostics before formal comparisons.")
    }
    comparison_rows <- list()
    for (i in seq_len(nrow(jobs))) {
      current()
      job <- jobs[i, , drop = FALSE]
      context <- new.env(parent = .GlobalEnv)
      context$RUN_DIR <- run_dir; context$OUTCOME <- job$outcome; context$prepared <- prepared
      status$stage <- paste("expected_value_comparison", job$outcome, job$model, job$variant, sep = "/"); write_status()
      run_block("04_模型检查与敏感性.md", "04_COMPARE_SENSITIVITY", target = context,
        overrides = list(SENSITIVITY_VARIANT = job$variant, SENSITIVITY_MODEL = job$model))
      comparison <- context$comparison
      if (nrow(comparison) != 365L || !identical(comparison$Species, prepared$species$Species) ||
          anyDuplicated(comparison$Species) || anyNA(comparison$Supported)) stop("Sensitivity species universe changed.")
      numeric_columns <- setdiff(names(comparison), c("Species", "Supported"))
      values <- as.matrix(comparison[, numeric_columns, drop = FALSE])
      if (any(!is.finite(values[comparison$Supported, , drop = FALSE])) ||
          any(!is.na(values[!comparison$Supported, , drop = FALSE]))) stop("Sensitivity support masking failed.")
      comparison$Outcome <- job$outcome; comparison$Model <- job$model; comparison$Variant <- job$variant
      comparison$PrimaryKey <- selected$Key[selected$Outcome == job$outcome & selected$Model == job$model & selected$Variant == "primary"]
      comparison$AlternativeKey <- selected$Key[selected$Outcome == job$outcome & selected$Model == job$model & selected$Variant == job$variant]
      comparison$Quantity <- if (job$outcome == "binary") "posterior PrHigh" else "posterior expected ratio"
      comparison$ValidationScope <- "same fitted observations; sensitivity comparison, not held-out validation"
      comparison_rows[[i]] <- comparison
      register(file.path(results_dir, paste0("sensitivity_", job$outcome, "_", job$model, "_", job$variant, ".csv")))
      rm(context)
    }
    all_ppc <- all_observed <- all_statistics <- all_ecdf <- all_intervals <- list()
    for (i in seq_len(nrow(groups))) {
      outcome <- groups$outcome[i]; variant <- groups$variant[i]
      current()
      context <- sensitivity_load(run_dir, outcome, variant, selected)
      context$diagnostics <- diagnostic_tables[[paste(outcome, variant)]]
      for (model in names(context$bundles)) {
        current()
        status$stage <- paste("PPC", outcome, model, variant, sep = "/"); write_status()
        if (exists("interval_check", envir = context, inherits = FALSE)) rm("interval_check", envir = context)
        run_block("04_模型检查与敏感性.md", "04_SELECT", overrides = list(CHECK_MODEL = model), target = context)
        rng_before <- .Random.seed
        run_block("04_模型检查与敏感性.md", "04_PPC", target = context)
        payload <- sensitivity_ppc_data(context, rng_before, .Random.seed)
        raw_file <- file.path(results_dir, paste0("ppc_raw_", outcome, "_", model, "_", variant, ".rds"))
        saveRDS(payload, raw_file)
        register(c(raw_file, file.path(results_dir, paste0("ppc_summary_", outcome, "_", model, "_", variant, ".csv")),
          file.path(results_dir, paste0("ppc_", outcome, "_", model, "_", variant, "_", names(context$ppc_sets), ".pdf"))))
        item <- paste(outcome, model, variant)
        summary <- context$ppc_summary
        summary$Outcome <- outcome; summary$Model <- model; summary$Variant <- variant; summary$Key <- context$obj$key
        summary$ValidationScope <- "training-data posterior predictive check"
        all_ppc[[item]] <- summary; all_observed[[item]] <- payload$observed_plot_data
        all_statistics[[item]] <- payload$statistic_plot_data; all_ecdf[[item]] <- payload$ecdf_plot_data
        if (!is.null(payload$intervals)) {
          intervals <- payload$intervals$summary
          intervals$Outcome <- outcome; intervals$Model <- model; intervals$Variant <- variant; intervals$Key <- context$obj$key
          all_intervals[[item]] <- intervals
          register(file.path(results_dir, paste0("interval_check_", model, "_", variant, ".csv")))
        }
        rm(payload)
      }
      rm(context); invisible(gc())
    }
    long <- do.call(rbind, comparison_rows)
    if (nrow(long) != 5840L || anyDuplicated(paste(long$Outcome, long$Model, long$Variant, long$Species)) ||
        length(all_ppc) != 16L) stop("Sensitivity output coverage is incomplete.")
    tables <- list(sensitivity_expected_values_long = long, diagnostics_all_sensitivity = diagnostics,
      ppc_summary_all_sensitivity = do.call(rbind, all_ppc), ppc_observed_plot_data_sensitivity = do.call(rbind, all_observed),
      ppc_statistic_plot_data_sensitivity = do.call(rbind, all_statistics), ppc_ecdf_plot_data_sensitivity = do.call(rbind, all_ecdf))
    if (length(all_intervals)) tables$interval_check_all_sensitivity <- do.call(rbind, all_intervals)
    for (name in names(tables)) {
      path <- file.path(results_dir, paste0(name, ".csv"))
      utils::write.csv(tables[[name]], path, row.names = FALSE, na = "")
      register(path)
    }
    current()
    manifest <- data.frame(File = substring(produced, nchar(run_dir) + 2L), Bytes = file.info(produced)$size,
      SHA256 = vapply(produced, function(path) digest::digest(file = path, algo = "sha256"), character(1)))
    utils::write.csv(manifest, file.path(audit_dir, "output_manifest.csv"), row.names = FALSE)
    status$status <- "COMPLETE_DIAGNOSTICS_AND_TRAINING_PPC"
    status$stage <- "complete"; status$comparison_rows <- nrow(long); status$ppc_models <- length(all_ppc)
    status$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    status$output_manifest <- file.path(audit_dir, "output_manifest.csv")
    write_status()
    cat("SENSITIVITY_POSTFIT_COMPLETE", nrow(long), "rows", length(all_ppc), "PPC models\n")
  }, error = function(error) {
    failed <- status; failed$status <- "ERROR"; failed$error <- conditionMessage(error); failed$partial_outputs <- produced
    status <<- failed
    write_status()
    stop(error)
  })
}

if (length(commandArgs(trailingOnly = TRUE))) stop("postfit_sensitivity.R takes no arguments.")
run_sensitivity_postfit()
