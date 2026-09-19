# Orchestration only. Statistical expressions are evaluated from the frozen manual.
# No fitting, input rewriting, or changes to common.R are performed by this script.
source("/project/work/ratio_analysis_20260914/scripts/common.R", local = .GlobalEnv)

manual_files <- c(
  "00_开始与使用顺序.md", "01_输入与编码.md", "02_独立分类模型.md",
  "03_联合比率模型.md", "04_模型检查与敏感性.md",
  "05_诊断与模型比较.md", "07_物种预测与区间.md"
)

configure_postfit_cores <- function() {
  requested <- Sys.getenv("RATIO_POST_CORES", unset = "1")
  if (!grepl("^[1-4]$", requested)) {
    stop("RATIO_POST_CORES must be an integer from 1 to 4; got: ", requested)
  }
  cores <- as.integer(requested)
  # Only this postprocessing R process is changed. verify_request reconstructs
  # sampling CORES in its own environment from each real parent's saved request.
  assign("CORES", cores, envir = .GlobalEnv)
  options(mc.cores = cores)
  cat("POSTFIT_CPU_CONFIGURATION", cores, "postprocessing core(s); parent sampling identity preserved\n")
  cores
}

verify_manual <- function() {
  manifest_file <- file.path(manual_dir, "MANIFEST.csv")
  anchor <- readLines(file.path(manual_dir, "MANIFEST.sha256"), warn = FALSE)
  anchor <- anchor[grepl("  MANIFEST[.]csv$", anchor)]
  if (length(anchor) != 1L ||
      !identical(substr(anchor, 1L, 64L), digest::digest(file = manifest_file, algo = "sha256"))) {
    stop("Frozen manual manifest does not match its SHA256 anchor.")
  }
  manifest <- utils::read.csv(manifest_file, stringsAsFactors = FALSE, check.names = FALSE)
  rows <- match(manual_files, manifest$File)
  if (anyNA(rows) || anyDuplicated(manifest$File)) stop("Manual manifest coverage is invalid.")
  actual <- vapply(manual_files, function(name) {
    digest::digest(file = file.path(manual_dir, name), algo = "sha256")
  }, character(1))
  if (!identical(unname(actual), manifest$SHA256[rows])) stop("A frozen manual file has changed.")
  data.frame(File = manual_files, SHA256 = unname(actual), stringsAsFactors = FALSE)
}

primary_selection <- function(run_dir, required_models) {
  index_file <- file.path(run_dir, "fit_index.csv")
  if (!file.exists(index_file)) stop("The parent must first create the selected fit_index.csv.")
  index <- utils::read.csv(index_file, stringsAsFactors = FALSE, check.names = FALSE)
  columns <- c("Outcome", "Variant", "Model", "Key", "RelativeFile", "FileSHA256", "SelectedAt")
  if (!all(columns %in% names(index)) || anyNA(index[, columns, drop = FALSE])) {
    stop("Selected fit index has missing columns or values.")
  }
  selected <- index[index$Variant == "primary", columns, drop = FALSE]
  if (any(!selected$Outcome %in% c("binary", "joint")) ||
      any(!selected$Model %in% required_models)) stop("Unexpected primary outcome or model.")
  pair <- paste(selected$Outcome, selected$Model, sep = ":")
  selected <- selected[!duplicated(pair, fromLast = TRUE), , drop = FALSE]
  expected <- as.vector(t(outer(c("binary", "joint"), required_models, paste, sep = ":")))
  actual <- paste(selected$Outcome, selected$Model, sep = ":")
  if (nrow(selected) != 20L || !setequal(actual, expected)) {
    stop("Both routes need all ten selected primary fits. Missing: ",
         paste(setdiff(expected, actual), collapse = ", "))
  }
  selected <- selected[match(expected, actual), , drop = FALSE]
  rownames(selected) <- NULL
  if (any(!grepl("^[0-9a-f]{64}$", selected$Key)) ||
      any(!grepl("^[0-9a-f]{64}$", selected$FileSHA256))) stop("Invalid fit SHA256 or request key.")
  expected_relative <- file.path("fits", selected$Outcome, "primary",
    paste0(selected$Model, "_", substr(selected$Key, 1L, 16L), ".rds"))
  if (!identical(selected$RelativeFile, expected_relative)) {
    stop("A selected file is outside its primary model identity path.")
  }
  selected
}

selection_identity <- function(selected) {
  digest::digest(selected[, setdiff(names(selected), "SelectedAt"), drop = FALSE], algo = "sha256")
}

