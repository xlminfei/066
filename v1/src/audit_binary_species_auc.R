# Read only the completed binary/species CV fits; do not fit or modify formal CV outputs.
options(warn = 1)
source("/project/work/ratio_analysis_20260914/scripts/common.R", local = .GlobalEnv)
initialize_manual()
out <- file.path(analysis_root, "review", "binary_species_auc_independent")
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) stop("Preserve the existing independent audit directory.")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
state <- list(status = "RUNNING", scope = "Completed binary/species subset only; the full formal goal remains incomplete")
atomic_json(state, file.path(out, "status.json"))
tryCatch({
  run_block("05_诊断与模型比较.md", "05_LOAD", overrides = list(OUTCOME = "binary", VARIANT = "primary"))
  dg <- utils::read.csv(file.path(RUN_DIR, "results", "diagnostics_binary_primary.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(dg) == 10L, all(dg$Status == "PASS"), setequal(dg$Model, names(bundles)))
  options(mc.cores = 1L)
  run_block("06_留出验证.md", "06_FOLDS", overrides = list(CV_TYPE = "species"))
  run_block("06A_HighLow_ROC_AUC.md", "06A_SETUP")
  run_block("06A_HighLow_ROC_AUC.md", "06A_LOAD")
  run_block("06A_HighLow_ROC_AUC.md", "06A_METRICS")
  pair_rows <- brier_rows <- list()
  for (model in auc_models) {
    z <- roc_data[roc_data$Model == model, , drop = FALSE]
    stopifnot(nrow(z) == 152L, length(unique(z$Species)) == 50L)
    brier_rows[[model]] <- data.frame(Model = model, CVType = "species", Records = nrow(z),
      Species = length(unique(z$Species)), BrierScore = mean((z$OOFPrHigh - z$High)^2),
      Weighting = "equal_weight_per_experiment", ScoreDefinition = "posterior_median_high_probability_Trials_1")
    for (k in auc_folds) {
      p <- z[z$Fold == k, , drop = FALSE]
      h <- p$OOFPrHigh[p$High == 1L]; l <- p$OOFPrHigh[p$High == 0L]
      stopifnot(length(h) > 0L, length(l) > 0L)
      pair_auc <- mean(outer(h, l, function(a, b) as.numeric(a > b) + .5 * as.numeric(a == b)))
      row <- auc_by_fold[auc_by_fold$Model == model & auc_by_fold$Fold == k, , drop = FALSE]
      stopifnot(nrow(row) == 1L, abs(pair_auc - row$AUC) < 1e-12)
      pair_rows[[paste(model, k)]] <- data.frame(Model = model, Fold = k, High = length(h), Low = length(l),
        PairAUC = pair_auc, pROC_AUC = row$AUC, Difference = pair_auc - row$AUC)
    }
  }
  pair_checks <- do.call(rbind, pair_rows); brier <- do.call(rbind, brier_rows)
  stopifnot(nrow(pair_checks) == 50L, nrow(auc_summary) == 10L, all(auc_summary$Status == "DEFINED"))
  for (model in auc_models) stopifnot(abs(auc_summary$CV_AUC[auc_summary$Model == model] -
    mean(pair_checks$PairAUC[pair_checks$Model == model])) < 1e-12)
  outputs <- list(auc_summary = auc_summary, auc_by_fold = auc_by_fold, pairwise_auc_checks = pair_checks,
    brier_scores = brier, roc_oof_experiments = roc_data, source_receipts = auc_receipts)
  for (name in names(outputs)) utils::write.csv(outputs[[name]], file.path(out, paste0(name, ".csv")), row.names = FALSE)
  for (model in auc_models) {
    chosen <- auc_index[auc_index$Model == model, , drop = FALSE]
    stopifnot(digest::digest(file = file.path(CV_DIR, chosen$File), algo = "sha256") ==
      auc_receipts$CVFileSHA256[auc_receipts$Model == model])
  }
  state$status <- "PASS_COMPLETED_BINARY_SPECIES_SUBSET"
  state$models <- 10L; state$folds <- 50L; state$records_per_model <- 152L; state$species <- 50L
  state$max_pairwise_auc_difference <- max(abs(pair_checks$Difference))
  state$script_sha256 <- digest::digest(file = file.path(analysis_root, "scripts", "audit_binary_species_auc.R"), algo = "sha256")
  state$fold_key <- fold_key; state$input_hashes <- prepared$input_hashes
  state$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  atomic_json(state, file.path(out, "status.json"))
  cat("INDEPENDENT_BINARY_SPECIES_AUC_COMPLETE\n")
  print(merge(auc_summary[, c("Model", "CV_AUC")], brier[, c("Model", "BrierScore")], sort = FALSE))
}, error = function(e) {
  state$status <- "ERROR"; state$message <- conditionMessage(e)
  atomic_json(state, file.path(out, "status.json"))
  stop(e)
})
