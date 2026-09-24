#!/usr/bin/env Rscript
# Reconciliation of saved OOF predictions, plus synthetic boundary checks.
# Usage: Rscript test_metrics.R REPOSITORY [NEW_PERSISTENT_OUTPUT_DIRECTORY]
# Sources are read only; this script never invokes a fit.
args <- commandArgs(TRUE)
if (length(args) > 2L) stop("Usage: Rscript test_metrics.R REPOSITORY [NEW_OUTPUT_DIRECTORY]")
repo <- normalizePath(if (length(args)) args[1L] else ".", mustWork = TRUE)
persistent_output <- if (length(args) == 2L) args[2L] else NULL
source(file.path(repo, "v4", "R", "load.R"))
load_v4(file.path(repo, "v4"))

expect_error <- function(expression) {
  failed <- tryCatch({ force(expression); FALSE }, error = function(e) TRUE)
  if (!failed) stop("Expected the invalid input to be rejected")
}
near <- function(a, b, tolerance = 1e-12) {
  a <- as.vector(a); b <- as.vector(b)
  stopifnot(length(a) == length(b), identical(is.na(a), is.na(b)))
  keep <- !is.na(a)
  stopifnot(all(is.finite(a[keep])), all(is.finite(b[keep])),
            all(abs(a[keep] - b[keep]) <= tolerance))
}
align <- function(a, b, keys) {
  stopifnot(!anyDuplicated(a[keys]), !anyDuplicated(b[keys]),
            setequal(metric_key(a, keys), metric_key(b, keys)))
  b[match(metric_key(a, keys), metric_key(b, keys)), , drop = FALSE]
}