new_context <- function(run_dir, outcome = NULL) {
  context <- new.env(parent = .GlobalEnv)
  context$RUN_DIR <- run_dir
  if (!is.null(outcome)) context$OUTCOME <- outcome
  context$VARIANT <- "primary"
  context
}

load_primary <- function(run_dir, outcome) {
  context <- new_context(run_dir, outcome)
  run_block("05_诊断与模型比较.md", "05_LOAD",
    overrides = list(OUTCOME = outcome, VARIANT = "primary"), target = context)
  if (length(context$bundles) != 10L ||
      !setequal(names(context$bundles), context$prepared$model_grid$Model)) {
    stop("05_LOAD did not select the complete ten-model route.")
  }
  context
}

verify_request <- function(bundle, outcome, model, run_dir) {
  request <- bundle$request
  if (!identical(request$outcome, outcome) || !identical(request$model, model) ||
      !identical(request$variant, "primary")) stop("Indexed model and embedded request disagree.")
  sampling <- request$sampling
  sample_names <- c("seed", "chains", "cores", "iter", "warmup", "adapt_delta", "max_treedepth")
  if (!setequal(names(sampling), sample_names) ||
      any(lengths(sampling) != 1L) || any(!is.finite(unlist(sampling))) ||
      sampling$chains != 4L || sampling$cores != 4L || sampling$iter <= sampling$warmup ||
      sampling$warmup < 1L || sampling$adapt_delta <= 0 || sampling$adapt_delta >= 1) {
    stop("Invalid or unexpected sampling identity in ", outcome, "/", model)
  }
  stan_fit <- if (outcome == "binary") bundle$fit$fit else bundle$fit
  if (length(rstan::get_sampler_params(stan_fit, inc_warmup = FALSE)) != 4L) {
    stop("The selected fit does not contain four actual posterior chains.")
  }
  # Rebuild the request using manual preparation expressions, never FIT_SAVE or COMPILE.
  # Selected retry sampling is retained; primary priors, data, code and encoding are rebuilt.
  expected <- new_context(run_dir, outcome)
  run_block("00_开始与使用顺序.md", "00_SETTINGS", target = expected)
  expected$RUN_DIR <- run_dir
  expected$MODEL_NAME <- model
  expected$VARIANT <- "primary"
  mapping <- c(seed = "SEED", chains = "CHAINS", cores = "CORES", iter = "ITER",
               warmup = "WARMUP", adapt_delta = "ADAPT_DELTA", max_treedepth = "MAX_TREEDEPTH")
  for (name in names(mapping)) assign(mapping[[name]], sampling[[name]], envir = expected)
  if (outcome == "binary") {
    run_block("02_独立分类模型.md", "02_PREPARE", target = expected)
  } else {
    run_block("03_联合比率模型.md", "03_STAN_MODEL", target = expected)
    expected$joint_code_hash <- digest::digest(expected$joint_model_code,
      algo = "sha256", serialize = FALSE)
    run_block("03_联合比率模型.md", "03_PREPARE", target = expected)
  }
  if (!identical(expected$request, request) || !identical(expected$request_key, bundle$key)) {
    different <- union(names(expected$request), names(request))
    different <- different[!vapply(different, function(name) {
      identical(expected$request[[name]], request[[name]])
    }, logical(1))]
    stop("Selected fit is not the frozen manual's current primary request: ",
         outcome, "/", model, "; fields: ", paste(different, collapse = ", "))
  }
  invisible(TRUE)
}

