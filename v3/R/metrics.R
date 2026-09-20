log_mean_exp <- function(x) {
  if (!length(x)) return(-Inf)
  if (all(is.infinite(x) & x < 0)) return(-Inf)
  m <- max(x[is.finite(x)])
  m + log(mean(exp(x - m)))
}

safe_log_diff_exp <- function(a, b) {
  if (is.na(a) || is.na(b) || b > a) return(NA_real_)
  if (is.infinite(a) && a < 0) return(-Inf)
  if (is.infinite(b) && b < 0) return(a)
  if (a == b) return(-Inf)
  a + log1p(-exp(b - a))
}

weighted_mean <- function(x, weight) {
  ok <- is.finite(x) & is.finite(weight) & weight > 0
  if (!any(ok)) return(NA_real_)
  sum(x[ok] * weight[ok]) / sum(weight[ok])
}

weighted_auc <- function(y, score, weight = rep(1, length(y))) {
  if (length(y) != length(score) || length(y) != length(weight)) stop("AUC inputs have different lengths")
  ok <- is.finite(score) & is.finite(weight) & weight > 0 & !is.na(y)
  y <- as.integer(y[ok]); score <- as.numeric(score[ok]); weight <- as.numeric(weight[ok])
  if (!length(y) || !all(y %in% c(0L, 1L))) stop("AUC truth must be binary")
  pos <- y == 1L; neg <- y == 0L
  wp <- sum(weight[pos]); wn <- sum(weight[neg])
  if (wp <= 0 || wn <= 0) return(NA_real_)
  pair <- outer(score[pos], score[neg], FUN = "-")
  contribution <- (pair > 0) + 0.5 * (pair == 0)
  as.numeric(sum(contribution * outer(weight[pos], weight[neg])) / (wp * wn))
}

roc_coordinates <- function(y, score, weight = rep(1, length(y))) {
  if (length(y) != length(score) || length(y) != length(weight)) stop("ROC inputs have different lengths")
  ok <- is.finite(score) & is.finite(weight) & weight > 0 & !is.na(y)
  y <- as.integer(y[ok]); score <- as.numeric(score[ok]); weight <- as.numeric(weight[ok])
  if (!length(y) || !all(y %in% c(0L, 1L))) stop("ROC truth must be binary")
  wp <- sum(weight[y == 1L]); wn <- sum(weight[y == 0L])
  if (wp <= 0 || wn <= 0) return(data.frame(Threshold = numeric(), FPR = numeric(), TPR = numeric()))
  ord <- order(-score, score)
  score <- score[ord]; y <- y[ord]; weight <- weight[ord]
  groups <- split(seq_along(score), cumsum(c(TRUE, diff(score) != 0)))
  rows <- list(data.frame(Threshold = Inf, FPR = 0, TPR = 0))
  cum_pos <- 0; cum_neg <- 0
  for (g in groups) {
    cum_pos <- cum_pos + sum(weight[g][y[g] == 1L])
    cum_neg <- cum_neg + sum(weight[g][y[g] == 0L])
    rows[[length(rows) + 1L]] <- data.frame(Threshold = score[g[[1L]]],
                                             FPR = cum_neg / wn, TPR = cum_pos / wp)
  }
  do.call(rbind, rows)
}

weighted_brier <- function(y, p, weight = rep(1, length(y))) weighted_mean((y - p)^2, weight)
weighted_mae <- function(y, p, weight = rep(1, length(y))) weighted_mean(abs(y - p), weight)
weighted_rmse <- function(y, p, weight = rep(1, length(y))) sqrt(weighted_mean((y - p)^2, weight))

