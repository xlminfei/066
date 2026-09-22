audit_plan_v3_impl <- function(state, root, run_dir, review_dir) {
  cfg <- read_config_v3(root)
  fresh <- prepare_state(file.path(root, "input"), cfg$expected_panel_species, cfg$expected_records)
  if (!identical(state, fresh)) stop("Formal audit state differs from freshly reconstructed current inputs")
  state <- fresh
  folds <- make_fold_tables_v3(state); expected <- task_plan_v3(state, folds)
  plan <- read.csv(file.path(run_dir, "run_plan.csv"), stringsAsFactors = FALSE)
  if (!identical(names(plan), names(expected)) || !isTRUE(all.equal(plan, expected, check.attributes = FALSE))) {
    stop("Run plan differs from canonical full grid/current inputs/config")
  }
  receipts <- list(); prediction_receipts <- list(); issues <- character()
  read_output <- function(name) {
    path <- file.path(root, "results", name)
    if (!file.exists(path)) { issues <<- c(issues, paste("Missing output:", name)); return(NULL) }
    read.csv(path, stringsAsFactors = FALSE)
  }
  ev <- read_output("cv_record_predictions.csv")
  pred <- read_output("full_panel_predictions.csv")
  if (!is.null(ev)) tryCatch({
    validate_cv_evidence_v3(state, ev, folds)
    if (!"RunPurpose" %in% names(ev) || anyNA(ev$RunPurpose) || any(ev$RunPurpose != "formal")) {
      stop("Test evidence cannot be audited as formal results")
    }
  }, error = function(e) issues <<- c(issues, conditionMessage(e)))
  if (!is.null(pred)) tryCatch({
    validate_prediction_table_v3(pred)
    grid <- expand.grid(Species = state$sites$Species, Route = V3_ROUTES, Model = V3_MODELS,
      TrainWeighting = V3_TRAIN_WEIGHTINGS, stringsAsFactors = FALSE)
    audit_assert_key_grid_v3(pred, grid, names(grid), "full_panel_grid")
  }, error = function(e) issues <<- c(issues, conditionMessage(e)))

  # Every saved fit is reopened; every held-out row and every full-panel species
  # is recomputed from its posterior, including an independent R likelihood.
  for (i in seq_len(nrow(plan))) {
    row <- plan[i, , drop = FALSE]
    path <- fit_path_v3(root, row$Route, row$Model, row$TrainWeighting, row$Design,
      if (is.na(row$Fold)) NULL else row$Fold)
    result <- tryCatch({
      bundle <- readRDS(path)
      active <- if (row$Route == "binary") state$binary_species else state$joint_species
      held <- if (row$Design == "full") character() else
        folds[[row$Design]][[row$Route]]$Species[folds[[row$Design]][[row$Route]]$Fold == row$Fold]
      train <- if (row$Design == "full") active else setdiff(active, held)
      spec <- fit_spec_v3(state, row$Route, row$Model, train, row$TrainWeighting,
        file.path(root, "stan", "joint_bb.stan"), seed = row$Seed)
      validate_fitted_bundle_v3(bundle, spec, require_pass = TRUE)
      context <- row[, c("Design", "Fold", "Route", "Model", "TrainWeighting"), drop = FALSE]
      context$RunPurpose <- "formal"
      recomputed <- tryCatch({
        if (row$Design == "full") {
          if (is.null(pred)) stop("Full-panel predictions are missing")
          saved <- pred[pred$Route == row$Route & pred$Model == row$Model &
            pred$TrainWeighting == row$TrainWeighting, , drop = FALSE]
          audit_full_bundle_predictions_v3(bundle, state, saved, context)
        } else {
          if (is.null(ev)) stop("OOF predictions are missing")
          held_rows <- which(state$observations$Species %in% held &
            if (row$Route == "binary") !is.na(state$observations$High) else state$observations$Informative)
          saved <- ev[ev$Design == row$Design & ev$Fold == row$Fold & ev$Route == row$Route &
            ev$Model == row$Model & ev$TrainWeighting == row$TrainWeighting, , drop = FALSE]
          audit_cv_bundle_predictions_v3(bundle, state, held_rows, saved, context)
        }
      }, error = function(e) audit_receipt_v3(context,
          if (row$Design == "full") "posterior_to_full_panel" else "posterior_to_OOF", "FAILED_STRATUM",
          0L, 0L, NA_integer_, NA_real_, 1e-10, status = "FAIL", reason = conditionMessage(e)))
      prediction_receipts[[length(prediction_receipts) + 1L]] <- recomputed
      passed <- all(recomputed$Status == "PASS")
      list(ok = passed, identity_ok = TRUE, prediction_ok = passed, key = bundle$key,
        reason = if (passed) "identity_current_inputs_diagnostics_and_all_predictions_recomputed" else
          paste(recomputed$Reason[recomputed$Status != "PASS"], collapse = "; "))
    }, error = function(e) list(ok = FALSE, identity_ok = FALSE, prediction_ok = FALSE,
      key = NA_character_, reason = conditionMessage(e)))
    receipts[[i]] <- cbind(row, data.frame(Pass = result$ok, IdentityPass = result$identity_ok,
      PredictionPass = result$prediction_ok, FitKey = result$key, Reason = result$reason))
    if (!result$ok) issues <- c(issues, paste(row$FitID, result$reason))
    # Persist each completed stratum so an interrupted audit cannot imply that
    # later fits or observations were checked.
    write_csv_atomic(do.call(rbind, receipts), file.path(review_dir, "fit_audit.csv"))
    if (length(prediction_receipts)) write_csv_atomic(do.call(rbind, prediction_receipts),
      file.path(review_dir, "audit_prediction_recompute.csv"))
    cat("AUDIT_FIT", i, "/", nrow(plan), row$FitID, if (result$ok) "PASS" else "FAIL", "\n")
    flush.console()
  }
  rec <- do.call(rbind, receipts)
  if (!length(issues)) {
    tryCatch({
      verify_derived_outputs_v3(root, state)
      for (stage in c("cv", "predict", "ppc")) verify_stage_receipt_v3(root, state, stage)
      fm <- read.csv(file.path(root, "results", "cv_fold_metrics.csv"), stringsAsFactors = FALSE)
      fold_grid <- do.call(rbind, lapply(names(folds), function(design) {
        z <- expand.grid(Route = V3_ROUTES, Model = V3_MODELS, TrainWeighting = V3_TRAIN_WEIGHTINGS,
          EvalWeighting = V3_EVAL_WEIGHTINGS, Fold = seq_len(V3_DESIGN_K[[design]]), stringsAsFactors = FALSE)
        z$Design <- design; z
      }))
      fold_keys <- c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting", "Fold")
      audit_assert_key_grid_v3(fm, fold_grid, fold_keys, "cv_fold_metric_grid")
      for (i in seq_len(nrow(fm))) {
        row <- fm[i, , drop = FALSE]
        evidence <- ev[ev$Design == row$Design & ev$Fold == row$Fold & ev$Route == row$Route &
          ev$Model == row$Model & ev$TrainWeighting == row$TrainWeighting, , drop = FALSE]
        score <- evaluate_evidence(evidence, row$EvalWeighting, row$Route)
        # Required evaluation fields are dynamic: new support/Bias fields cannot
        # be silently omitted by comparing only an old hard-coded intersection.
        for (name in setdiff(fold_keys, names(score))) score[[name]] <- row[[name]]
        audit_compare_table_v3(row, score, fold_keys, "cv_fold_scores")
      }
      summary <- summarize_cv_metrics_v3(ev, fm)
      stored <- read.csv(file.path(root, "results", "cv_metrics_summary.csv"), stringsAsFactors = FALSE)
      audit_compare_table_v3(stored, summary, setdiff(fold_keys, "Fold"), "cv_summary")
      model_table <- read.csv(file.path(root, "results", "model_vs_null.csv"), stringsAsFactors = FALSE)
      training_table <- read.csv(file.path(root, "results", "training_method_comparisons.csv"), stringsAsFactors = FALSE)
      comparison_receipts <- verify_comparison_outputs_v3(ev, model_table, training_table)
      write_csv_atomic(comparison_receipts, file.path(review_dir, "audit_comparison_recompute.csv"))
      quantitative_receipts <- verify_quantitative_outputs_v32(ev,
        read.csv(file.path(root, "results", "quantitative_bias_summary.csv"), stringsAsFactors = FALSE),
        read.csv(file.path(root, "results", "quantitative_plot_source.csv"), stringsAsFactors = FALSE))
      write_csv_atomic(quantitative_receipts, file.path(review_dir, "audit_quantitative_recompute.csv"))
      required <- c("calibration_bins.csv", "roc_coordinates.csv", "training_ppc_summary.csv")
      for (file in required) if (!file.exists(file.path(root, "results", file))) stop("Missing output: ", file)
      if (!file.exists(file.path(root, "reports", "REPORT_v3_3.md"))) stop("Missing full result report")
    }, error = function(e) issues <<- c(issues, conditionMessage(e)))
  }
  status <- if (length(issues)) "FAILED" else "PASS"
  checked <- if (length(prediction_receipts)) do.call(rbind, prediction_receipts) else data.frame()
  write_json_atomic(list(status = status, version = V3_VERSION, expected_tasks = nrow(expected),
    fits_checked = nrow(rec), fits_passed = sum(rec$Pass), posterior_refits = 0L,
    prediction_strata_checked = nrow(checked),
    prediction_rows_checked = if (nrow(checked)) sum(checked$RowsChecked) else 0L,
    prediction_audit_source = "current_inputs_and_saved_fitted_posterior; independent_R_raw_loglik",
    issues = issues), file.path(review_dir, "audit_v3.json"))
  if (length(issues)) stop("Formal audit failed: ", paste(head(issues, 5), collapse = "; "))
  invisible(TRUE)
}