export_blueprint_term_map <- function(prepared, output_file) {
  rows <- list()
  for (outcome in c("binary", "joint")) {
    for (group in unique(prepared$model_grid$Group)) {
      blueprint <- prepared$blueprints[[paste(outcome, group, sep = "_")]]
      if (is.null(blueprint)) stop("Missing blueprint: ", outcome, "/", group)
      observed_index <- match(blueprint$observed_species, prepared$species$Species)
      if (anyNA(observed_index) || anyDuplicated(observed_index)) stop("Invalid blueprint training species.")
      x_observed <- cbind(Intercept = 1, blueprint$X[observed_index, , drop = FALSE])
      if (ncol(x_observed) != blueprint$parameter_columns ||
          qr(x_observed)$rank != blueprint$rank) stop("Blueprint design rank or dimensions changed.")
      nonest <- estimability::nonest.basis(x_observed)
      identifiable <- estimability::is.estble(diag(ncol(x_observed)), nonest)
      if (length(identifiable) != ncol(x_observed) || anyNA(identifiable)) {
        stop("Cannot determine coefficient-direction estimability.")
      }
      intercept <- data.frame(Outcome = outcome, Group = group, Column = "Intercept",
        OriginalTerm = "(Intercept)", Variable = "", Level = "", ReferenceLevel = "",
        IdentifiableDirection = identifiable[1L],
        ParameterName = if (outcome == "binary") "b_Intercept" else "alpha",
        TermType = "centered_intercept", Center = NA_real_,
        DesignRank = blueprint$rank, DesignColumns = blueprint$parameter_columns,
        RankDeficientModel = blueprint$rank < blueprint$parameter_columns,
        ObservedSpecies = length(observed_index), StoredObservedLevelOrder = "",
        ContrastType = "not_applicable",
        ReferenceRecovery = "centered intercept has no single factor reference category",
        EstimabilityMethod = "is.estble(unit_vector, nonest.basis(cbind(Intercept, X_observed)))",
        stringsAsFactors = FALSE)
      rows[[paste(outcome, group, "Intercept")]] <- intercept
      if (!ncol(blueprint$X)) next
      if (!identical(colnames(blueprint$X), blueprint$columns$Column) ||
          anyDuplicated(blueprint$columns$Term) || any(!is.finite(blueprint$columns$Center))) {
        stop("Invalid blueprint column identity or centers.")
      }
      raw <- sweep(blueprint$X, 2L, blueprint$columns$Center, FUN = "+")
      # Raw factor objects and contrasts attributes were not retained by 01. Recover
      # coding from saved X + Center, then verify R treatment contrasts on all panel rows.
      # The saved observed-level order is used directly; no alphabetic reference guess.
      candidates <- list()
      panel_levels <- list()
      for (variable in blueprint$variables) {
        values <- as.character(prepared$species[[variable]])
        observed_levels <- blueprint$levels[[variable]]
        if (is.null(observed_levels) || anyDuplicated(observed_levels) ||
            !setequal(observed_levels, unique(values[observed_index]))) {
          stop("Stored factor levels do not match observed species: ", variable)
        }
        panel_levels[[variable]] <- c(observed_levels, setdiff(unique(values), observed_levels))
        candidates[[variable]] <- data.frame(Variable = variable, Level = panel_levels[[variable]],
          OriginalTerm = paste0(variable, panel_levels[[variable]]), stringsAsFactors = FALSE)
      }
      candidates <- do.call(rbind, candidates)
      matches <- lapply(blueprint$columns$Term, function(term) which(candidates$OriginalTerm == term))
      if (any(lengths(matches) != 1L)) stop("A retained contrast term cannot be resolved uniquely.")
      term_map <- candidates[unlist(matches), , drop = FALSE]
      references <- character()
      for (variable in unique(term_map$Variable)) {
        columns <- which(term_map$Variable == variable)
        values <- as.character(prepared$species[[variable]])
        observed_levels <- blueprint$levels[[variable]]
        level_contrasts <- do.call(rbind, lapply(observed_levels, function(level) {
          values_for_level <- raw[observed_index[values[observed_index] == level], columns, drop = FALSE]
          first <- values_for_level[1L, ]
          if (any(abs(sweep(values_for_level, 2L, first, FUN = "-")) > 1e-12)) {
            stop("Saved contrast is not constant within factor level: ", variable, "/", level)
          }
          first
        }))
        reference_rows <- which(rowSums(abs(level_contrasts) > 1e-12) == 0L)
        if (length(reference_rows) != 1L) {
          stop("Reference cannot be uniquely recovered from observed all-zero contrast row: ", variable)
        }
        reference <- observed_levels[reference_rows]
        references[[variable]] <- reference
        factor_values <- factor(values, levels = panel_levels[[variable]])
        treatment <- stats::contr.treatment(levels(factor_values),
          base = match(reference, levels(factor_values)))
        if (!all(term_map$Level[columns] %in% colnames(treatment))) {
          stop("Retained contrast level disagrees with reconstructed treatment contrast.")
        }
        contrasts(factor_values) <- treatment
        reconstructed <- stats::contrasts(factor_values)[as.integer(factor_values),
          term_map$Level[columns], drop = FALSE]
        if (anyNA(reconstructed) || any(abs(reconstructed - raw[, columns, drop = FALSE]) > 1e-12)) {
          stop("R treatment contrast does not reproduce saved full-panel design: ", variable)
        }
      }
      for (column in seq_len(ncol(blueprint$X))) {
        variable <- term_map$Variable[column]
        row <- intercept
        row$Column <- blueprint$columns$Column[column]
        row$OriginalTerm <- blueprint$columns$Term[column]
        row$Variable <- variable
        row$Level <- term_map$Level[column]
        row$ReferenceLevel <- references[[variable]]
        row$IdentifiableDirection <- identifiable[column + 1L]
        row$ParameterName <- if (outcome == "binary") paste0("b_", row$Column) else paste0("beta[", column, "]")
        row$TermType <- "factor_contrast"
        row$Center <- blueprint$columns$Center[column]
        row$StoredObservedLevelOrder <- paste(blueprint$levels[[variable]], collapse = "|")
        row$ContrastType <- "treatment_verified_against_saved_design"
        row$ReferenceRecovery <- "unique all-zero observed contrast row in X+Center; R contrast verified on all panel species"
        rows[[paste(outcome, group, row$Column)]] <- row
      }
    }
  }
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  if (anyDuplicated(paste(result$Outcome, result$Group, result$Column))) stop("Duplicate blueprint term mapping.")
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(result, output_file, row.names = FALSE, na = "")
  result
}

