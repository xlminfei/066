# Evaluation is fixed to species-equal weights on record-equal fits. Intervals
# and tests below condition on saved OOF predictions; no bootstrap refits occur.
metric_columns <- function(x, required) {
  if (!is.data.frame(x) || anyDuplicated(names(x)) || !all(required %in% names(x))) {
    stop("Metric table lacks required, uniquely named columns: ", paste(required, collapse = ", "))
  }
  invisible(TRUE)
}

metric_ids <- function(x, columns) {
  metric_columns(x, columns)
  for (nm in columns) {
    value <- as.character(x[[nm]])
    if (anyNA(value) || any(!nzchar(trimws(value)))) stop("Invalid metric identifier: ", nm)
  }
  invisible(TRUE)
}

metric_key <- function(x, columns) do.call(paste, c(x[columns], sep = "|"))

weighted_mean <- function(x, weight) {
  if (!length(x) || length(x) != length(weight) || any(!is.finite(x)) ||
      any(!is.finite(weight)) || any(weight <= 0)) stop("Invalid weighted metric inputs")
  sum(x * weight) / sum(weight)
}

weighted_auc <- function(y, score, weight = rep(1, length(y))) {
  if (!length(y) || length(y) != length(score) || length(y) != length(weight) ||
      anyNA(y) || any(!y %in% c(0L, 1L)) || any(!is.finite(score)) ||
      any(score < 0 | score > 1) || any(!is.finite(weight)) || any(weight <= 0)) {
    stop("Invalid binary labels, probabilities, or AUC weights")
  }
  positive <- y == 1L; negative <- y == 0L
  if (!any(positive) || !any(negative)) return(NA_real_)
  difference <- outer(score[positive], score[negative], "-")
  sum(((difference > 0) + .5 * (difference == 0)) *
        outer(weight[positive], weight[negative])) /
    (sum(weight[positive]) * sum(weight[negative]))
}

roc_coordinates <- function(y, score, weight = rep(1, length(y))) {
  auc <- weighted_auc(y, score, weight)
  if (!is.finite(auc)) stop("ROC requires both binary classes; never omit an invalid fold")
  order <- order(-score, score)
  y <- y[order]; score <- score[order]; weight <- weight[order]
  groups <- split(seq_along(score), cumsum(c(TRUE, diff(score) != 0)))
  positive <- cumsum(vapply(groups, function(i) sum(weight[i][y[i] == 1L]), numeric(1)))
  negative <- cumsum(vapply(groups, function(i) sum(weight[i][y[i] == 0L]), numeric(1)))
  out <- data.frame(Threshold = c(Inf, vapply(groups, function(i) score[i[1L]], numeric(1))),
                    FPR = c(0, negative / sum(weight[y == 0L])),
                    TPR = c(0, positive / sum(weight[y == 1L])))
  out$FPR[nrow(out)] <- 1; out$TPR[nrow(out)] <- 1
  out
}