evaluate_evidence <- function(evidence, eval_weighting = "record_equal", route = NULL) {
  if (!nrow(evidence)) stop("Cannot score an empty evidence table")
  route <- route %||% unique(evidence$Route)[[1L]]
  if (route == "binary") {
    valid <- !is.na(evidence$ObservedHigh) & is.finite(evidence$PredictedPrHigh) &
      is.finite(evidence$LogPredictiveDensityRaw)
    z <- evidence[valid, , drop = FALSE]
    if (!nrow(z)) stop("No valid binary evidence rows")
    wf <- build_eval_weights(z[, "Species", drop = FALSE], eval_weighting)
    out <- data.frame(Route = route, EvalWeighting = eval_weighting,
      RecordsUsed = nrow(z), SpeciesUsed = length(unique(z$Species)),
      WeightSum = sum(wf$weight), ELPD = sum(wf$weight * z$LogPredictiveDensityRaw),
      MeanLogScore = weighted_mean(z$LogPredictiveDensityRaw, wf$weight),
      AUC = weighted_auc(z$ObservedHigh, z$PredictedPrHigh, wf$weight),
      Brier = weighted_brier(z$ObservedHigh, z$PredictedPrHigh, wf$weight),
      MAE = NA_real_, RMSE = NA_real_, PointRecords = 0L,
      Aggregation = "weighted_record_or_species", stringsAsFactors = FALSE)
    out
  } else {
    valid <- is.finite(evidence$LogPredictiveDensityRaw)
    z <- evidence[valid, , drop = FALSE]
    if (!nrow(z)) stop("No valid joint evidence rows")
    wf <- build_eval_weights(z[, "Species", drop = FALSE], eval_weighting)
    point <- is.finite(z$ObservedPoint) & is.finite(z$PredictedPoint)
    wp <- if (any(point)) build_eval_weights(z[point, "Species", drop = FALSE], eval_weighting)$weight else numeric()
    out <- data.frame(Route = route, EvalWeighting = eval_weighting,
      RecordsUsed = nrow(z), SpeciesUsed = length(unique(z$Species)),
      WeightSum = sum(wf$weight), ELPD = sum(wf$weight * z$LogPredictiveDensityRaw),
      MeanLogScore = weighted_mean(z$LogPredictiveDensityRaw, wf$weight),
      AUC = NA_real_, Brier = NA_real_,
      MAE = if (any(point)) weighted_mae(z$ObservedPoint[point], z$PredictedPoint[point], wp) else NA_real_,
      RMSE = if (any(point)) weighted_rmse(z$ObservedPoint[point], z$PredictedPoint[point], wp) else NA_real_,
      PointRecords = sum(point), Aggregation = "weighted_record_or_species", stringsAsFactors = FALSE)
    out
  }
}

calibration_bins <- function(evidence, eval_weighting = "record_equal",
                             breaks = seq(0, 1, by = 0.2), bootstrap = 2000L,
                             seed = V3_SEED) {
  z <- evidence[!is.na(evidence$ObservedHigh) & is.finite(evidence$PredictedPrHigh), , drop = FALSE]
  if (!nrow(z)) return(data.frame())
  wf <- build_eval_weights(z[, "Species", drop = FALSE], eval_weighting)
  z$Bin <- cut(z$PredictedPrHigh, breaks = breaks, include.lowest = TRUE, right = FALSE)
  rows <- lapply(seq_along(split(seq_len(nrow(z)), z$Bin, drop = TRUE)), function(k) {
    groups <- split(seq_len(nrow(z)), z$Bin, drop = TRUE)
    ii <- groups[[k]]; species <- unique(z$Species[ii])
    point_pred <- weighted_mean(z$PredictedPrHigh[ii], wf$weight[ii])
    point_obs <- weighted_mean(z$ObservedHigh[ii], wf$weight[ii])
    set.seed(seed + k)
    boot <- rep(NA_real_, bootstrap)
    if (length(species)) for (b in seq_len(bootstrap)) {
      sampled <- sample(species, length(species), replace = TRUE)
      pieces <- lapply(seq_along(sampled), function(rep_id) {
        q <- z[ii[z$Species[ii] == sampled[[rep_id]]], , drop = FALSE]
        q$ClusterID <- paste0(sampled[[rep_id]], "#", rep_id)
        q
      })
      qb <- do.call(rbind, pieces)
      if (eval_weighting == "record_equal") wb <- rep(1, nrow(qb)) else {
        counts <- table(qb$ClusterID)
        wb <- nrow(qb) / (length(sampled) * as.numeric(counts[qb$ClusterID]))
      }
      boot[[b]] <- weighted_mean(qb$ObservedHigh, wb)
    }
    valid <- is.finite(boot)
    data.frame(EvalWeighting = eval_weighting, Bin = as.character(z$Bin[ii]),
      RecordsUsed = length(ii), SpeciesUsed = length(species), WeightSum = sum(wf$weight[ii]),
      MeanPredicted = point_pred, ObservedRate = point_obs,
      CalibrationLower = if (any(valid)) stats::quantile(boot[valid], .025, names = FALSE) else NA_real_,
      CalibrationUpper = if (any(valid)) stats::quantile(boot[valid], .975, names = FALSE) else NA_real_,
      BootstrapValid = sum(valid), IntervalStatus = if (!length(species)) "INSUFFICIENT_SUPPORT" else
        if (sum(valid) < max(20L, bootstrap / 2)) "INSUFFICIENT_SUPPORT" else "OK",
      stringsAsFactors = FALSE)
  })
  if (length(rows)) do.call(rbind, rows) else data.frame()
}