audit_plan_v3 <- function(state, root, run_dir, review_dir) {
  path <- file.path(review_dir, "audit_v3.json")
  write_json_atomic(list(status = "RUNNING", version = V3_VERSION), path)
  empty_predictions <- audit_receipt_v3(list(), "", "", 0L, 0L, 0L, NA_real_, 1e-10)[FALSE, , drop = FALSE]
  write_csv_atomic(empty_predictions, file.path(review_dir, "audit_prediction_recompute.csv"))
  write_csv_atomic(data.frame(Check = character(), RowsChecked = integer(), ColumnsChecked = integer(),
    MaximumAbsoluteDifference = numeric(), Status = character()), file.path(review_dir, "audit_comparison_recompute.csv"))
  write_csv_atomic(data.frame(Check = character(), RowsChecked = integer(), ColumnsChecked = integer(),
    MaximumAbsoluteDifference = numeric(), Status = character()), file.path(review_dir, "audit_quantitative_recompute.csv"))
  write_csv_atomic(data.frame(FitID = character(), Pass = logical(), Reason = character()), file.path(review_dir, "fit_audit.csv"))
  tryCatch(audit_plan_v3_impl(state, root, run_dir, review_dir), error = function(e) {
    previous <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) list())
    previous$status <- "FAILED"; previous$version <- V3_VERSION; previous$reason <- conditionMessage(e)
    write_json_atomic(previous, path)
    stop(e)
  })
}