evaluate_evidence <- function(evidence) {
  metric_ids(evidence, c("Route", "Species", "RecordID"))
  metric_columns(evidence, "LogPredictiveDensityRaw")
  route <- unique(as.character(evidence$Route))
  if (!nrow(evidence) || length(route) != 1L || !route %in% ROUTES ||
      anyDuplicated(evidence$RecordID) || any(!is.finite(evidence$LogPredictiveDensityRaw))) {
    stop("Invalid route, duplicate record, empty evidence, or nonfinite held-out log score")
  }
  weight <- species_weights(evidence$Species)
  mean_log_score <- weighted_mean(evidence$LogPredictiveDensityRaw, weight)
  out <- data.frame(Route = route, EvalWeighting = EVAL_WEIGHTING,
    RecordsUsed = nrow(evidence), SpeciesUsed = length(unique(evidence$Species)),
    LogScoreRecordsUsed = nrow(evidence), LogScoreSpeciesUsed = length(unique(evidence$Species)),
    PointSpeciesUsed = 0L, PISpeciesUsed = 0L, WeightSum = sum(weight),
    ELPD = mean_log_score * nrow(evidence), MeanLogScore = mean_log_score,
    AUC = NA_real_, Brier = NA_real_, MAE = NA_real_, RMSE = NA_real_, Bias = NA_real_,
    PointRecords = 0L, PICoverage = NA_real_, MeanPIWidth = NA_real_, PIRecords = 0L,
    Aggregation = "species_equal_on_metric_valid_set", stringsAsFactors = FALSE)
  if (route == "binary") {
    metric_columns(evidence, c("ObservedHigh", "PredictedPrHigh"))
    out$AUC <- weighted_auc(evidence$ObservedHigh, evidence$PredictedPrHigh, weight)
    out$Brier <- weighted_mean((evidence$ObservedHigh - evidence$PredictedPrHigh)^2, weight)
    return(out)
  }
  metric_columns(evidence, c("Type", "ObservedPoint", "PredictedPoint", "PredictedPI_lower",
                              "PredictedPI_upper", "PIWidth", "IntervalCovered"))
  if (anyNA(evidence$Type) || any(!evidence$Type %in% c("count", "exact", "interval"))) {
    stop("Joint evidence requires count, exact, or interval types")
  }
  point <- evidence$Type %in% c("count", "exact")
  prediction <- evidence$PredictedPoint; observed <- evidence$ObservedPoint
  if (any(!is.finite(prediction)) || any(prediction < 0 | prediction > 1) ||
      any(!is.finite(observed[point])) || any(observed[point] < 0 | observed[point] > 1)) {
    stop("Joint point predictions and count/exact observations must be finite proportions")
  }
  lower <- evidence$PredictedPI_lower; upper <- evidence$PredictedPI_upper
  if (any(!is.finite(lower) | !is.finite(upper)) || any(lower < 0 | upper > 1 | lower > upper) ||
      any(!is.finite(evidence$PIWidth)) || any(abs(evidence$PIWidth - (upper - lower)) > 1e-10)) {
    stop("Invalid predictive interval or width")
  }
  covered <- observed[point] >= lower[point] & observed[point] <= upper[point]
  if (anyNA(evidence$IntervalCovered[point]) || any(covered != evidence$IntervalCovered[point])) {
    stop("Incorrect or missing count/exact predictive interval coverage")
  }
  # Interval observations contribute to log scores, never to point/PI metrics.
  if (any(point)) {
    point_weight <- species_weights(evidence$Species[point])
    error <- prediction[point] - observed[point]
    out$MAE <- weighted_mean(abs(error), point_weight)
    out$RMSE <- sqrt(weighted_mean(error^2, point_weight))
    out$Bias <- weighted_mean(error, point_weight)
    out$PICoverage <- weighted_mean(as.numeric(covered), point_weight)
    out$MeanPIWidth <- weighted_mean(evidence$PIWidth[point], point_weight)
  }
  out$PointRecords <- out$PIRecords <- sum(point)
  out$PointSpeciesUsed <- out$PISpeciesUsed <- length(unique(evidence$Species[point]))
  out
}

pair_evidence <- function(candidate, reference) {
  required <- c("RecordID", "Species", "Fold", "Type", "ObservedHigh", "ObservedPoint")
  metric_columns(candidate, required); metric_columns(reference, required)
  if (nrow(candidate) != nrow(reference) || anyDuplicated(candidate$RecordID) ||
      anyDuplicated(reference$RecordID) || !setequal(candidate$RecordID, reference$RecordID)) {
    stop("Candidate and same-training Null evidence are not record-paired")
  }
  reference <- reference[match(candidate$RecordID, reference$RecordID), , drop = FALSE]
  for (nm in c(required, intersect("OriginalRow", intersect(names(candidate), names(reference))))) {
    if (!identical(candidate[[nm]], reference[[nm]])) stop("Paired evidence mismatch: ", nm)
  }
  reference
}

