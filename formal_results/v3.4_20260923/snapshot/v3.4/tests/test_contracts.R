check <- function(condition, message) {
  if (!isTRUE(condition)) stop("FAIL: ", message, call. = FALSE)
  cat("PASS: ", message, "\n", sep = "")
}

# Classification boundaries are part of the frozen input contract.
boundary <- data.frame(
  Type = c("count", "count", "exact", "interval", "interval", "interval"),
  Events = c(4, 5, NA, NA, NA, NA), Total = c(10, 10, NA, NA, NA, NA),
  Exact = c(NA, NA, .5, NA, NA, NA),
  Lower = c(NA, NA, NA, .4, .5, .2), Upper = c(NA, NA, NA, .5, 1, .55),
  stringsAsFactors = FALSE
)
classified <- classify_high_low(boundary)
check(identical(as.integer(classified$High), c(0L, 1L, 1L, 0L, 1L, NA_integer_)),
      "40-50 is LOW, exact/lower 50 is HIGH, strict crossing is excluded")

# The predictor set has five sites. Site151 is retained only as metadata.
panel <- data.frame(
  Species = c("s1", "s2", "s3", "s4", "s5"),
  Site3 = c("C", "R", "C", "MISSING", "Q"),
  Site20 = c("K", "R", "K", "K", "K"),
  Site117 = c("K", "K", "S", "K", "K"),
  Site151 = c("C", "C", "C", "R", "C"),
  Site196 = c("C", "A", "C", "C", "C"),
  Site315 = c("K", "T", "R", "A", "MISSING"),
  stringsAsFactors = FALSE
)
dict <- build_encoding_dictionary(panel, rare_min = 4L)
encoded <- encode_panel(panel, dict, predictor_sites = c("Site3", "Site20", "Site117", "Site196", "Site315"))
check(!"Site151" %in% encoded$predictor_sites, "Site151 is excluded from predictor sites")
check(encoded$data$M1_Site315[[1]] == "K_or_T" && encoded$data$M1_Site315[[3]] == "other",
      "Site315 M1 uses K_or_T and other")
check(all(encoded$data$M3_Site3[panel$Site3 == "R"] == "OTHER"),
      "M3 rare levels below four panel occurrences become OTHER")

# Training weights must preserve total effective record count while balancing species.
records <- data.frame(Species = c("a", "a", "a", "b", "c", "c"), stringsAsFactors = FALSE)
wr <- build_train_weights(records, weighting = "record_equal")
ws <- build_train_weights(records, weighting = "species_equal")
check(all(wr$weight == 1), "record_equal training weights are one")
check(max(abs(tapply(ws$weight, records$Species, sum) - 2)) < 1e-12,
      "species_equal gives each species the same total weight")
check(abs(sum(ws$weight) - nrow(records)) < 1e-12,
      "species_equal keeps total training weight equal to record count")

# AUC must be tie-safe and invariant to row order.
y <- c(1, 1, 0, 0); p <- c(.9, .6, .7, .2); w <- c(1, 3, 4, 2)
check(abs(weighted_auc(y, p, rep(1, 4)) - .75) < 1e-12,
      "unweighted AUC matches the pairwise definition")
check(abs(weighted_auc(y, p, w) - .5) < 1e-12,
      "weighted AUC matches the weighted pairwise definition")
check(abs(weighted_auc(y, p, w) - weighted_auc(rev(y), rev(p), rev(w))) < 1e-12,
      "weighted AUC is invariant to row order")
check(abs(weighted_auc(c(0, 1), c(.5, .5), c(1, 1)) - .5) < 1e-12,
      "tied predictions have AUC 0.5")

evidence <- data.frame(Route = "binary", Species = c("a", "a", "b", "c"),
  ObservedHigh = c(0, 1, 1, 0), PredictedPrHigh = c(.2, .8, .7, .4),
  LogPredictiveDensityRaw = log(c(.8, .8, .7, .6)), stringsAsFactors = FALSE)
er <- evaluate_evidence(evidence, "record_equal", "binary")
es <- evaluate_evidence(evidence, "species_equal", "binary")
check(er$RecordsUsed == 4 && es$RecordsUsed == 4 && er$WeightSum == es$WeightSum,
      "both evaluation weightings use the same base evidence rows")
check(abs(er$AUC - weighted_auc(evidence$ObservedHigh, evidence$PredictedPrHigh)) < 1e-12,
      "evaluation AUC uses the shared tie-safe metric")
