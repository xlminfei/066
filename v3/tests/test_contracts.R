#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, warn = 1)

`%||%` <- function(x, y) if (is.null(x)) y else x
root <- Sys.getenv("V3_ROOT", unset = "/project/v3")
source(file.path(root, "R", "config.R"), local = TRUE)
source(file.path(root, "R", "data_encoding.R"), local = TRUE)
source(file.path(root, "R", "weights.R"), local = TRUE)
source(file.path(root, "R", "metrics.R"), local = TRUE)
source(file.path(root, "R", "applicability.R"), local = TRUE)
source(file.path(root, "R", "comparison.R"), local = TRUE)
source(file.path(root, "R", "plotting.R"), local = TRUE)

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

cat("ALL CONTRACT TESTS PASSED\n")