check_metric_evidence <- function(evidence) {
  ids <- c("Design", "Route", "Model", "TrainWeighting", "RecordID", "Species")
  metric_ids(evidence, ids)
  metric_columns(evidence, c("Fold", "Type", "ObservedHigh", "ObservedPoint", "LogPredictiveDensityRaw"))
  if (!identical(TRAIN_WEIGHTING, "record_equal") || !identical(EVAL_WEIGHTING, "species_equal") ||
      any(!evidence$TrainWeighting %in% TRAIN_WEIGHTING) || any(!evidence$Design %in% names(DESIGNS)) ||
      any(!evidence$Route %in% ROUTES) || any(!evidence$Model %in% MODELS)) stop("Invalid evaluation identity")
  if ("EvalWeighting" %in% names(evidence) &&
      (anyNA(evidence$EvalWeighting) || any(evidence$EvalWeighting != EVAL_WEIGHTING))) stop("Invalid evaluation weighting")
  if (anyDuplicated(evidence[c("Design", "Route", "Model", "RecordID")])) stop("Duplicate OOF record keys")
  fold <- evidence$Fold
  if (!is.numeric(fold) || is.object(fold) || !is.null(dim(fold)) || length(fold) != nrow(evidence) ||
      any(!is.finite(fold)) || any(fold != trunc(fold))) {
    stop("Fold IDs must be finite integers")
  }
  for (design in names(DESIGNS)) for (route in ROUTES) {
    q <- evidence[evidence$Design == design & evidence$Route == route, , drop = FALSE]
    if (!setequal(q$Model, MODELS)) stop("Missing model in ", design, "/", route)
    null <- q[q$Model == "Null", , drop = FALSE]
    for (model in MODELS) {
      z <- q[q$Model == model, , drop = FALSE]
      pair_evidence(z, null)
      if (!setequal(z$Fold, seq_len(DESIGNS[[design]]))) stop("Missing or invalid fold IDs")
      if (any(vapply(split(z$Fold, as.character(z$Species)), function(f) length(unique(f)) != 1L, logical(1)))) {
        stop("A species appears in multiple folds")
      }
      evaluate_evidence(z)
    }
  }
  invisible(TRUE)
}