cb <- calibration_bins(evidence, "species_equal", bootstrap = 20L, seed = 99L)
check(nrow(cb) > 0 && all(c("CalibrationLower", "CalibrationUpper", "IntervalStatus") %in% names(cb)),
      "calibration bins provide fixed-weight point estimates and cluster bootstrap intervals")

status <- applicability_status(
  has_response = TRUE, missing_predictor = TRUE, unseen_category = TRUE,
  unseen_raw_residue = TRUE, unseen_combination = TRUE, fixed_effect_estimable = FALSE,
  site151_outside_domain = TRUE
)
check(all(c("missing_predictor", "unseen_category", "unseen_combination",
            "unseen_raw_residue", "fixed_effect_not_estimable", "site151_outside_training_domain") %in% status$WarningCodes),
      "applicability status retains all independent warnings")

synthetic <- do.call(rbind, lapply(V3_MODELS, function(model) do.call(rbind, lapply(V3_TRAIN_WEIGHTINGS, function(tw) {
  data.frame(Design = "fivefold", Fold = 1L, Route = "binary", Model = model,
    TrainWeighting = tw, RecordID = paste0(model, tw, 1:4), Species = c("a", "a", "b", "c"),
    ObservedHigh = c(0, 1, 1, 0), PredictedPrHigh = c(.2, .8, .7, .4),
    LogPredictiveDensityRaw = log(c(.8, .8, .7, .6)), stringsAsFactors = FALSE)
}))))
post_dir <- tempfile("v3-post-"); dir.create(post_dir)
roc <- make_roc_outputs(synthetic, post_dir)
check(nrow(roc) > 0 && file.exists(file.path(post_dir, "roc_coordinates.csv")),
      "post-processing writes ROC coordinates from the shared evidence table")
cal <- calibration_bins(synthetic[synthetic$Model == "M1" & synthetic$TrainWeighting == "record_equal", ],
                        "species_equal", bootstrap = 20L)
check(nrow(cal) > 0, "post-processing computes calibration bins")
plot_roc_base(roc, file.path(post_dir, "roc.pdf"))
plot_calibration_base(cbind(data.frame(Design = "fivefold", Model = "M1", TrainWeighting = "record_equal"), cal),
                      file.path(post_dir, "calibration.pdf"))
check(file.exists(file.path(post_dir, "roc.pdf")) && file.exists(file.path(post_dir, "calibration.pdf")),
      "plotting entry points create PDF artifacts")



# Regression checks for the review findings.
# These are intentionally added before the production fixes.
counts_probe <- data.frame(
  Species = c("s1", "s1"), Type = c("count", "interval"),
  Events = c(1, NA), Total = c(2, NA), Exact = c(NA, NA),
  Lower = c(NA, .4), Upper = c(NA, .6),
  High = c(1L, NA_integer_), stringsAsFactors = FALSE
)
counts <- build_binary_counts(counts_probe, "s1")
check(counts$UnclassifiedCount[[1]] == 1L && counts$RecordCount[[1]] == 2L,
      "unclassified records remain in binary audit counts")

panel_no_missing <- data.frame(
  Species = c("a", "b"), Site3 = c("C", "C"), Site20 = c("K", "K"),
  Site117 = c("K", "K"), Site151 = c("C", "C"), Site196 = c("C", "C"),
  Site315 = c("K", "K"), stringsAsFactors = FALSE
)
dict_no_missing <- build_encoding_dictionary(panel_no_missing, rare_min = 1L)
enc_no_missing <- encode_panel(panel_no_missing, dict_no_missing)
bp_no_missing <- make_design_blueprint(enc_no_missing$data, panel_no_missing$Species, "M1")
check("MISSING" %in% bp_no_missing$levels$Site3,
      "blueprints reserve MISSING even when absent from training panel")

repeated_bin <- data.frame(
  Route = "binary", Species = c("a", "a", "b"),
  ObservedHigh = c(1, 0, 1), PredictedPrHigh = c(.21, .22, .81),
  LogPredictiveDensityRaw = log(c(.8, .7, .9)), stringsAsFactors = FALSE
)
cb_repeated <- calibration_bins(repeated_bin, "record_equal", bootstrap = 20L, seed = 1L)
check(nrow(cb_repeated) == 2L,
      "calibration output has one row per bin")

mean_draws <- matrix(c(.1, .2, .9), nrow = 3L, ncol = 1L)
mean_summary <- summarize_prediction_draws(mean_draws)
check(abs(mean_summary$Point[[1]] - mean(c(.1, .2, .9))) < 1e-12,
      "prediction Point uses posterior mean")