run_metric_tests <- function(output_dir = NULL) {
  stopifnot(B_ELPD == 2000L, B_OTHER_METRICS == 50000L, SEED == 20260920L, SEED_OTHER == 20260923L)
  persistent <- !is.null(output_dir)
  if (persistent && (length(output_dir) != 1L || is.na(output_dir) || !nzchar(trimws(output_dir)))) stop("Invalid output directory")
  output <- if (persistent) normalizePath(output_dir, mustWork = FALSE) else tempfile("v4_metric_test_")
  if (file.exists(output) || dir.exists(output)) stop("Test output must be a new, absent directory: ", output)
  if (!dir.create(output, recursive = TRUE)) stop("Cannot create test output directory: ", output)
  status <- list(status = "INCOMPLETE", started_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    B_ELPD = B_ELPD, B_OTHER_METRICS = B_OTHER_METRICS, SEED = SEED, SEED_OTHER = SEED_OTHER,
    fitted_models_run = 0L, output_preserved = persistent)
  if (persistent) {
    on.exit({
      status$finished_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
      write_json_atomic(status, file.path(output, "test_status.json"))
    }, add = TRUE)
  } else on.exit(unlink(output, recursive = TRUE), add = TRUE)
  # Unequal records per species: equal species means, not equal record means.
  joint <- data.frame(Route = "joint_bb", Species = c("a", "a", "b", "interval_only"),
    RecordID = paste0("j", 1:4), Type = c("count", "exact", "count", "interval"),
    ObservedPoint = c(0, 0, 0, NA), PredictedPoint = c(.1, .3, .9, .8),
    PredictedPI_lower = 0, PredictedPI_upper = 1, PIWidth = 1,
    IntervalCovered = c(TRUE, TRUE, TRUE, NA), LogPredictiveDensityRaw = c(-1, -3, -4, -8))
  metric <- evaluate_evidence(joint)
  near(metric$MeanLogScore, mean(c(-2, -4, -8)))
  near(metric$ELPD, metric$MeanLogScore * 4)
  near(metric$MAE, .55); near(metric$RMSE, sqrt(.43)); near(metric$Bias, .55)
  stopifnot(metric$LogScoreSpeciesUsed == 3L, metric$PointSpeciesUsed == 2L,
            metric$PISpeciesUsed == 2L, metric$PIRecords == 3L, metric$PICoverage == 1,
            abs(metric$RMSE - mean(c(sqrt(.05), .9))) > .01)
  changed <- joint; changed$ObservedPoint[4] <- .999
  near(evaluate_evidence(changed)$MAE, metric$MAE)
  near(evaluate_evidence(changed)$PICoverage, metric$PICoverage)
  changed <- joint; changed$PredictedPoint[1] <- Inf; expect_error(evaluate_evidence(changed))
  changed <- joint; changed$ObservedPoint[1] <- -1; expect_error(evaluate_evidence(changed))
  changed <- joint; changed$IntervalCovered[1] <- FALSE; expect_error(evaluate_evidence(changed))
  changed <- joint; changed$PIWidth[1] <- .2; expect_error(evaluate_evidence(changed))
  changed <- joint; changed$LogPredictiveDensityRaw[1] <- -Inf; expect_error(evaluate_evidence(changed))
  em <- error_species_stats(joint[1:3, ], "PredictedPoint")
  near(error_metrics_from_counts(em, c(1L, 1L))$RMSE[, 1L], sqrt(.43))

  # Full-set weights persist inside calibration bins even when one species has
  # records in two bins. Rebuilding the bin weights would wrongly give 1/2.
  binary <- data.frame(Route = "binary", Species = c(rep("a", 4L), "b"), RecordID = paste0("b", 1:5),
    ObservedHigh = c(1, 1, 0, 0, 0), PredictedPrHigh = c(.1, .1, .9, .9, .1),
    LogPredictiveDensityRaw = rep(-1, 5L))
  calibration <- calibration_bins(binary, bootstrap = B_ELPD, seed = 123L)
  near(calibration$ObservedRate[calibration$Bin == "[0,0.2)"], 1 / 3)
  near(evaluate_evidence(binary)$Brier, mean(c(mean((c(1, 1, 0, 0) - c(.1, .1, .9, .9))^2), .01)))
  near(weighted_auc(c(0, 1), c(.5, .5)), .5)
  stopifnot(is.na(weighted_auc(c(1, 1), c(.5, .5))))
  expect_error(roc_coordinates(c(1, 1), c(.5, .5)))
  expect_error(weighted_auc(c(0, 1), c(-.1, .5)))
  degenerate <- normal_bootstrap_test(.1, rep(.1, B_ELPD))
  stopifnot(is.na(degenerate$P_approx), is.na(degenerate$Z_approx),
            degenerate$TestStatus == "DEGENERATE_CLUSTER_BOOTSTRAP")

  # BH has exactly 3 planned members even if one or all P values are NA.
  grid <- expected_hypotheses(); grid$P_approx <- rep(c(.01, NA_real_, .04), 10L)
  grid$CI95_lower <- seq_len(30L); grid$CI95_upper <- seq_len(30L) + 1
  adjusted <- adjust_hypothesis_families(grid)
  near(adjusted$P_BH3, rep(c(.03, NA_real_, .06), 10L))
  stopifnot(identical(adjusted$P_approx, grid$P_approx), identical(adjusted$CI95_lower, grid$CI95_lower),
            length(unique(adjusted$FamilyID)) == 10L, all(adjusted$FamilySize == 3L))
  changed <- grid; changed$P_approx[] <- NA_real_
  stopifnot(all(is.na(adjust_hypothesis_families(changed)$P_BH3)))
  expect_error(adjust_hypothesis_families(grid[-1L, ]))
  expect_error(adjust_hypothesis_families(rbind(grid, grid[1L, ])))
  changed <- grid; changed[2L, ] <- changed[1L, ]; expect_error(adjust_hypothesis_families(changed))
  for (model in c("Null", "M4", "", NA_character_)) {
    changed <- grid; changed$Model[1L] <- model; expect_error(adjust_hypothesis_families(changed))
  }
  for (bad in c(NaN, Inf, -.01, 1.01)) {
    changed <- grid; changed$P_approx[1L] <- bad; expect_error(adjust_hypothesis_families(changed))
  }
  changed <- grid; changed$P_approx <- as.character(changed$P_approx); expect_error(adjust_hypothesis_families(changed))
  changed <- grid; changed$P_approx <- matrix(changed$P_approx, ncol = 1L); expect_error(adjust_hypothesis_families(changed))
  changed <- grid; changed$Design[1L] <- " "; expect_error(adjust_hypothesis_families(changed))
  changed <- grid; changed$TrainWeighting[1L] <- "species_equal"; expect_error(adjust_hypothesis_families(changed))
  cat("METRIC_BOUNDARIES_PASS: species weights, interval exclusions, RMSE, calibration, invalid inputs, NA/zero-SE, BH3\n")

  baseline <- file.path(repo, "formal_results", "v3.4_20260923", "snapshot", "v3.4", "results")
  supplement <- file.path(repo, "formal_results", "v3.4_20260923", "pvalue_supplement_20260923", "source", "additional_metrics")
  source_files <- file.path(baseline, c("cv_record_predictions.csv", "cv_metrics_summary.csv", "model_vs_null.csv", "calibration_bins.csv"))
  supplement_files <- file.path(supplement, c("supplementary_metric_tests.csv", "bootstrap_difference_draws.rds", "bootstrap_species_multiplicities.rds"))
  input_files <- file.path(repo, "v4", "data", names(INPUT_SHA256))
  code_files <- c(file.path(repo, "v4", c("settings.R", "run_all.R", "01_prepare.R", "02_fit.R", "03_evaluate.R", "04_plot.R", "stan/joint_bb.stan")),
    list.files(file.path(repo, "v4", "R"), pattern = "[.]R$", full.names = TRUE),
    file.path(repo, "validation", "v4", "test_metrics.R"))
  receipt_files <- c(source_files, supplement_files, input_files, code_files)
  receipt_kind <- c(rep("saved_formal_csv", length(source_files)), rep("saved_supplement", length(supplement_files)),
    rep("frozen_input", length(input_files)), rep("tested_code", length(code_files)))
  before <- vapply(receipt_files, sha256_file, character(1))
  evidence <- read.csv(source_files[1L], stringsAsFactors = FALSE)
  evidence <- evidence[evidence$TrainWeighting == TRAIN_WEIGHTING, , drop = FALSE]
  stopifnot(nrow(evidence) == 2440L, all(evidence$RunPurpose == "formal"))
  read_input <- function(name) read.csv(file.path(repo, "v4", "data", name), stringsAsFactors = FALSE, na.strings = c("", "NA"))
  folds <- setNames(lapply(names(DESIGNS), function(d) setNames(lapply(ROUTES, function(r)
    read_input(paste0("folds_", r, "_species_", DESIGNS[[d]], ".csv"))), ROUTES)), names(DESIGNS))
  state <- prepare_from_tables(read_input("observations.csv"), read_input("sites.csv"), folds)
  check_cv_evidence(state, evidence)
  factored <- evidence; factored$Species <- factor(factored$Species, levels = c(unique(factored$Species), "unused_level"))
  check_metric_evidence(factored)
  for (bad in c(NA_real_, .5, 0, 11, Inf)) {
    changed <- evidence; changed$Fold[1L] <- bad; expect_error(check_metric_evidence(changed))
  }
  changed <- evidence; changed$RecordID[1L] <- NA; expect_error(check_metric_evidence(changed))
  changed <- evidence; changed$Fold <- matrix(changed$Fold, ncol = 1L); expect_error(check_metric_evidence(changed))
  changed <- evidence; changed$Species[1L] <- " "; expect_error(check_metric_evidence(changed))
  changed <- evidence; changed$Model[changed$Model == "M3"] <- "M4"; expect_error(check_metric_evidence(changed))
  expect_error(check_metric_evidence(evidence[-1L, ]))
  expect_error(check_metric_evidence(rbind(evidence, evidence[1L, ])))
  changed <- evidence; changed$ObservedPoint[which(changed$Route == "joint_bb" & changed$Type == "interval")[1L]] <- .5
  expect_error(check_cv_evidence(state, changed))
  tables <- evaluate_stage(state, evidence, output)
  expect_error(hypothesis_tests(evidence, tables$cv_metrics_summary[-1L, ]))
  expect_error(hypothesis_tests(evidence, rbind(tables$cv_metrics_summary, tables$cv_metrics_summary[1L, ])))
  changed <- tables$cv_metrics_summary; changed$Model[1L] <- "M4"
  expect_error(hypothesis_tests(evidence, changed))
  expected_files <- c("cv_fold_metrics.csv", "cv_metrics_summary.csv", "hypothesis_tests.csv", "roc_coordinates.csv",
    "calibration_bins.csv", "quantitative_plot_source.csv", "quantitative_bias_summary.csv", "auc_fold_species_support.csv",
    "bootstrap_draws.rds", "bootstrap_multiplicities.rds")
  stopifnot(setequal(list.files(output), expected_files), nrow(tables$cv_fold_metrics) == 120L,
    nrow(tables$cv_metrics_summary) == 16L, nrow(tables$hypothesis_tests) == 30L,
    nrow(tables$auc_fold_species_support) == 15L, all(tables$quantitative_plot_source$Type %in% c("count", "exact")),
    all(tables$quantitative_bias_summary$PointRecords == 145L), all(tables$quantitative_bias_summary$PointSpeciesUsed == 48L))

  keys <- c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")
  previous <- read.csv(source_files[2L], stringsAsFactors = FALSE)
  previous <- previous[previous$TrainWeighting == TRAIN_WEIGHTING & previous$EvalWeighting == EVAL_WEIGHTING, ]
  previous <- align(tables$cv_metrics_summary, previous, keys)
  columns <- c("AUC", "PooledAUC", "FoldMeanAUC", "MeanLogScore", "Brier", "MAE", "RMSE", "Bias", "PICoverage", "MeanPIWidth",
               "RecordsUsed", "SpeciesUsed", "LogScoreSpeciesUsed", "PointSpeciesUsed", "PISpeciesUsed")
  for (name in columns) near(tables$cv_metrics_summary[[name]], previous[[name]])
  near(tables$cv_metrics_summary$ELPD, previous$ELPD, 1e-10)
  near(tables$cv_metrics_summary$ELPD, tables$cv_metrics_summary$MeanLogScore * tables$cv_metrics_summary$RecordsUsed)
  binary_summary <- tables$cv_metrics_summary[tables$cv_metrics_summary$Route == "binary", ]
  stopifnot(any(abs(binary_summary$AUC - binary_summary$PooledAUC) > 1e-4))
  for (i in seq_len(nrow(binary_summary))) {
    q <- binary_summary[i, ]; fm <- tables$cv_fold_metrics
    near(q$AUC, mean(fm$AUC[fm$Design == q$Design & fm$Route == "binary" & fm$Model == q$Model]))
  }
  previous_cal <- read.csv(source_files[4L], stringsAsFactors = FALSE)
  previous_cal <- previous_cal[previous_cal$TrainWeighting == TRAIN_WEIGHTING & previous_cal$EvalWeighting == EVAL_WEIGHTING, ]
  previous_cal <- align(tables$calibration_bins, previous_cal, c("Design", "Model", "TrainWeighting", "EvalWeighting", "Bin"))
  for (name in c("ObservedRate", "MeanPredicted", "CalibrationLower", "CalibrationUpper", "WeightSum")) {
    near(tables$calibration_bins[[name]], previous_cal[[name]])
  }
  stopifnot(identical(tables$calibration_bins$IntervalStatus, previous_cal$IntervalStatus))
  cat("SAVED_OOF_METRICS_PASS: 120 fold metrics, 16 summaries, full-weight calibration, point/PI species support\n")

  old_log <- read.csv(source_files[3L], stringsAsFactors = FALSE)
  old_log <- old_log[old_log$TrainWeighting == TRAIN_WEIGHTING & old_log$EvalWeighting == EVAL_WEIGHTING & old_log$Scope == "design", ]
  old_log$Metric <- "MeanLogScore"
  old_other <- read.csv(file.path(supplement, "supplementary_metric_tests.csv"), stringsAsFactors = FALSE)
  old_other <- old_other[old_other$TrainWeighting == TRAIN_WEIGHTING & old_other$EvalWeighting == EVAL_WEIGHTING & old_other$Model != "Null", ]
  numeric_tests <- c("Difference", "SE_approx", "Z_approx", "P_approx", "CI95_lower", "CI95_upper")
  common <- c(keys, "Metric", numeric_tests)
  previous_tests <- rbind(old_log[common], old_other[common])
  previous_tests <- align(tables$hypothesis_tests, previous_tests, c(keys, "Metric"))
  for (name in numeric_tests) near(tables$hypothesis_tests[[name]], previous_tests[[name]])
  max_p_difference <- max(abs(tables$hypothesis_tests$P_approx - previous_tests$P_approx), na.rm = TRUE)
  max_ci_difference <- max(abs(as.matrix(tables$hypothesis_tests[c("CI95_lower", "CI95_upper")]) -
                               as.matrix(previous_tests[c("CI95_lower", "CI95_upper")])), na.rm = TRUE)
  cat(sprintf("RAW_TEST_MAX_ABS_DIFFERENCE: P=%.3g CI=%.3g\n",
    max_p_difference, max_ci_difference))
  stopifnot(all(tables$hypothesis_tests$Model != "Null"), all(tables$hypothesis_tests$FamilySize == 3L),
            length(unique(tables$hypothesis_tests$FamilyID)) == 10L)
  for (i in split(seq_len(30L), tables$hypothesis_tests$FamilyID)) {
    near(tables$hypothesis_tests$P_BH3[i], p.adjust(previous_tests$P_approx[i], "BH", n = 3L))
  }
  cat("SAVED_OOF_INFERENCE_PASS: all 30 original raw P/CI/SE/differences retained; ten independent BH3 families\n")

  stored_draws <- readRDS(file.path(output, "bootstrap_draws.rds"))
  stored_counts <- readRDS(file.path(output, "bootstrap_multiplicities.rds"))
  old_draws <- readRDS(file.path(supplement, "bootstrap_difference_draws.rds"))
  old_counts <- readRDS(file.path(supplement, "bootstrap_species_multiplicities.rds"))
  stopifnot(length(stored_draws) == 30L)
  for (d in names(DESIGNS)) {
    for (family in c("AUC", "ERROR")) {
      key <- paste(family, d, sep = "_")
      stopifnot(identical(stored_counts[[key]]$counts, old_counts[[key]]$counts))
    }
    for (m in c("M1", "M2", "M3")) for (metric in c("AUC", "MAE", "RMSE")) {
      r <- if (metric == "AUC") "binary" else "joint_bb"
      key <- paste(metric, d, r, m, TRAIN_WEIGHTING, EVAL_WEIGHTING, sep = "|")
      old_key <- paste(metric, d, m, TRAIN_WEIGHTING, EVAL_WEIGHTING, sep = "|")
      near(stored_draws[[key]], old_draws[[old_key]])
      stopifnot(length(stored_draws[[key]]) == 50000L)
    }
    for (r in ROUTES) {
      count <- stored_counts[[paste("MeanLogScore", d, r, sep = "_")]]
      S <- length(count$species)
      set.seed(SEED + match(d, names(DESIGNS)) * 100L + match(r, ROUTES))
      expected_index <- matrix(sample.int(S, S * B_ELPD, replace = TRUE), nrow = S)
      stopifnot(identical(count$sampled_species_index, expected_index), all(colSums(count$counts) == S))
      for (m in c("M1", "M2", "M3")) stopifnot(length(stored_draws[[paste("MeanLogScore", d, r, m, TRAIN_WEIGHTING, EVAL_WEIGHTING, sep = "|")]]) == 2000L)
    }
  }
  stopifnot(identical(before, vapply(receipt_files, sha256_file, character(1))))
  cat("BOOTSTRAP_ORDER_PASS: AUC/error multiplicities identical, 18 draw vectors reconciled, four log-score seeds/index matrices preserved\n")

  # An explicitly synthetic boundary removes every point-eligible observation.
  # The persisted final suite also uses the production 2,000/50,000 replicates
  # for this boundary, with no bootstrap-size overrides.
  boundary <- new.env(parent = .GlobalEnv)
  source(file.path(repo, "v4", "R", "metric_functions.R"), local = boundary)
  changed <- evidence; j <- changed$Route == "joint_bb"
  changed$Type[j] <- "interval"; changed$ObservedPoint[j] <- NA_real_; changed$IntervalCovered[j] <- NA
  changed$RunPurpose <- "synthetic_no_point_boundary"
  empty_tables <- boundary$evaluate_tables(changed)
  empty_tests <- boundary$hypothesis_tests(changed, empty_tables$cv_metrics_summary)$hypothesis_tests
  error <- empty_tests$Metric %in% c("MAE", "RMSE")
  stopifnot(nrow(empty_tests) == 30L, sum(error) == 12L, all(is.na(empty_tests$P_approx[error])),
    all(is.na(empty_tests$P_BH3[error])), all(empty_tests$TestStatus[error] == "INSUFFICIENT_POINT_SPECIES"),
    nrow(empty_tables$quantitative_plot_source) == 0L, all(empty_tables$quantitative_bias_summary$PointSpeciesUsed == 0L),
    B_ELPD == 2000L, B_OTHER_METRICS == 50000L)
  cat("NO_POINT_BOUNDARY_PASS: all 12 error tests retained as flagged NA; 30 total tests; no fitted model run\n")

  # Reconciliation and receipts are written only after checking that evaluation
  # itself produced exactly its ten required files.
  reconciliation <- list()
  for (name in c(columns, "ELPD")) {
    a <- tables$cv_metrics_summary[[name]]; b <- previous[[name]]
    tolerance <- if (name == "ELPD") 1e-10 else 1e-12
    reconciliation[[length(reconciliation) + 1L]] <- cbind(tables$cv_metrics_summary[keys],
      data.frame(Metric = name, Comparison = "point_metric", Field = "Estimate",
        Recomputed = a, SavedBaseline = b, AbsoluteDifference = abs(a - b), Tolerance = tolerance,
        BothNA = is.na(a) & is.na(b),
        WithinTolerance = (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= tolerance)))
  }
  for (name in numeric_tests) {
    a <- tables$hypothesis_tests[[name]]; b <- previous_tests[[name]]
    reconciliation[[length(reconciliation) + 1L]] <- cbind(tables$hypothesis_tests[c(keys, "Metric")],
      data.frame(Comparison = "hypothesis", Field = name, Recomputed = a, SavedBaseline = b,
        AbsoluteDifference = abs(a - b), Tolerance = 1e-12, BothNA = is.na(a) & is.na(b),
        WithinTolerance = (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= 1e-12)))
  }
  reconciliation <- do.call(rbind, reconciliation)
  stopifnot(all(reconciliation$WithinTolerance))
  write_csv_atomic(reconciliation, file.path(output, "metric_reconciliation.csv"))
  after <- vapply(receipt_files, sha256_file, character(1))
  stopifnot(identical(before, after))
  receipt <- data.frame(Path = substring(receipt_files, nchar(repo) + 2L), Kind = receipt_kind,
    SHA256Before = unname(before), SHA256After = unname(after), Unchanged = unname(before == after))
  write_csv_atomic(receipt, file.path(output, "source_sha256_receipt.csv"))
  capture.output(sessionInfo(), file = file.path(output, "sessionInfo.txt"))
  status$status <- "PASS"
  status$evidence_rows <- nrow(evidence)
  status$output_rows <- list(cv_fold_metrics = nrow(tables$cv_fold_metrics), cv_metrics_summary = nrow(tables$cv_metrics_summary),
    hypothesis_tests = nrow(tables$hypothesis_tests), auc_fold_species_support = nrow(tables$auc_fold_species_support))
  status$hypothesis_families <- length(unique(tables$hypothesis_tests$FamilyID))
  status$bootstrap_draw_vectors <- length(stored_draws)
  status$bootstrap_multiplicity_groups <- length(stored_counts)
  status$auc_error_multiplicities_identical <- TRUE
  status$auc_error_draw_vectors_reconciled <- 18L
  status$log_score_seed_index_sequences_identical <- 4L
  status$max_abs_p_difference <- max_p_difference
  status$max_abs_ci_difference <- max_ci_difference
  status$reconciliation_rows <- nrow(reconciliation)
  status$all_source_hashes_unchanged <- all(receipt$Unchanged)
  status$source_hashes_checked <- nrow(receipt)
  status$R_version <- R.version.string
  status$RNG_kind <- RNGkind()
  status$production_output_sha256 <- as.list(setNames(vapply(file.path(output, expected_files), sha256_file, character(1)), expected_files))
  if (persistent) cat("PERSISTENT_EVIDENCE_SAVED:", output, "\n")
}

run_metric_tests(persistent_output)
cat("V4_METRICS_PASS\n")