ppc_ecdf_coordinates <- function(outcome, model, subset, observed, replicated, key) {
  count <- min(50L, nrow(replicated))
  if (count < 1L) stop("PPC has no replicates for an ECDF overlay.")
  curves <- c(list(observed), lapply(seq_len(count), function(i) replicated[i, ]))
  coordinates <- lapply(seq_along(curves), function(i) {
    values <- curves[[i]]
    if (!length(values) || any(!is.finite(values)) || any(values < 0 | values > 1)) {
      stop("Invalid PPC values supplied to ECDF export.")
    }
    x <- sort(unique(c(0, values, 1)))
    data.frame(Outcome = outcome, Model = model, Subset = subset, Replicate = i - 1L,
      X = x, ECDF = stats::ecdf(values)(x), Type = if (i == 1L) "observed" else "replicated",
      Variant = "primary", Key = key, stringsAsFactors = FALSE)
  })
  do.call(rbind, coordinates)
}

ppc_payload <- function(context, rng_before, rng_after) {
  outcome <- context$OUTCOME
  model <- context$CHECK_MODEL
  bundle <- context$obj
  source_rows <- list()
  observed_rows <- list()
  statistic_rows <- list()
  ecdf_rows <- list()
  for (kind in names(context$ppc_sets)) {
    simulation <- context$ppc_sets[[kind]]
    source <- if (outcome == "binary") bundle$request$training else {
      bundle$request$source_rows[bundle$request$source_rows$Type == kind, , drop = FALSE]
    }
    record_id <- if (outcome == "binary") source$BinaryID else source$RecordID
    if (length(simulation$observed) != nrow(source) ||
        ncol(simulation$replicated) != nrow(source) ||
        any(!is.finite(simulation$observed)) || any(!is.finite(simulation$replicated)) ||
        any(simulation$observed < 0 | simulation$observed > 1) ||
        any(simulation$replicated < 0 | simulation$replicated > 1)) {
      stop("PPC source map or generated values failed validation: ", outcome, "/", model, "/", kind)
    }
    source_rows[[kind]] <- source
    observed_rows[[kind]] <- data.frame(Outcome = outcome, Model = model, Variant = "primary",
      Key = bundle$key, Subset = kind, ObservationIndex = seq_len(nrow(source)),
      RecordID = record_id, Species = as.character(source$Species), Observed = simulation$observed)
    statistic_rows[[kind]] <- data.frame(Outcome = outcome, Model = model, Variant = "primary",
      Key = bundle$key, Subset = kind, Replicate = seq_len(nrow(simulation$replicated)),
      Mean = rowMeans(simulation$replicated),
      SD = if (ncol(simulation$replicated) > 1L) apply(simulation$replicated, 1L, stats::sd) else NA_real_,
      ZeroFraction = rowMeans(simulation$replicated == 0),
      OneFraction = rowMeans(simulation$replicated == 1))
    ecdf_rows[[kind]] <- ppc_ecdf_coordinates(outcome, model, kind,
      simulation$observed, simulation$replicated, bundle$key)
  }
  intervals <- NULL
  draw_selection <- NULL
  if (outcome == "joint") {
    n_iteration <- dim(context$da)[1L]
    draw_selection <- data.frame(DrawMatrixRow = context$use,
      Chain = (context$use - 1L) %/% n_iteration + 1L,
      PostWarmupIteration = (context$use - 1L) %% n_iteration + 1L)
    if (exists("interval_check", envir = context, inherits = FALSE)) {
      intervals <- list(summary = context$interval_check,
        source_rows = context$obs[context$ir, , drop = FALSE],
        probability_draws = context$probabilities,
        draw_order = "all posterior iterations within each chain; rstan permuted=FALSE")
      if (any(!is.finite(intervals$probability_draws)) ||
          any(intervals$probability_draws < 0 | intervals$probability_draws > 1)) {
        stop("Interval posterior probabilities are invalid.")
      }
    }
  }
  list(outcome = outcome, model = model, variant = "primary", key = bundle$key,
    selection = context$selected[context$selected$Model == model, , drop = FALSE],
    source_hashes = context$prepared$input_hashes, seed = get("SEED", envir = context, inherits = TRUE),
    quantity = "posterior predictive replicate; in-sample diagnostic, not expected-value uncertainty",
    ppc_sets = context$ppc_sets, source_rows = source_rows,
    joint_draw_selection = draw_selection,
    binary_draw_selection_note = if (outcome == "binary") {
      "04_PPC delegates draw selection to brms::posterior_predict; exact internal IDs are not exposed."
    } else NULL,
    rng_before_ppc = rng_before, rng_after_ppc = rng_after, intervals = intervals,
    ecdf_selection_rule = "Replicate 0 is observed; replicates 1:min(50,nrep) are unchanged first rows of 04_PPC replicated; no resampling",
    ecdf_plot_rule = "right-continuous step function, evaluated at each curve's unique values plus domain endpoints 0 and 1; draw with post/after steps",
    observed_plot_data = do.call(rbind, observed_rows),
    statistic_plot_data = do.call(rbind, statistic_rows),
    ecdf_plot_data = do.call(rbind, ecdf_rows))
}