nonfinite_evidence <- data.frame(
  Route = "binary", Species = "a", ObservedHigh = 1,
  PredictedPrHigh = .8, LogPredictiveDensityRaw = -Inf,
  stringsAsFactors = FALSE
)
nonfinite_rejected <- inherits(tryCatch(evaluate_evidence(nonfinite_evidence, "record_equal", "binary"),
                                        error = function(e) e), "error")
check(nonfinite_rejected,
      "non-finite held-out scores are rejected instead of dropped")

null_draws <- null_projection_draws(c(qlogis(.1), qlogis(.8)), 3L)
check(all(abs(null_draws[, 1L] - null_draws[, 2L]) < 1e-12) &&
      all(abs(null_draws[, 2L] - null_draws[, 3L]) < 1e-12),
      "Null batch projection repeats each posterior draw across species")

external_missing <- panel_no_missing[1, , drop = FALSE]
external_missing$Site3 <- "MISSING"
external_enc <- encode_panel(external_missing, dict_no_missing)
external_x <- design_from_blueprint(external_enc$data, bp_no_missing)
check(any(external_x[1, grep("MISSING", colnames(external_x), fixed = TRUE)] == 1L),
      "external MISSING has a dedicated design direction")


make_syn_evidence <- function(model, tw, fold) {
  data.frame(Design = "fivefold", Fold = fold, Route = "binary", Model = model,
    TrainWeighting = tw, RecordID = paste("r", fold, 1:4, sep = "_"),
    Species = c("a", "a", "b", "b"), ObservedHigh = c(1, 0, 1, 0),
    PredictedPrHigh = if (model == "Null") c(.55, .45, .55, .45) else c(.8, .2, .7, .3),
    LogPredictiveDensityRaw = log(if (model == "Null") c(.55, .55, .55, .55) else c(.8, .8, .7, .7)),
    stringsAsFactors = FALSE)
}
syn_evidence <- do.call(rbind, lapply(c("Null", "M1"), function(m) do.call(rbind, lapply(V3_TRAIN_WEIGHTINGS, function(tw) do.call(rbind, lapply(1:2, function(fold) make_syn_evidence(m, tw, fold)))))))
syn_metrics <- list()
for (ew in V3_EVAL_WEIGHTINGS) for (m in c("Null", "M1")) for (tw in V3_TRAIN_WEIGHTINGS) for (fold in 1:2) {
  q <- syn_evidence[syn_evidence$Model == m & syn_evidence$TrainWeighting == tw & syn_evidence$Fold == fold, , drop = FALSE]
  r <- evaluate_evidence(q, ew, "binary")
  r$Design <- "fivefold"; r$Fold <- fold; r$Model <- m; r$TrainWeighting <- tw
  syn_metrics[[length(syn_metrics) + 1L]] <- r
}
syn_metrics <- do.call(rbind, syn_metrics)
syn_summary <- summarize_cv_metrics_v3(syn_evidence, syn_metrics)
check(nrow(syn_summary) == 8L && all(c("Model", "TrainWeighting", "EvalWeighting") %in% names(syn_summary)) &&
      !anyDuplicated(syn_summary[, c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")]),
      "CV summary preserves model, training weighting, and evaluation weighting identities")
syn_cmp <- compare_evidence_models(syn_evidence, "species_equal", scope = "design")
check(nrow(syn_cmp) == 2L && all(is.na(syn_cmp$Fold)) && all(is.finite(syn_cmp$Difference)),
      "model comparison aggregates the complete CV design at the species cluster level")

joint_probe <- data.frame(
  Route = "joint_bb", Type=c("count","interval","exact"), Species = c("a", "a", "b"),
  ObservedPoint = c(.2, NA, .7), PredictedPoint = c(.3, .5, .6),
  PredictedPI_lower = c(.1, .2, .5), PredictedPI_upper = c(.4, .8, .8),
  PIWidth = c(.3, .6, .3), IntervalCovered = c(TRUE, NA, TRUE),
  LogPredictiveDensityRaw = log(c(.7, .8, .6)), stringsAsFactors = FALSE
)
joint_eval <- evaluate_evidence(joint_probe, "species_equal", "joint_bb")
check(joint_eval$PIRecords == 2L && is.finite(joint_eval$PICoverage) && is.finite(joint_eval$MeanPIWidth),
      "joint evaluation reports predictive interval coverage and width")
