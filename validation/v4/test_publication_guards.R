#!/usr/bin/env Rscript
# Deterministic publication/resume guards only. No compilation or sampling.
# Persistent artifacts are limited to the explicitly supplied guard output directory.
args <- commandArgs(TRUE)
repo <- normalizePath(if (length(args)) args[1L] else ".", mustWork = TRUE)
output <- if (length(args) >= 2L) args[2L] else file.path(repo, "validation", "v4", "guard_checks")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, mustWork = TRUE)
root <- file.path(repo, "v4")
source(file.path(root, "R", "load.R"))
load_v4(root)

checks <- list()
record_check <- function(name, expression, error_pattern = NULL) {
  error <- tryCatch({ suppressWarnings(force(expression)); NULL }, error = function(e) conditionMessage(e))
  passed <- if (is.null(error_pattern)) is.null(error) else
    !is.null(error) && grepl(error_pattern, error, perl = TRUE)
  detail <- if (is.null(error)) "accepted" else error
  checks[[length(checks) + 1L]] <<- data.frame(Check = name, Passed = passed, Detail = detail)
  cat(if (passed) "PASS" else "FAIL", name, "|", detail, "\n")
  invisible(passed)
}

run_checks <- function() {
  input_files <- file.path(root, "data", names(INPUT_SHA256))
  hashes_before <- vapply(input_files, sha256_file, character(1))
  work <- tempfile("v4_publication_guards_")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  prepared <- file.path(work, "prepared")
  state <- prepare_stage(root, prepared)
  record_check("fresh_prepared_load", stopifnot(identical(load_prepared(root, prepared), state)))

  # Each mutation leaves the stored input and analysis identities unchanged.
  changed <- state
  index <- which(changed$observations$Type == "exact")[1L]
  changed$observations$Exact[index] <- .123456
  saveRDS(changed, file.path(prepared, "prepared.rds"))
  record_check("tampered_observation_rejected", load_prepared(root, prepared),
               "Prepared state differs from frozen inputs: observations")
  changed <- state
  changed$encoded$M1_Site3[1L] <- if (changed$encoded$M1_Site3[1L] == "other") "C_validated" else "other"
  saveRDS(changed, file.path(prepared, "prepared.rds"))
  record_check("tampered_encoding_rejected", load_prepared(root, prepared),
               "Prepared state differs from frozen inputs: encoded")
  changed <- state
  folds <- changed$fold_tables$fivefold$joint_bb
  index <- c(which(folds$Fold == 1L)[1L], which(folds$Fold == 2L)[1L])
  folds$Fold[index] <- rev(folds$Fold[index])
  changed$fold_tables$fivefold$joint_bb <- folds
  record_check("mutated_fold_map_remains_structurally_valid", check_fold_tables(changed))
  saveRDS(changed, file.path(prepared, "prepared.rds"))
  record_check("nonfrozen_valid_fold_map_rejected", load_prepared(root, prepared),
               "Prepared state differs from frozen inputs: fold_tables")
  saveRDS(state, file.path(prepared, "prepared.rds"))
  record_check("restored_prepared_load", stopifnot(identical(load_prepared(root, prepared), state)))

  prediction <- data.frame(Species = c("fixture_a", "fixture_b"), Route = ROUTES,
    Model = "M1", TrainWeighting = TRAIN_WEIGHTING, Point = c(.2, .4),
    PosteriorMedian = c(.2, .4), CrI_lower = c(.1, .3), CrI_upper = c(.3, .5),
    PI_lower = c(NA_real_, .05), PI_upper = c(NA_real_, .95))
  record_check("valid_prediction_schema", validate_prediction_table(prediction))
  numeric_columns <- c("Point", "PosteriorMedian", "CrI_lower", "CrI_upper", "PI_lower", "PI_upper")
  for (column in numeric_columns) {
    changed <- prediction; changed[[column]] <- NULL
    record_check(paste0("missing_prediction_", column, "_rejected"), validate_prediction_table(changed),
                 "Invalid prediction keys or missing columns")
  }
  record_check("prediction_keys_only_rejected", validate_prediction_table(prediction[1:4]),
               "Invalid prediction keys or missing columns")
  changed <- prediction; changed$Model[1L] <- "M4"
  record_check("unknown_prediction_model_rejected", validate_prediction_table(changed), "Invalid prediction grid")

  for (stage in c("fit", "evaluate", "plot")) {
    directory <- file.path(work, paste0("receipt_", stage))
    dir.create(directory)
    required <- stage_files(stage)
    for (file in required) {
      path <- file.path(directory, file)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      writeLines(paste("Guard fixture, not a fitted result:", file), path)
    }
    record_check(paste0(stage, "_canonical_receipt"), {
      stage_receipt(stage, state, directory)
      check_stage_receipt(stage, state, directory)
    })
    record_check(paste0(stage, "_empty_file_set_rejected"), stage_receipt(stage, state, directory, character()),
                 "Stage file set is incomplete")
    record_check(paste0(stage, "_incomplete_file_set_rejected"), stage_receipt(stage, state, directory, required[-1L]),
                 "Stage file set is incomplete")
    record_check(paste0(stage, "_duplicate_file_set_rejected"), stage_receipt(stage, state, directory, c(required, required[1L])),
                 "Stage file set is incomplete")
    receipt_path <- file.path(directory, paste0(stage, "_receipt.rds"))
    valid_receipt <- readRDS(receipt_path)
    changed <- valid_receipt; changed$files <- setNames(character(), character())
    saveRDS(changed, receipt_path)
    record_check(paste0(stage, "_empty_stored_receipt_rejected"), check_stage_receipt(stage, state, directory),
                 "Invalid/incomplete stage receipt")
    changed <- valid_receipt; changed$files <- changed$files[-1L]
    saveRDS(changed, receipt_path)
    record_check(paste0(stage, "_incomplete_stored_receipt_rejected"), check_stage_receipt(stage, state, directory),
                 "Invalid/incomplete stage receipt")
    saveRDS(valid_receipt, receipt_path)
    writeLines("Changed after receipt", file.path(directory, required[1L]))
    record_check(paste0(stage, "_changed_output_rejected"), check_stage_receipt(stage, state, directory),
                 "Stage outputs changed")
    unlink(file.path(directory, required[1L]))
    record_check(paste0(stage, "_missing_output_rejected"), check_stage_receipt(stage, state, directory), ".+")
  }

  expected_grid <- expand.grid(Design = names(DESIGNS), Route = ROUTES, Model = MODELS,
    TrainWeighting = TRAIN_WEIGHTING, EvalWeighting = EVAL_WEIGHTING, stringsAsFactors = FALSE)
  keys <- names(expected_grid)
  record_check("complete_metric_identity_grid", check_grid(expected_grid, expected_grid, keys))
  changed <- expected_grid; changed[1L, ] <- changed[2L, ]
  record_check("duplicate_metric_identity_rejected", check_grid(changed, expected_grid, keys), "Output grid mismatch")
  changed <- expected_grid; changed$Model[1L] <- "M4"
  record_check("wrong_metric_identity_rejected", check_grid(changed, expected_grid, keys), "Output grid mismatch")
  record_check("count_only_metric_table_rejected", check_grid(data.frame(Dummy = seq_len(16L)), expected_grid, keys),
               "Metric table lacks required")

  # Recreate the former false-COMPLETE example using immutable saved RS rows.
  # This is a negative validator fixture, not a new analysis or a fit result.
  bad_output <- file.path(work, "false_complete")
  dir.create(bad_output)
  baseline <- file.path(repo, "formal_results", "v3.4_20260923", "snapshot", "v3.4", "results")
  for (name in c("cv_record_predictions.csv", "full_panel_predictions.csv")) {
    table <- read.csv(file.path(baseline, name), stringsAsFactors = FALSE)
    table <- table[table$TrainWeighting == TRAIN_WEIGHTING, , drop = FALSE]
    write_csv_atomic(table, file.path(bad_output, name))
  }
  plan <- task_plan(state); diagnostics <- plan; diagnostics$Status <- "PASS"
  write_csv_atomic(diagnostics, file.path(bad_output, "fit_diagnostics.csv"))
  write_csv_atomic(data.frame(Status = "OK"), file.path(bad_output, "training_ppc_summary.csv"))
  sizes <- c(cv_metrics_summary = 16L, cv_fold_metrics = 120L, hypothesis_tests = 30L)
  for (name in names(sizes)) write_csv_atomic(data.frame(Dummy = seq_len(sizes[[name]])),
                                            file.path(bad_output, paste0(name, ".csv")))
  old_files <- list(fit = c("fit_diagnostics.csv", "cv_record_predictions.csv", "full_panel_predictions.csv", "training_ppc_summary.csv"),
                   evaluate = paste0(names(sizes), ".csv"), plot = character())
  for (stage in names(old_files)) {
    files <- old_files[[stage]]
    hashes <- setNames(vapply(files, function(n) sha256_file(file.path(bad_output, n)), character(1)), files)
    saveRDS(list(stage = stage, analysis_id = state$analysis_id, files = hashes),
            file.path(bad_output, paste0(stage, "_receipt.rds")))
  }
  record_check("former_false_complete_fixture_rejected", check_complete_outputs(state, bad_output),
               "Metric table lacks required")

  # Reach the fit-inventory guard without creating any purported fit file.
  diagnostics$FitKey <- paste0("negative_fixture_", seq_len(nrow(plan)))
  for (name in c("MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI")) diagnostics[[name]] <- 1
  write_csv_atomic(diagnostics, file.path(bad_output, "fit_diagnostics.csv"))
  manifest <- data.frame(FitID = plan$FitID, Path = file.path("fits", paste0(plan$FitID, ".rds")),
    Bytes = 1, SHA256 = strrep("0", 64L), FitKey = diagnostics$FitKey)
  write_csv_atomic(manifest, file.path(bad_output, "fit_manifest.csv"))
  record_check("missing_128_fit_files_rejected", check_complete_outputs(state, bad_output), "Missing or changed fit file")
  record_check("no_fit_file_created", stopifnot(!dir.exists(file.path(bad_output, "fits"))))
  record_check("frozen_input_files_unchanged", stopifnot(identical(hashes_before, vapply(input_files, sha256_file, character(1)))))
  state$analysis_id
}

identity <- run_checks()
results <- do.call(rbind, checks)
write_csv_atomic(results, file.path(output, "checks.csv"))
write_json_atomic(list(status = if (all(results$Passed)) "PASS" else "FAIL", analysis_id = identity,
  checks = nrow(results), passed = sum(results$Passed), failed = sum(!results$Passed),
  scope = "deterministic resume, schema, receipt and completion rejection checks; no compilation or MCMC",
  positive_full_completion_tested = FALSE, R = as.character(getRversion())), file.path(output, "status.json"))
if (!all(results$Passed)) stop("PUBLICATION_GUARDS_FAILED: ", sum(!results$Passed), " failed checks")
cat("PUBLICATION_GUARDS_PASS:", nrow(results), "checks; no compilation or MCMC\n")