validate_predictions <- function(context, selected) {
  models <- c("M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P")
  long <- context$long_output
  wide <- context$wide_output
  species <- context$prepared$species$Species
  if (length(species) != 365L || nrow(long) != 2190L || nrow(wide) != 365L ||
      anyDuplicated(paste(long$Species, long$Model)) || anyDuplicated(wide$Species) ||
      !identical(wide$Species, species) || !setequal(long$Model, models)) {
    stop("07 output is not the required 2190-row long / 365-row wide species universe.")
  }
  for (model in models) {
    rows <- long[long$Model == model, , drop = FALSE]
    if (!identical(rows$Species, species)) stop("07 species order differs between models.")
    for (outcome in c("binary", "joint")) {
      columns <- if (outcome == "binary") c("PrHighLower95", "PrHigh", "PrHighUpper95") else {
        c("RatioLower95", "PredictedRatio", "RatioUpper95")
      }
      support <- rows[[if (outcome == "binary") "BinarySupported" else "RatioSupported"]]
      values <- as.matrix(rows[, columns, drop = FALSE])
      draws <- context$expected_draws[[outcome]][[model]]
      if (anyNA(support) || !identical(colnames(draws), species) || ncol(draws) != 365L ||
          nrow(draws) < 1L || any(!is.finite(draws[, support, drop = FALSE])) ||
          any(draws[, support, drop = FALSE] < 0 | draws[, support, drop = FALSE] > 1) ||
          any(!is.na(draws[, !support, drop = FALSE])) ||
          any(!is.finite(values[support, , drop = FALSE])) ||
          any(!is.na(values[!support, , drop = FALSE])) ||
          any(values[support, 1L] > values[support, 2L]) ||
          any(values[support, 2L] > values[support, 3L])) {
        stop("07 support masking, draws, or quantile ordering failed: ", outcome, "/", model)
      }
    }
  }
  actual <- do.call(rbind, context$selection_used)
  expected <- selected[selected$Model %in% models, , drop = FALSE]
  actual <- actual[match(paste(expected$Outcome, expected$Model), paste(actual$Outcome, actual$Model)),
                   names(expected), drop = FALSE]
  rownames(actual) <- rownames(expected) <- NULL
  if (nrow(actual) != 12L || !identical(selection_identity(actual), selection_identity(expected))) {
    stop("07 used a different selected primary fit.")
  }
  invisible(TRUE)
}