calibration_bins <- function(evidence, breaks = seq(0, 1, by = .2),
                             bootstrap = B_ELPD, seed = SEED) {
  if (any(evidence$Route != "binary") || anyNA(evidence$ObservedHigh) ||
      any(!evidence$ObservedHigh %in% c(0, 1))) stop("Calibration requires complete binary labels")
  evaluate_evidence(evidence)
  if (!is.numeric(breaks) || any(!is.finite(breaks)) || length(breaks) < 2L ||
      any(diff(breaks) <= 0) || min(breaks) != 0 || max(breaks) != 1) stop("Invalid calibration breaks")
  check_bootstrap_size(bootstrap)
  weight <- species_weights(evidence$Species)
  bin_id <- findInterval(evidence$PredictedPrHigh, breaks, rightmost.closed = TRUE, all.inside = TRUE)
  groups <- split(seq_len(nrow(evidence)), bin_id, drop = TRUE)
  rows <- lapply(names(groups), function(k) {
    bin <- as.integer(k); i <- groups[[k]]; species <- unique(as.character(evidence$Species[i]))
    # Keep full binary-set species weights inside each bin. Sampling order and
    # seed match the previous per-bin, paired species resampling loop.
    numerator <- vapply(species, function(s) sum(evidence$ObservedHigh[i][evidence$Species[i] == s] *
                                                  weight[i][evidence$Species[i] == s]), numeric(1))
    denominator <- vapply(species, function(s) sum(weight[i][evidence$Species[i] == s]), numeric(1))
    set.seed(seed + bin)
    sampled <- matrix(sample.int(length(species), length(species) * bootstrap, replace = TRUE), nrow = length(species))
    draws <- colSums(matrix(numerator[sampled], nrow = length(species))) /
      colSums(matrix(denominator[sampled], nrow = length(species)))
    if (any(!is.finite(draws))) stop("Nonfinite calibration bootstrap draw")
    interval <- quantile(draws, c(.025, .975), names = FALSE)
    status <- if (length(species) < 2L || bootstrap < 20L) "INSUFFICIENT_SUPPORT" else
      if (interval[2] <= interval[1]) "DEGENERATE_INTERVAL" else if (length(species) < 10L) "LIMITED_SPECIES" else "OK"
    data.frame(EvalWeighting = EVAL_WEIGHTING,
      Bin = paste0("[", breaks[bin], ",", breaks[bin + 1L], if (bin == length(breaks) - 1L) "]" else ")"),
      RecordsUsed = length(i), SpeciesUsed = length(species), WeightSum = sum(weight[i]),
      MeanPredicted = weighted_mean(evidence$PredictedPrHigh[i], weight[i]),
      ObservedRate = weighted_mean(evidence$ObservedHigh[i], weight[i]),
      CalibrationLower = interval[1], CalibrationUpper = interval[2],
      BootstrapValid = bootstrap, IntervalStatus = status, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

evaluate_tables <- function(evidence) {
  check_metric_evidence(evidence)
  folds <- summaries <- rocs <- calibration <- sources <- bias <- list()
  for (design in names(DESIGNS)) for (route in ROUTES) for (model in MODELS) {
    z <- evidence[evidence$Design == design & evidence$Route == route & evidence$Model == model, , drop = FALSE]
    key <- data.frame(Design = design, Model = model, TrainWeighting = TRAIN_WEIGHTING)
    group_folds <- lapply(seq_len(DESIGNS[[design]]), function(fold) {
      q <- z[z$Fold == fold, , drop = FALSE]
      result <- cbind(key, Fold = fold, evaluate_evidence(q))
      if (route == "binary") {
        if (!is.finite(result$AUC)) stop("Undefined fold AUC; no fold may be dropped")
        coords <- roc_coordinates(q$ObservedHigh, q$PredictedPrHigh, species_weights(q$Species))
        rocs[[length(rocs) + 1L]] <<- cbind(key, Route = route, Fold = fold,
          EvalWeighting = EVAL_WEIGHTING, AUC = result$AUC, coords)
      }
      result
    })
    fold_table <- do.call(rbind, group_folds)
    folds[[length(folds) + 1L]] <- fold_table
    summary <- cbind(key, FoldCount = DESIGNS[[design]], evaluate_evidence(z))
    summary$PooledAUC <- summary$AUC
    summary$FoldMeanAUC <- if (route == "binary") mean(fold_table$AUC) else NA_real_
    summary$AUC <- summary$FoldMeanAUC
    summary$Aggregation <- if (route == "binary") "full_design_records; AUC_is_unweighted_fold_mean; PooledAUC_is_descriptive_only" else "full_design_metric_valid_set"
    summaries[[length(summaries) + 1L]] <- summary
    if (route == "binary") {
      calibration[[length(calibration) + 1L]] <- cbind(key, Route = route, calibration_bins(z))
    } else {
      point <- z[z$Type %in% c("count", "exact"), , drop = FALSE]
      columns <- c("Design", "Fold", "Route", "Model", "TrainWeighting", "RecordID", "Species", "Type",
                   "ObservedPoint", "PredictedPoint", intersect(c("FitKey", "RunPurpose"), names(point)))
      source <- point[columns]
      source$EvalWeighting <- rep(EVAL_WEIGHTING, nrow(point))
      source$EvaluationWeight <- if (nrow(point)) species_weights(point$Species) else numeric()
      source$SignedError <- point$PredictedPoint - point$ObservedPoint
      sources[[length(sources) + 1L]] <- source
      bias[[length(bias) + 1L]] <- cbind(key, Route = route, EvalWeighting = EVAL_WEIGHTING,
        summary[c("LogScoreRecordsUsed", "LogScoreSpeciesUsed", "PointRecords", "PointSpeciesUsed", "PISpeciesUsed", "Bias")],
        BiasDefinition = "weighted_mean(predicted_minus_observed)", PointSet = "count_and_exact; interval_not_imputed")
    }
  }
  out <- lapply(list(cv_fold_metrics = folds, cv_metrics_summary = summaries, roc_coordinates = rocs,
    calibration_bins = calibration, quantitative_plot_source = sources, quantitative_bias_summary = bias),
    function(rows) { x <- do.call(rbind, rows); rownames(x) <- NULL; x })
  if (nrow(out$cv_fold_metrics) != sum(DESIGNS) * length(MODELS) * length(ROUTES) ||
      nrow(out$cv_metrics_summary) != length(DESIGNS) * length(MODELS) * length(ROUTES)) stop("Incomplete metric grid")
  out
}

check_bootstrap_size <- function(B) {
  if (length(B) != 1L || !is.numeric(B) || !is.finite(B) || B < 2L || B != trunc(B)) {
    stop("Bootstrap replicates must be an integer of at least two")
  }
  invisible(TRUE)
}

auc_species_stats <- function(d) {
  metric_ids(d, "Species")
  weighted_auc(d$ObservedHigh, d$PredictedPrHigh)
  species <- sort(unique(as.character(d$Species)))
  n <- vapply(species, function(s) sum(d$Species == s), integer(1))
  high <- vapply(species, function(s) sum(d$ObservedHigh[d$Species == s]), numeric(1))
  score <- vapply(species, function(s) {
    value <- unique(d$PredictedPrHigh[d$Species == s])
    if (length(value) != 1L) stop("Species score must be constant within its fitted fold")
    value
  }, numeric(1))
  list(species = species, n = n, high = high, low = n - high, score = score,
       type = ifelse(high == 0, "LOW_only", ifelse(high == n, "HIGH_only", "mixed")))
}

auc_from_cluster_counts <- function(meta, multiplicity) {
  if (is.null(dim(multiplicity))) multiplicity <- matrix(multiplicity, ncol = 1L)
  if (nrow(multiplicity) != length(meta$n) || any(!is.finite(multiplicity)) || any(multiplicity < 0)) {
    stop("Invalid species bootstrap multiplicities")
  }
  scale <- 1 / meta$n
  positive <- multiplicity * (meta$high * scale)
  negative <- multiplicity * (meta$low * scale)
  kernel <- outer(meta$score, meta$score, function(a, b) (a > b) + .5 * (a == b))
  denominator <- colSums(positive) * colSums(negative)
  if (any(!is.finite(denominator) | denominator <= 0)) stop("Undefined AUC resample; never drop a fold")
  colSums(positive * (kernel %*% negative)) / denominator
}

auc_stratified_counts <- function(meta, B, seed) {
  check_bootstrap_size(B)
  set.seed(seed)
  counts <- matrix(0L, length(meta$n), B)
  for (group in sort(unique(meta$type))) {
    i <- which(meta$type == group)
    counts[i, ] <- rmultinom(B, length(i), rep(1 / length(i), length(i)))
  }
  counts
}

error_species_stats <- function(d, prediction_columns) {
  if (!nrow(d) || any(!d$Type %in% c("count", "exact")) || any(!is.finite(d$ObservedPoint)) ||
      any(d$ObservedPoint < 0 | d$ObservedPoint > 1)) stop("Invalid point-eligible evidence")
  species <- sort(unique(as.character(d$Species)))
  n <- vapply(species, function(s) sum(d$Species == s), integer(1))
  absolute <- squared <- matrix(NA_real_, length(species), length(prediction_columns),
                               dimnames = list(species, prediction_columns))
  for (j in seq_along(prediction_columns)) {
    prediction <- d[[prediction_columns[j]]]
    if (any(!is.finite(prediction)) || any(prediction < 0 | prediction > 1)) stop("Invalid point prediction")
    error <- prediction - d$ObservedPoint
    for (i in seq_along(species)) {
      keep <- d$Species == species[i]
      absolute[i, j] <- sum(abs(error[keep])); squared[i, j] <- sum(error[keep]^2)
    }
  }
  list(species = species, n = n, absolute_error_sum = absolute, squared_error_sum = squared)
}

error_metrics_from_counts <- function(meta, multiplicity) {
  if (is.null(dim(multiplicity))) multiplicity <- matrix(multiplicity, ncol = 1L)
  if (nrow(multiplicity) != length(meta$n) || any(!is.finite(multiplicity)) ||
      any(multiplicity < 0) || any(colSums(multiplicity) <= 0)) stop("Invalid paired error bootstrap multiplicities")
  denominator <- colSums(multiplicity)
  list(MAE = crossprod(multiplicity, meta$absolute_error_sum / meta$n) / denominator,
       RMSE = sqrt(crossprod(multiplicity, meta$squared_error_sum / meta$n) / denominator))
}

normal_bootstrap_test <- function(difference, draws, minimum_se = 1e-12, se_draws = draws) {
  if (!is.finite(difference) || length(draws) < 2L || any(!is.finite(draws))) stop("Invalid bootstrap difference or draws")
  if (length(se_draws) != length(draws) || any(!is.finite(se_draws))) stop("Invalid bootstrap SE draws")
  se <- sd(se_draws); interval <- quantile(draws, c(.025, .975), names = FALSE)
  degenerate <- !is.finite(se) || se < minimum_se
  list(Difference = difference, SE_approx = se, Z_approx = if (degenerate) NA_real_ else difference / se,
    P_approx = if (degenerate) NA_real_ else 2 * pnorm(-abs(difference / se)),
    CI95_lower = interval[1], CI95_upper = interval[2],
    TestStatus = if (degenerate) "DEGENERATE_CLUSTER_BOOTSTRAP" else "CONDITIONAL_OOF_NORMAL_APPROXIMATION")
}

expected_hypotheses <- function() {
  rows <- list()
  for (design in names(DESIGNS)) for (route in ROUTES) {
    metrics <- if (route == "binary") c("AUC", "MeanLogScore") else c("MeanLogScore", "MAE", "RMSE")
    for (metric in metrics) rows[[length(rows) + 1L]] <- data.frame(Route = route, Metric = metric,
      Design = design, TrainWeighting = TRAIN_WEIGHTING, EvalWeighting = EVAL_WEIGHTING,
      Model = c("M1", "M2", "M3"), stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

adjust_hypothesis_families <- function(tests) {
  family <- c("Route", "Metric", "Design", "TrainWeighting", "EvalWeighting")
  identity <- c(family, "Model")
  metric_ids(tests, identity); metric_columns(tests, "P_approx")
  expected <- expected_hypotheses()
  if (nrow(tests) != 30L || anyDuplicated(tests[identity]) ||
      !setequal(metric_key(tests, identity), metric_key(expected, identity))) {
    stop("Hypothesis grid must contain exactly the 30 non-Null tests, once each")
  }
  p <- tests$P_approx
  if (!is.numeric(p) || is.object(p) || !is.null(dim(p)) || length(p) != nrow(tests) ||
      any(is.nan(p)) || any(!is.na(p) & (!is.finite(p) | p < 0 | p > 1))) {
    stop("Invalid P value; only finite [0,1] values or explicit NA are allowed")
  }
  groups <- split(seq_len(nrow(tests)), metric_key(tests, family))
  if (length(groups) != 10L || any(lengths(groups) != 3L)) stop("Expected ten BH families of three tests")
  tests$P_BH3 <- NA_real_; tests$FamilySize <- 3L
  tests$FamilyID <- metric_key(tests, family)
  for (i in groups) tests$P_BH3[i] <- p.adjust(p[i], method = "BH", n = 3L)
  tests
}

hypothesis_tests <- function(evidence, summary) {
  check_metric_evidence(evidence)
  keys <- c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")
  metric_ids(summary, keys)
  expected <- expand.grid(Design = names(DESIGNS), Route = ROUTES, Model = MODELS,
    TrainWeighting = TRAIN_WEIGHTING, EvalWeighting = EVAL_WEIGHTING, stringsAsFactors = FALSE)
  if (nrow(summary) != nrow(expected) || anyDuplicated(summary[keys]) ||
      !setequal(metric_key(summary, keys), metric_key(expected, keys))) stop("Incomplete, extra, or duplicated metric summary keys")
  metric_columns(summary, c("AUC", "MeanLogScore", "MAE", "RMSE"))
  check_bootstrap_size(B_ELPD); check_bootstrap_size(B_OTHER_METRICS)
  rows <- draws <- multiplicities <- support <- list()
  point_ref <- function(design, route, model, metric) {
    q <- summary[summary$Design == design & summary$Route == route & summary$Model == model &
                   summary$TrainWeighting == TRAIN_WEIGHTING & summary$EvalWeighting == EVAL_WEIGHTING, , drop = FALSE]
    if (nrow(q) != 1L) stop("Missing or duplicate summary metric key")
    q[[metric]][1L]
  }
  add <- function(design, route, model, metric, estimate, reference, stat, boot, n, species, B, seed_rule, support_note) {
    key <- paste(metric, design, route, model, TRAIN_WEIGHTING, EVAL_WEIGHTING, sep = "|")
    if (!is.null(draws[[key]])) stop("Duplicate bootstrap key")
    draws[[key]] <<- boot
    scaled <- if (metric == "MeanLogScore") stat$Difference * n else NA_real_
    rows[[length(rows) + 1L]] <<- cbind(data.frame(Route = route, Metric = metric, Design = design,
      TrainWeighting = TRAIN_WEIGHTING, EvalWeighting = EVAL_WEIGHTING, Model = model,
      Estimate = estimate, Reference = if (metric == "AUC") "chance_level_0.5" else "Null_same_training",
      ReferenceEstimate = reference, ELPD_Difference = scaled, RecordsUsed = n, SpeciesUsed = species,
      FoldCount = DESIGNS[[design]], BootstrapReplicates = B, BootstrapValid = length(boot), SeedRule = seed_rule,
      SupportNote = support_note, Alternative = "two.sided",
      InferenceScope = "fixed_OOF_predictions_conditional_exploratory_no_refitting",
      CIKind = "percentile_species_cluster_bootstrap_interval_for_difference", stringsAsFactors = FALSE),
      as.data.frame(stat, stringsAsFactors = FALSE))
  }
  for (di in seq_along(DESIGNS)) {
    design <- names(DESIGNS)[di]; k <- DESIGNS[[di]]
    # MeanLogScore and ELPD are the same test after multiplication by N.
    for (ri in seq_along(ROUTES)) {
      route <- ROUTES[ri]
      z <- evidence[evidence$Design == design & evidence$Route == route, , drop = FALSE]
      null <- z[z$Model == "Null", , drop = FALSE]
      species <- sort(unique(as.character(null$Species))); S <- length(species)
      seed <- SEED + di * 100L + ri
      set.seed(seed)
      index <- matrix(sample.int(S, S * B_ELPD, replace = TRUE), nrow = S)
      counts <- vapply(seq_len(B_ELPD), function(b) tabulate(index[, b], nbins = S), integer(S))
      multiplicities[[paste("MeanLogScore", design, route, sep = "_")]] <-
        list(species = species, counts = matrix(counts, nrow = S), sampled_species_index = index, seed = seed)
      for (model in setdiff(MODELS, "Null")) {
        candidate <- z[z$Model == model, , drop = FALSE]; reference <- pair_evidence(candidate, null)
        delta <- candidate$LogPredictiveDensityRaw - reference$LogPredictiveDensityRaw
        means <- vapply(species, function(s) sum(delta[candidate$Species == s]) / sum(candidate$Species == s), numeric(1))
        boot <- colMeans(matrix(means[index], nrow = S))
        stat <- normal_bootstrap_test(mean(means), boot, minimum_se = sqrt(.Machine$double.eps))
        if (S < 2L) {
          stat[c("SE_approx", "Z_approx", "P_approx", "CI95_lower", "CI95_upper")] <- NA_real_
          stat$TestStatus <- "INSUFFICIENT_SPECIES"
        } else if (stat$SE_approx <= sqrt(.Machine$double.eps)) {
          stat$P_approx <- stat$Z_approx <- NA_real_; stat$TestStatus <- "DEGENERATE_BOOTSTRAP"
        } else if (S < 10L) {
          stat$P_approx <- NA_real_; stat$TestStatus <- "LIMITED_SPECIES"
        } else stat$TestStatus <- "CONDITIONAL_OOF_APPROXIMATION"
        add(design, route, model, "MeanLogScore", point_ref(design, route, model, "MeanLogScore"),
            point_ref(design, route, "Null", "MeanLogScore"), stat, boot, nrow(candidate), S, B_ELPD,
            "SEED+100*design_index+route_index; sample.int sorted species", "paired_whole_design_species_bootstrap")
      }
    }
    binary <- evidence[evidence$Design == design & evidence$Route == "binary", , drop = FALSE]
    null <- binary[binary$Model == "Null", , drop = FALSE]
    meta <- counts <- vector("list", k)
    for (f in seq_len(k)) {
      meta[[f]] <- auc_species_stats(null[null$Fold == f, , drop = FALSE])
      seed <- SEED_OTHER + 1000L * di + 10L * f
      counts[[f]] <- auc_stratified_counts(meta[[f]], B_OTHER_METRICS, seed)
      m <- meta[[f]]
      if (abs(auc_from_cluster_counts(m, rep(1, length(m$n))) - .5) > 1e-12) stop("Null has unexpected within-fold discrimination")
      support[[length(support) + 1L]] <- data.frame(Design = design, Fold = f, Species = length(m$n),
        Records = sum(m$n), HighOnly = sum(m$type == "HIGH_only"), LowOnly = sum(m$type == "LOW_only"),
        Mixed = sum(m$type == "mixed"), HighBearingSpecies = sum(m$high > 0), LowBearingSpecies = sum(m$low > 0),
        SingletonOutcomeStrata = sum(table(m$type) == 1L), Seed = seed)
    }
    multiplicities[[paste0("AUC_", design)]] <- list(metas = meta, counts = counts)
    support_note <- if (any(vapply(meta, function(m) sum(m$low > 0) < 2L || sum(m$high > 0) < 2L, logical(1))))
      "LIMITED_CLASS_SPECIES_IN_SOME_FOLDS" else "CONDITIONAL_ON_FOLD_AND_SPECIES_OUTCOME_STRATA"
    for (model in setdiff(MODELS, "Null")) {
      z <- binary[binary$Model == model, , drop = FALSE]; pair_evidence(z, null)
      point <- numeric(k); boot <- numeric(B_OTHER_METRICS)
      for (f in seq_len(k)) {
        m <- auc_species_stats(z[z$Fold == f, , drop = FALSE])
        if (!identical(m$species, meta[[f]]$species) || !identical(m$n, meta[[f]]$n) || !identical(m$high, meta[[f]]$high)) stop("Unpaired AUC species strata")
        point[f] <- auc_from_cluster_counts(m, rep(1, length(m$n)))
        boot <- boot + auc_from_cluster_counts(m, counts[[f]]) / k
      }
      if (abs(mean(point) - point_ref(design, "binary", model, "AUC")) > 1e-12) stop("AUC is not the equal-fold mean")
      # Calculate SE on AUC draws, as in the original supplement, then retain
      # differences. Shifting draws before sd() can change rounding at tiny SE.
      stat <- normal_bootstrap_test(mean(point) - .5, boot - .5, se_draws = boot)
      add(design, "binary", model, "AUC", mean(point), .5, stat, boot - .5, nrow(z),
          length(unique(z$Species)), B_OTHER_METRICS, "SEED_OTHER+1000*design_index+10*fold; rmultinom", support_note)
    }
    # A single paired species resample is shared by MAE and RMSE and all models.
    joint <- evidence[evidence$Design == design & evidence$Route == "joint_bb" &
                        evidence$Type %in% c("count", "exact"), , drop = FALSE]
    null <- joint[joint$Model == "Null", , drop = FALSE]; null <- null[order(null$RecordID), , drop = FALSE]
    seed <- SEED_OTHER + 1000L * di + 999L
    if (!nrow(null)) {
      for (metric in c("MAE", "RMSE")) for (model in setdiff(MODELS, "Null")) {
        stat <- list(Difference = NA_real_, SE_approx = NA_real_, Z_approx = NA_real_, P_approx = NA_real_,
                     CI95_lower = NA_real_, CI95_upper = NA_real_, TestStatus = "INSUFFICIENT_POINT_SPECIES")
        add(design, "joint_bb", model, metric, NA_real_, NA_real_, stat, numeric(), 0L, 0L,
            B_OTHER_METRICS, "SEED_OTHER+1000*design_index+999; rmultinom", "no_count_or_exact_observations")
      }
      multiplicities[[paste0("ERROR_", design)]] <- list(species = character(), counts = matrix(integer(), 0L, 0L), seed = seed)
      next
    }
    data <- null[c("RecordID", "Species", "Type", "ObservedPoint", "Fold")]
    for (model in MODELS) {
      z <- joint[joint$Model == model, , drop = FALSE]; pair_evidence(z, null)
      data[[model]] <- z$PredictedPoint[match(null$RecordID, z$RecordID)]
    }
    m <- error_species_stats(data, MODELS); S <- length(m$n)
    set.seed(seed); counts <- rmultinom(B_OTHER_METRICS, S, rep(1 / S, S))
    multiplicities[[paste0("ERROR_", design)]] <- list(meta = m, counts = counts, seed = seed)
    point <- error_metrics_from_counts(m, rep(1, S)); boot <- error_metrics_from_counts(m, counts)
    for (metric in c("MAE", "RMSE")) for (model in setdiff(MODELS, "Null")) {
      estimate <- point[[metric]][1L, model]; reference <- point[[metric]][1L, "Null"]
      if (abs(estimate - point_ref(design, "joint_bb", model, metric)) > 1e-12) stop("Point error metric does not match summary")
      delta <- boot[[metric]][, model] - boot[[metric]][, "Null"]
      stat <- normal_bootstrap_test(estimate - reference, delta)
      add(design, "joint_bb", model, metric, estimate, reference, stat, delta, nrow(null), S,
          B_OTHER_METRICS, "SEED_OTHER+1000*design_index+999; rmultinom", "paired_species_bootstrap_complete_point_subset")
    }
  }
  tests <- adjust_hypothesis_families(do.call(rbind, rows)); rownames(tests) <- NULL
  list(hypothesis_tests = tests, auc_fold_species_support = do.call(rbind, support),
       bootstrap_draws = draws, bootstrap_multiplicities = multiplicities)
}
