# One explicitly scheduled same-A submatrix check. Never edits the formal fit index.
options(warn = 1) # Print each warning immediately to the task log; statistical settings are unchanged.
source("/project/work/ratio_analysis_20260914/scripts/common.R", local = .GlobalEnv)

matrix_manual_check <- function() {
  manifest_path <- file.path(manual_dir, "MANIFEST.csv")
  anchor <- readLines(file.path(manual_dir, "MANIFEST.sha256"), warn = FALSE)
  anchor <- anchor[grepl("  MANIFEST[.]csv$", anchor)]
  if (length(anchor) != 1L || !identical(substr(anchor, 1L, 64L),
      digest::digest(file = manifest_path, algo = "sha256"))) stop("Manual manifest anchor changed.")
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  files <- c("00_开始与使用顺序.md", "03_联合比率模型.md", "05_诊断与模型比较.md", "08_可选矩阵核查.md")
  actual <- vapply(files, function(file) digest::digest(file = file.path(manual_dir, file), algo = "sha256"), character(1))
  rows <- match(files, manifest$File)
  if (anyNA(rows) || !identical(unname(actual), manifest$SHA256[rows])) stop("Frozen matrix-check manual changed.")
  actual
}

matrix_parent_selection <- function(run_dir, outcome) {
  index <- utils::read.csv(file.path(run_dir, "fit_index.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("Outcome", "Variant", "Model", "Key", "RelativeFile", "FileSHA256", "SelectedAt")
  if (!all(required %in% names(index))) stop("Fit index is missing identity columns.")
  selected <- index[index$Outcome == outcome & index$Variant == "primary" & index$Model == "M3_P", required, drop = FALSE]
  if (!nrow(selected)) stop("No selected primary M3_P for ", outcome)
  selected <- selected[nrow(selected), , drop = FALSE]
  rownames(selected) <- NULL
  if (anyNA(selected) || !grepl("^[0-9a-f]{64}$", selected$Key) ||
      !grepl("^[0-9a-f]{64}$", selected$FileSHA256) ||
      selected$RelativeFile != file.path("fits", outcome, "primary", paste0("M3_P_", substr(selected$Key, 1L, 16L), ".rds"))) {
    stop("Invalid parent fit identity.")
  }
  selected
}

matrix_diagnostic_tables <- function(context) {
  chain_rows <- quality_rows <- quantity_rows <- status_rows <- list()
  for (side in c("full", "sub")) {
    summary <- as.data.frame(posterior::summarise_draws(context$pair_draws[[side]],
      "mean", "mcse_mean", "rhat", "ess_bulk", "ess_tail"))
    quality <- context$pair_quality[[side]]
    samplers <- context$pair_sampler[[side]]
    depth <- if (side == "full") context$full_bundle$request$sampling$max_treedepth else {
      context$sub_bundle$request$sampling$max_treedepth
    }
    chains <- do.call(rbind, lapply(seq_along(samplers), function(chain) {
      data <- samplers[[chain]]
      data.frame(Side = side, Chain = chain, Divergences = sum(data[, "divergent__"]),
        TreeDepthHits = sum(data[, "treedepth__"] >= depth),
        EBFMI = mean(diff(data[, "energy__"])^2) / stats::var(data[, "energy__"]))
    }))
    finite <- all(is.finite(as.matrix(summary[, c("mean", "mcse_mean", "rhat", "ess_bulk", "ess_tail")]))) &&
      all(is.finite(as.matrix(quality[, c("rhat", "ess_bulk", "ess_tail")]))) && all(is.finite(chains$EBFMI))
    passed <- finite && max(quality$rhat) < MAX_RHAT && min(quality$ess_bulk) >= MIN_ESS &&
      min(quality$ess_tail) >= MIN_ESS && all(summary$mcse_mean > 0) && max(summary$rhat) < MAX_RHAT &&
      min(summary$ess_bulk) >= MIN_ESS && min(summary$ess_tail) >= MIN_ESS &&
      sum(chains$Divergences) == 0 && sum(chains$TreeDepthHits) == 0 && min(chains$EBFMI) > .3
    status_rows[[side]] <- data.frame(Side = side, Status = if (passed) "PASS" else "NEEDS_REVIEW",
      MaxRhat = max(quality$rhat), MinBulkESS = min(quality$ess_bulk), MinTailESS = min(quality$ess_tail),
      MaxComparisonRhat = max(summary$rhat), MinComparisonBulkESS = min(summary$ess_bulk),
      MinComparisonTailESS = min(summary$ess_tail), MinimumComparisonMCSE = min(summary$mcse_mean),
      Divergences = sum(chains$Divergences), TreeDepthHits = sum(chains$TreeDepthHits),
      MinEBFMI = min(chains$EBFMI), AllFinite = finite)
    quality$Side <- side; summary$Side <- side
    chain_rows[[side]] <- chains; quality_rows[[side]] <- quality; quantity_rows[[side]] <- summary
  }
  list(status = do.call(rbind, status_rows), chains = do.call(rbind, chain_rows),
       parameters = do.call(rbind, quality_rows), quantities = do.call(rbind, quantity_rows))
}

run_matrix_job <- function(outcome, attempt) {
  if (!outcome %in% c("binary", "joint") || !attempt %in% 1:3) stop("Usage: matrix_job.R <binary|joint> <1|2|3>")
  initialize_manual()
  run_dir <- RUN_DIR
  manual_hashes <- matrix_manual_check()
  prepared_hash <- digest::digest(file = file.path(run_dir, "prepared.rds"), algo = "sha256")
  selected <- matrix_parent_selection(run_dir, outcome)
  parent_key <- selected$Key
  parent_dir <- file.path(run_dir, "matrix_checks", paste0(outcome, "_M3_P"), paste0("parent_", substr(parent_key, 1L, 16L)))
  job_dir <- file.path(parent_dir, paste0("attempt_", attempt))
  status_file <- file.path(job_dir, "status.json")
  if (attempt > 1L) {
    previous_file <- file.path(parent_dir, paste0("attempt_", attempt - 1L), "status.json")
    if (!file.exists(previous_file)) stop("A retry requires the previous attempt's diagnostic receipt.")
    previous <- jsonlite::read_json(previous_file, simplifyVector = TRUE)
    if (!identical(previous$parent_key, parent_key) || !identical(previous$status, "NEEDS_REVIEW") ||
        !isTRUE(previous$retry_eligible)) stop("Retry allowed only for a numerically inadequate subfit, not ReviewFlag selection.")
  }
  if (file.exists(status_file)) {
    previous <- jsonlite::read_json(status_file, simplifyVector = TRUE)
    if (identical(previous$status, "RUNNING")) stop("Unresolved RUNNING receipt: inspect it before restarting.")
  }
  dir.create(file.path(job_dir, "results"), recursive = TRUE, showWarnings = FALSE)
  status <- list(status = "RUNNING", outcome = outcome, model = "M3_P", attempt = attempt,
    pid = Sys.getpid(), parent_key = parent_key, parent_selection = selected, directory = job_dir,
    started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    comparison_rule = "original 08: abs(Difference) <= 2 * JointMCSE; no threshold or seed search")
  write_status <- function() atomic_json(status, status_file)
  write_status()
  tryCatch({
    context <- new.env(parent = .GlobalEnv)
    context$RUN_DIR <- run_dir
    run_block("05_诊断与模型比较.md", "05_LOAD", target = context,
      overrides = list(OUTCOME = outcome, VARIANT = "primary", fit_index = selected))
    parent <- context$bundles$M3_P
    expected_spec <- prepared$model_grid[match("M3_P", prepared$model_grid$Model), , drop = FALSE]
    if (!identical(parent$key, parent_key) || !identical(parent$request$outcome, outcome) ||
        !identical(parent$request$model, "M3_P") || !identical(parent$request$variant, "primary") ||
        !identical(parent$request$spec, expected_spec) ||
        (outcome == "binary" && !identical(parent$request$family, "binomial")) ||
        (outcome == "joint" && !identical(parent$request$count_family, "binomial")) ||
        !isTRUE(parent$request$spec$Phylo) || parent$request$sampling$chains != 4L || parent$request$sampling$cores != 4L) {
      stop("Parent is not the selected four-chain primary M3_P.")
    }
    # The original 05 diagnostic output is isolated from formal primary diagnostics.
    context$RUN_DIR <- job_dir
    run_block("05_诊断与模型比较.md", "05_DIAGNOSTICS", target = context)
    context$RUN_DIR <- run_dir
    if (nrow(context$diagnostics) != 1L || context$diagnostics$Status != "PASS") {
      stop("The current full-A parent does not pass original 05 diagnostics.")
    }
    overrides <- list(CHECK_MODEL = "M3_P", CHECK_DIR = job_dir)
    if (attempt > 1L) {
      multiplier <- 2L^(attempt - 1L)
      overrides$CHECK_ITER <- as.integer(parent$request$sampling$iter * multiplier)
      overrides$CHECK_WARMUP <- as.integer(parent$request$sampling$warmup * multiplier)
      overrides$CHECK_ADAPT_DELTA <- max(parent$request$sampling$adapt_delta, if (attempt == 2L) .999 else .9995)
      overrides$CHECK_MAX_TREEDEPTH <- as.integer(max(parent$request$sampling$max_treedepth, 15L))
    }
    run_block("08_可选矩阵核查.md", "08_PREPARE", overrides = overrides, target = context)
    if (!identical(context$check_request$parent_key, parent_key) ||
        !identical(context$check_key, digest::digest(context$check_request, algo = "sha256")) ||
        context$CHECK_SEED != parent$request$sampling$seed + 100001L) stop("Matrix request or fixed check seed is invalid.")
    if (outcome == "joint") {
      run_block("03_联合比率模型.md", "03_STAN_MODEL", target = context)
      context$joint_compiled_code_hash <- digest::digest(context$joint_model_code, algo = "sha256", serialize = FALSE)
      if (!identical(context$joint_compiled_code_hash, parent$request$code_hash) ||
          !identical(readLines(file.path(analysis_root, "environment", "joint_compiled.sha256"), warn = FALSE),
            context$joint_compiled_code_hash)) stop("Compiled joint kernel is not the exact parent/manual code.")
      context$joint_compiled <- readRDS(file.path(analysis_root, "environment", "joint_compiled.rds"))
    }
    status$stage <- "submatrix_fit"; status$check_key <- context$check_key
    status$check_request <- context$check_request
    status$full_species <- length(parent$species); status$submatrix_species <- length(context$observed_species)
    status$input_hashes <- context$prepared$input_hashes
    status$submatrix_file <- context$sub_file
    status$A_sha256 <- digest::digest(parent$request$A, algo = "sha256")
    status$A_submatrix_sha256 <- digest::digest(context$A_observed, algo = "sha256")
    write_status()
    saveRDS(list(parent_selection = selected, request = context$check_request, key = context$check_key,
      parent_sampling = parent$request$sampling, input_hashes = context$prepared$input_hashes,
      manual_hashes = manual_hashes, attempt = attempt), file.path(job_dir, "request_identity.rds"))
    run_block("08_可选矩阵核查.md", "08_FIT_SUBMATRIX", target = context)
    if (!identical(context$sub_bundle$request, context$check_request) ||
        !identical(context$sub_bundle$key, context$check_key) ||
        !identical(context$sub_bundle$species, context$observed_species)) stop("Submatrix fit identity changed.")
    sub_stan <- if (outcome == "binary") context$sub_bundle$fit$fit else context$sub_bundle$fit
    if (length(rstan::get_sampler_params(sub_stan, inc_warmup = FALSE)) != 4L) stop("Subfit does not contain four actual chains.")
    status$stage <- "comparison"; write_status()
    diagnostic_message <- "完整或子矩阵拟合需要进一步诊断，不能把数值比较写成通过。"
    comparison_error <- tryCatch({
      run_block("08_可选矩阵核查.md", "08_COMPARE", target = context)
      NULL
    }, error = function(error) {
      if (identical(conditionMessage(error), diagnostic_message)) error else stop(error)
    })
    tables <- matrix_diagnostic_tables(context)
    for (name in names(tables)) utils::write.csv(tables[[name]],
      file.path(job_dir, paste0("matrix_diagnostics_", name, ".csv")), row.names = FALSE, na = "")
    saveRDS(list(pair_quality = context$pair_quality, pair_draws = context$pair_draws,
      pair_sampler = context$pair_sampler, parent_selection = selected, check_request = context$check_request),
      file.path(job_dir, "matrix_comparison_evidence.rds"))
    if (!identical(matrix_manual_check(), manual_hashes) ||
        !identical(digest::digest(file = file.path(run_dir, "prepared.rds"), algo = "sha256"), prepared_hash) ||
        !identical(digest::digest(file = file.path(run_dir, selected$RelativeFile), algo = "sha256"), selected$FileSHA256) ||
        !identical(matrix_parent_selection(run_dir, outcome)[, setdiff(names(selected), "SelectedAt"), drop = FALSE],
          selected[, setdiff(names(selected), "SelectedAt"), drop = FALSE])) stop("Manual or parent selection changed during matrix job.")
    for (name in names(prepared$input_paths)) if (!identical(
      digest::digest(file = prepared$input_paths[[name]], algo = "sha256"), prepared$input_hashes[[name]])) stop("Input changed during matrix job.")
    status$diagnostics <- tables$status
    status$submatrix_file_sha256 <- digest::digest(file = context$sub_file, algo = "sha256")
    status$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    if (!is.null(comparison_error)) {
      status$status <- "NEEDS_REVIEW"
      status$message <- conditionMessage(comparison_error)
      status$retry_eligible <- tables$status$Status[tables$status$Side == "full"] == "PASS" &&
        tables$status$Status[tables$status$Side == "sub"] == "NEEDS_REVIEW" && attempt < 3L
      write_status()
      cat("MATRIX_JOB_NEEDS_REVIEW", outcome, attempt, "retry_eligible", status$retry_eligible, "\n")
      return(invisible(list(exit_code = 2L, status = status)))
    }
    if (any(tables$status$Status != "PASS")) stop("Independent diagnostic table disagrees with original 08 completion.")
    comparison <- context$comparison
    expected_flag <- ifelse(abs(comparison$Difference) <= 2 * comparison$JointMCSE,
      "within_2_MCSE", "review_difference")
    if (!identical(comparison$ReviewFlag, expected_flag) || any(!is.finite(as.matrix(comparison[,
        c("FullMean", "SubmatrixMean", "Difference", "JointMCSE")]))) || any(comparison$JointMCSE <= 0)) {
      stop("Original 08 comparison rule or numerical values are invalid.")
    }
    plot_data <- comparison
    plot_data$Outcome <- outcome; plot_data$Model <- "M3_P"; plot_data$Attempt <- attempt
    plot_data$ParentKey <- parent_key; plot_data$CheckKey <- context$check_key
    plot_data$QuantityType <- ifelse(startsWith(plot_data$Quantity, "Expected["), "observed_species_expected_value", "common_parameter")
    plot_data$CheckSeed <- context$CHECK_SEED
    utils::write.csv(plot_data, file.path(job_dir, "matrix_comparison_plot_data.csv"), row.names = FALSE)
    status$review_differences <- sum(comparison$ReviewFlag == "review_difference")
    status$status <- if (status$review_differences) "COMPLETE_WITH_REVIEW_DIFFERENCES" else "COMPLETE_WITHIN_2_MCSE"
    status$retry_eligible <- FALSE
    status$comparison_file <- file.path(job_dir, paste0(outcome, "_M3_P_comparison.csv"))
    status$plot_data_file <- file.path(job_dir, "matrix_comparison_plot_data.csv")
    output_files <- list.files(job_dir, recursive = TRUE, full.names = TRUE)
    output_files <- output_files[!dir.exists(output_files) & !basename(output_files) %in% c("status.json", "output_manifest.csv")]
    utils::write.csv(data.frame(File = substring(output_files, nchar(job_dir) + 2L), Bytes = file.info(output_files)$size,
      SHA256 = vapply(output_files, function(path) digest::digest(file = path, algo = "sha256"), character(1))),
      file.path(job_dir, "output_manifest.csv"), row.names = FALSE)
    write_status()
    cat("MATRIX_JOB_COMPLETE", outcome, attempt, status$status, "review_differences", status$review_differences, "\n")
    invisible(list(exit_code = 0L, status = status))
  }, error = function(error) {
    failed <- status; failed$status <- "ERROR"; failed$error <- conditionMessage(error)
    status <<- failed
    write_status()
    stop(error)
  })
}

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || !grepl("^[123]$", arguments[[2L]])) stop("Usage: matrix_job.R <binary|joint> <1|2|3>")
result <- run_matrix_job(arguments[[1L]], as.integer(arguments[[2L]]))
if (result$exit_code != 0L) quit(save = "no", status = result$exit_code, runLast = FALSE)