run_primary_postfit <- function() {
  initialize_manual()
  postfit_cores <- configure_postfit_cores()
  frozen <- verify_manual()
  run_dir <- RUN_DIR
  required_models <- prepared$model_grid$Model
  if (length(required_models) != 10L || anyDuplicated(required_models) ||
      nrow(prepared$species) != 365L || anyDuplicated(prepared$species$Species)) {
    stop("Prepared data do not contain the prescribed ten models / 365 unique species.")
  }
  selected <- primary_selection(run_dir, required_models)
  selection_key <- selection_identity(selected)
  prepared_hash <- digest::digest(file = file.path(run_dir, "prepared.rds"), algo = "sha256")
  input_paths <- prepared$input_paths
  input_hashes <- prepared$input_hashes
  runner_files <- file.path(analysis_root, "scripts", c("common.R", "postfit_primary.R"))
  runner_hashes <- vapply(runner_files, function(path) digest::digest(file = path, algo = "sha256"), character(1))
  term_map_file <- file.path(analysis_root, "provenance", "blueprint_term_map.csv")
  term_map <- export_blueprint_term_map(prepared, term_map_file)
  results_dir <- file.path(run_dir, "results")
  started <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  audit_dir <- file.path(results_dir, "postfit_primary_audit",
    paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_", Sys.getpid()))
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  produced <- character()
  status <- list(status = "RUNNING", pid = Sys.getpid(), started_at = started,
    postfit_cores = postfit_cores, postfit_mc_cores = getOption("mc.cores"),
    postfit_cores_env = Sys.getenv("RATIO_POST_CORES", unset = "1"),
    selection_identity = selection_key, prepared_sha256 = prepared_hash,
    formal_output_gate = "PENDING_ALL_20_IDENTITIES_AND_DIAGNOSTICS",
    manual_files = frozen, script_sha256 = as.list(runner_hashes), audit_directory = audit_dir,
    blueprint_term_map = list(file = term_map_file, rows = nrow(term_map),
      sha256 = digest::digest(file = term_map_file, algo = "sha256")))
  write_status <- function() {
    status$updated_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    atomic_json(status, file.path(audit_dir, "status.json"))
    atomic_json(status, file.path(results_dir, "postfit_primary_status.json"))
  }
  register <- function(paths) {
    if (any(!file.exists(paths)) || any(file.info(paths)$size <= 0)) {
      stop("A required output is missing or empty: ", paste(paths[!file.exists(paths)], collapse = ", "))
    }
    produced <<- unique(c(produced, paths))
  }
  current <- function() {
    for (name in names(input_paths)) {
      if (!identical(digest::digest(file = input_paths[[name]], algo = "sha256"), input_hashes[[name]])) {
        stop("An original input changed during postfit: ", name)
      }
    }
    if (!identical(selection_identity(primary_selection(run_dir, required_models)), selection_key) ||
        !identical(digest::digest(file = file.path(run_dir, "prepared.rds"), algo = "sha256"), prepared_hash) ||
        !identical(verify_manual(), frozen) ||
        !identical(vapply(runner_files, function(path) digest::digest(file = path, algo = "sha256"), character(1)), runner_hashes)) {
      stop("Inputs, primary selection, frozen manual, or runner changed during postfit.")
    }
  }
  write_status()
  tryCatch({
    utils::write.csv(selected, file.path(audit_dir, "selected_primary_fits.csv"), row.names = FALSE)
    all_diagnostics <- list()
    # No LOO, PPC, or species prediction is run until both complete routes pass this gate.
    for (outcome in c("binary", "joint")) {
      current()
      status$stage <- paste0("identity_and_diagnostics_", outcome)
      write_status()
      context <- load_primary(run_dir, outcome)
      for (model in required_models) verify_request(context$bundles[[model]], outcome, model, run_dir)
      run_block("05_诊断与模型比较.md", "05_DIAGNOSTICS", target = context)
      diagnostics <- context$diagnostics
      all_diagnostics[[outcome]] <- diagnostics
      register(file.path(results_dir, paste0(c("diagnostics_", "parameter_summary_"), outcome, "_primary.csv")))
      if (nrow(diagnostics) != 10L || anyDuplicated(diagnostics$Model) ||
          !setequal(diagnostics$Model, required_models) || anyNA(diagnostics$Status) ||
          any(!diagnostics$Status %in% c("PASS", "NEEDS_REVIEW"))) {
        stop("A primary route returned an unexpected diagnostic structure: ", outcome)
      }
      expected_keys <- selected$Key[selected$Outcome == outcome]
      if (!setequal(diagnostics$Key, expected_keys)) stop("Diagnostic keys do not match primary selection.")
      rm(context)
      invisible(gc())
    }
    combined_diagnostics <- do.call(rbind, all_diagnostics)
    if (any(combined_diagnostics$Status != "PASS")) {
      failed <- combined_diagnostics[combined_diagnostics$Status != "PASS", , drop = FALSE]
      stop("Primary sampling gate failed: ", paste(paste(failed$Outcome, failed$Model, sep = "/"), collapse = ", "))
    }
    current()
    status$formal_output_gate <- "PASS_ALL_20_IDENTITIES_AND_DIAGNOSTICS"
    write_status()
    all_ppc <- all_observed <- all_statistics <- all_ecdf <- all_intervals <- list()
    ranking_rows <- loo_estimate_rows <- list()
    for (outcome in c("binary", "joint")) {
      current()
      context <- load_primary(run_dir, outcome)
      context$diagnostics <- all_diagnostics[[outcome]]
      # Preserve previous rankings before reevaluation, so an error or failed PSIS gate cannot
      # leave a previous ranking at a filename readers could mistake for this execution.
      for (prefix in c("model_comparison_", "baseline_comparison_")) {
        old_file <- file.path(results_dir, paste0(prefix, outcome, "_primary.csv"))
        if (file.exists(old_file) && !file.rename(old_file, file.path(audit_dir, basename(old_file)))) {
          stop("Cannot archive a previous comparison before reevaluating PSIS.")
        }
      }
      status$stage <- paste0("loo_", outcome)
      write_status()
      run_block("05_诊断与模型比较.md", "05_LOO", target = context)
      register(file.path(results_dir, paste0(c("loo_objects_", "loo_status_", "loo_source_means_"),
        outcome, "_primary", c(".rds", ".csv", ".csv"))))
      loo_status <- context$loo_status
      if (nrow(loo_status) != 10L || anyDuplicated(loo_status$Model) ||
          !setequal(loo_status$Model, required_models) || anyNA(loo_status$Status) ||
          any(!loo_status$Status %in% c("PASS", "USE_GROUPED_CV"))) stop("Unexpected 05_LOO status structure.")
      ranking_ok <- all(loo_status$Status == "PASS")
      if (ranking_ok) {
        run_block("05_诊断与模型比较.md", "05_COMPARE", target = context)
        register(file.path(results_dir, paste0(c("model_comparison_", "baseline_comparison_"),
          outcome, "_primary.csv")))
      } else {
        cat("LOO_RANKING_REFUSED", outcome, "PSIS failed; retain diagnostics and use 06 grouped CV.\n")
      }
      ranking_rows[[outcome]] <- data.frame(Outcome = outcome, Variant = "primary",
        SamplingGate = "PASS", Models = 10L,
        RankingStatus = if (ranking_ok) "PASS" else "REFUSED_USE_GROUPED_CV",
        ModelsWithProblemRows = sum(loo_status$Status != "PASS"),
        ProblemRows = sum(loo_status$ProblemRows),
        HoldoutUnit = if (outcome == "binary") "species-aggregated binary row" else "original experiment record")
      for (model in required_models) {
        estimate <- context$loo_objects[[model]]$estimates
        if (ranking_ok && any(!is.finite(estimate))) stop("Non-finite LOO estimates despite a passed PSIS gate require investigation.")
        loo_estimate_rows[[paste(outcome, model)]] <- data.frame(Outcome = outcome, Model = model,
          Variant = "primary", Key = context$bundles[[model]]$key,
          ELPD_LOO = estimate["elpd_loo", "Estimate"], ELPD_LOO_SE = estimate["elpd_loo", "SE"],
          P_LOO = estimate["p_loo", "Estimate"], LOOIC = estimate["looic", "Estimate"],
          PSISStatus = loo_status$Status[match(model, loo_status$Model)],
          EstimatesFinite = all(is.finite(estimate)),
          RouteRankingStatus = ranking_rows[[outcome]]$RankingStatus)
      }
      # Each of the ten models uses the manual's SELECT and PPC blocks without statistical edits.
      for (model in required_models) {
        current()
        status$stage <- paste0("ppc_", outcome, "_", model)
        write_status()
        if (exists("interval_check", envir = context, inherits = FALSE)) rm("interval_check", envir = context)
        run_block("04_模型检查与敏感性.md", "04_SELECT", overrides = list(CHECK_MODEL = model), target = context)
        rng_before <- .Random.seed
        run_block("04_模型检查与敏感性.md", "04_PPC", target = context)
        payload <- ppc_payload(context, rng_before, .Random.seed)
        raw_file <- file.path(results_dir, paste0("ppc_raw_", outcome, "_", model, "_primary.rds"))
        saveRDS(payload, raw_file)
        register(c(raw_file,
          file.path(results_dir, paste0("ppc_summary_", outcome, "_", model, "_primary.csv")),
          file.path(results_dir, paste0("ppc_", outcome, "_", model, "_primary_", names(context$ppc_sets), ".pdf"))))
        summary <- context$ppc_summary
        summary$Outcome <- outcome; summary$Model <- model; summary$Variant <- "primary"
        summary$Key <- context$obj$key
        all_ppc[[paste(outcome, model)]] <- summary
        all_observed[[paste(outcome, model)]] <- payload$observed_plot_data
        all_statistics[[paste(outcome, model)]] <- payload$statistic_plot_data
        all_ecdf[[paste(outcome, model)]] <- payload$ecdf_plot_data
        if (!is.null(payload$intervals)) {
          intervals <- payload$intervals$summary
          intervals$Outcome <- outcome; intervals$Model <- model; intervals$Variant <- "primary"
          intervals$Key <- context$obj$key
          all_intervals[[model]] <- intervals
          register(file.path(results_dir, paste0("interval_check_", model, "_primary.csv")))
        }
        rm(payload)
      }
      rm(context)
      invisible(gc())
    }
    current()
    status$stage <- "species_predictions"
    write_status()
    prediction <- new_context(run_dir)
    run_block("07_物种预测与区间.md", "07_PREDICT", target = prediction)
    validate_predictions(prediction, selected)
    register(file.path(results_dir, c("species_predictions_long.csv", "species_predictions_wide.csv",
      "expected_value_draws.rds")))
    summaries <- list(
      diagnostics_all_primary = do.call(rbind, all_diagnostics),
      model_comparison_status_primary = do.call(rbind, ranking_rows),
      loo_estimates_all_primary = do.call(rbind, loo_estimate_rows),
      ppc_summary_all_primary = do.call(rbind, all_ppc),
      ppc_observed_plot_data_primary = do.call(rbind, all_observed),
      ppc_statistic_plot_data_primary = do.call(rbind, all_statistics),
      ppc_ecdf_plot_data_primary = do.call(rbind, all_ecdf)
    )
    if (length(all_intervals)) summaries$interval_check_all_primary <- do.call(rbind, all_intervals)
    for (name in names(summaries)) {
      path <- file.path(results_dir, paste0(name, ".csv"))
      utils::write.csv(summaries[[name]], path, row.names = FALSE, na = "")
      register(path)
    }
    if (length(all_ppc) != 20L) stop("Not all twenty primary models completed PPC.")
    current()
    manifest <- data.frame(File = substring(produced, nchar(run_dir) + 2L),
      Bytes = file.info(produced)$size,
      SHA256 = vapply(produced, function(path) digest::digest(file = path, algo = "sha256"), character(1)),
      stringsAsFactors = FALSE)
    utils::write.csv(manifest, file.path(audit_dir, "output_manifest.csv"), row.names = FALSE)
    status$status <- if (all(vapply(ranking_rows, function(row) row$RankingStatus == "PASS", logical(1)))) {
      "COMPLETE_ALL_PREDICTION_AND_LOO_GATES_PASS"
    } else "COMPLETE_WITH_GROUPED_CV_REQUIRED"
    status$stage <- "complete"
    status$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    status$primary_models <- 20L
    status$ppc_models <- length(all_ppc)
    status$species_long_rows <- nrow(prediction$long_output)
    status$species_wide_rows <- nrow(prediction$wide_output)
    status$loo_routes <- do.call(rbind, ranking_rows)
    status$output_manifest <- file.path(audit_dir, "output_manifest.csv")
    write_status()
    cat("POSTFIT_PRIMARY_OUTPUTS_COMPLETE", status$status, "\n")
    cat("POSTFIT_OUTPUT_MANIFEST", status$output_manifest, "\n")
    invisible(status)
  }, error = function(error) {
    failed_status <- status
    failed_status$status <- "ERROR"
    failed_status$error <- conditionMessage(error)
    failed_status$partial_outputs <- produced
    status <<- failed_status
    write_status()
    stop(error)
  })
}

arguments <- commandArgs(trailingOnly = TRUE)
if (identical(arguments, "--blueprint-only")) {
  initialize_manual()
  verify_manual()
  output_file <- file.path(analysis_root, "provenance", "blueprint_term_map.csv")
  term_map <- export_blueprint_term_map(prepared, output_file)
  print(unique(term_map[, c("Outcome", "Group", "DesignRank", "DesignColumns", "RankDeficientModel")]))
  cat("BLUEPRINT_TERM_MAP_PASS", nrow(term_map), "rows", output_file, "\n")
  cat("NO_FITS_OR_POSTERIOR_POSTPROCESSING_EXECUTED\n")
} else if (length(arguments)) {
  stop("Only --blueprint-only or no arguments are supported.")
} else {
  run_primary_postfit()
}
