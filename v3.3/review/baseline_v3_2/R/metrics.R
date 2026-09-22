log_mean_exp <- function(x) {
  if (!length(x) || anyNA(x)) stop("Empty or NA log draws")
  if (any(is.nan(x)) || any(is.infinite(x) & x > 0)) stop("log_mean_exp received invalid positive/NaN values")
  if (all(is.infinite(x) & x < 0)) return(-Inf)
  finite <- is.finite(x)
  m <- max(x[finite])
  m + log(mean(exp(x - m)))
}

safe_log_diff_exp <- function(a, b) {
  if (is.na(a) || is.na(b) || b > a) return(NA_real_)
  if (is.infinite(a) && a < 0) return(-Inf)
  if (is.infinite(b) && b < 0) return(a)
  if (a == b) return(-Inf)
  a + log1p(-exp(b - a))
}

weighted_mean <- function(x, weight, allow_missing = FALSE) {
  if (length(x) != length(weight)) stop("Metric inputs have different lengths")
  invalid <- !is.finite(x) | !is.finite(weight) | weight <= 0
  if (any(invalid) && !allow_missing) stop("Non-finite or non-positive metric input")
  ok <- !invalid
  if (!any(ok)) return(NA_real_)
  sum(x[ok] * weight[ok]) / sum(weight[ok])
}

validate_auc_inputs <- function(y, score, weight) {
  if (length(y) != length(score) || length(y) != length(weight)) stop("AUC inputs have different lengths")
  if (anyNA(y) || any(!is.finite(score)) || any(!is.finite(weight)) || any(weight <= 0)) {
    stop("AUC inputs contain missing/non-finite values")
  }
  if (!length(y) || !all(y %in% c(0L, 1L))) stop("AUC truth must be binary")
  list(y = y, score = as.numeric(score), weight = as.numeric(weight))
}

weighted_auc <- function(y, score, weight = rep(1, length(y))) {
  z <- validate_auc_inputs(y, score, weight)
  y <- z$y; score <- z$score; weight <- z$weight
  pos <- y == 1L; neg <- y == 0L
  wp <- sum(weight[pos]); wn <- sum(weight[neg])
  if (wp <= 0 || wn <= 0) return(NA_real_)
  pair <- outer(score[pos], score[neg], FUN = "-")
  contribution <- (pair > 0) + 0.5 * (pair == 0)
  as.numeric(sum(contribution * outer(weight[pos], weight[neg])) / (wp * wn))
}

roc_coordinates <- function(y, score, weight = rep(1, length(y))) {
  z <- validate_auc_inputs(y, score, weight)
  y <- z$y; score <- z$score; weight <- z$weight
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
  ans<-do.call(rbind, rows);ans$FPR[nrow(ans)]<-1;ans$TPR[nrow(ans)]<-1;ans
}

weighted_brier <- function(y, p, weight = rep(1, length(y))) weighted_mean((y - p)^2, weight)
weighted_mae <- function(y, p, weight = rep(1, length(y))) weighted_mean(abs(y - p), weight)
weighted_rmse <- function(y, p, weight = rep(1, length(y))) sqrt(weighted_mean((y - p)^2, weight))
weighted_bias <- function(y, p, weight = rep(1, length(y))) weighted_mean(p - y, weight)

assert_score_column <- function(evidence) {
  if (!"LogPredictiveDensityRaw" %in% names(evidence)) stop("Evidence lacks LogPredictiveDensityRaw")
  bad <- !is.finite(evidence$LogPredictiveDensityRaw)
  if (any(bad)) {
    ids <- if ("RecordID" %in% names(evidence)) as.character(evidence$RecordID[bad]) else as.character(which(bad))
    stop("Non-finite held-out log score for record(s): ", paste(ids, collapse = ", "))
  }
}

evaluate_evidence <- function(evidence, eval_weighting = "record_equal", route = NULL) {
  if (!nrow(evidence)) stop("Cannot score an empty evidence table")
  route <- route %||% unique(evidence$Route)[[1L]]
  if (!identical(unique(as.character(evidence$Route)),route)) stop("Evidence route mismatch")
  if (length(unique(evidence$Route)) > 1L) stop("Evidence contains multiple routes")
  assert_score_column(evidence)
  if (route == "binary") {
    if (anyNA(evidence$ObservedHigh) || any(!is.finite(evidence$PredictedPrHigh))) {
      stop("Binary evidence has missing/non-finite observed labels or predictions")
    }
    if(any(!evidence$ObservedHigh%in%c(0,1))||any(evidence$PredictedPrHigh<0|evidence$PredictedPrHigh>1))stop("Invalid binary label/probability")
    z <- evidence
    wf <- build_eval_weights(z[, "Species", drop = FALSE], eval_weighting)
    out <- data.frame(Route = route, EvalWeighting = eval_weighting,
      RecordsUsed = nrow(z), SpeciesUsed = length(unique(z$Species)),
      LogScoreRecordsUsed = nrow(z), LogScoreSpeciesUsed = length(unique(z$Species)),
      PointSpeciesUsed = 0L, PISpeciesUsed = 0L,
      WeightSum = sum(wf$weight), ELPD = sum(wf$weight * z$LogPredictiveDensityRaw),
      MeanLogScore = weighted_mean(z$LogPredictiveDensityRaw, wf$weight),
      AUC = weighted_auc(z$ObservedHigh, z$PredictedPrHigh, wf$weight),
      Brier = weighted_brier(z$ObservedHigh, z$PredictedPrHigh, wf$weight),
      MAE = NA_real_, RMSE = NA_real_, Bias = NA_real_, PointRecords = 0L,
       PICoverage = NA_real_, MeanPIWidth = NA_real_, PIRecords = 0L,
       Aggregation = "weighted_record_or_species", stringsAsFactors = FALSE)
    return(out)
  }
  if (route != "joint_bb") stop("Unknown evidence route: ", route)
  if(!"Type"%in%names(evidence)||any(!evidence$Type%in%c("count","exact","interval")))stop("Joint evidence requires Type")
  point <- evidence$Type%in%c("count","exact")
  bad <- !is.finite(evidence$PredictedPoint) | (point & !is.finite(evidence$ObservedPoint))
  if(any(bad))stop("Nonfinite joint point inputs; records: ",paste((evidence$RecordID%||%seq_len(nrow(evidence)))[bad],collapse=","))
  fields<-c("PredictedPI_lower","PredictedPI_upper","PIWidth","IntervalCovered")
  if(!all(fields%in%names(evidence)))stop("Joint evidence lacks predictive intervals")
  lo<-evidence$PredictedPI_lower;hi<-evidence$PredictedPI_upper
  if(any(!is.finite(lo)|!is.finite(hi)|lo<0|hi>1|lo>hi)||any(!is.finite(evidence$PIWidth))||any(abs(evidence$PIWidth-(hi-lo))>1e-10))stop("Invalid predictive interval or width")
  covered<-evidence$ObservedPoint[point]>=lo[point]&evidence$ObservedPoint[point]<=hi[point]
  if(anyNA(evidence$IntervalCovered[point])||any(covered!=evidence$IntervalCovered[point]))stop("Incorrect or missing interval coverage")
  z<-evidence;wf<-build_eval_weights(z[,"Species",drop=FALSE],eval_weighting)
  wp<-if(any(point))build_eval_weights(z[point,"Species",drop=FALSE],eval_weighting)$weight else numeric()
  out<-data.frame(Route=route,EvalWeighting=eval_weighting,RecordsUsed=nrow(z),SpeciesUsed=length(unique(z$Species)),
    LogScoreRecordsUsed=nrow(z),LogScoreSpeciesUsed=length(unique(z$Species)),
    PointSpeciesUsed=length(unique(z$Species[point])),PISpeciesUsed=length(unique(z$Species[point])),WeightSum=sum(wf$weight),
    ELPD=sum(wf$weight*z$LogPredictiveDensityRaw),MeanLogScore=weighted_mean(z$LogPredictiveDensityRaw,wf$weight),AUC=NA_real_,Brier=NA_real_,
    MAE=if(any(point))weighted_mae(z$ObservedPoint[point],z$PredictedPoint[point],wp) else NA_real_,
    RMSE=if(any(point))weighted_rmse(z$ObservedPoint[point],z$PredictedPoint[point],wp) else NA_real_,
    Bias=if(any(point))weighted_bias(z$ObservedPoint[point],z$PredictedPoint[point],wp) else NA_real_,PointRecords=sum(point),
    PICoverage=if(any(point))weighted_mean(as.numeric(covered),wp) else NA_real_,
    MeanPIWidth=if(any(point))weighted_mean(z$PIWidth[point],wp) else NA_real_,PIRecords=sum(point),Aggregation="full_metric_valid_set_weights; PI_matches_record_observation_model")
  out
}

calibration_bins <- function(evidence, eval_weighting = "record_equal",
                             breaks = seq(0, 1, by = 0.2), bootstrap = 2000L,
                             seed = V3_SEED) {
  if (any(!is.na(evidence$ObservedHigh) & !is.finite(evidence$PredictedPrHigh))) {
    stop("Calibration evidence has non-finite predictions for labelled records")
  }
  z <- evidence[!is.na(evidence$ObservedHigh), , drop = FALSE]
  if (!nrow(z)) return(data.frame())
  if (any(!is.finite(z$PredictedPrHigh)) || any(z$PredictedPrHigh < 0 | z$PredictedPrHigh > 1)) {
    stop("Calibration predictions must be finite and within [0,1]")
  }
  if (any(diff(breaks) <= 0)) stop("Calibration breaks must be strictly increasing")
  wf <- build_eval_weights(z[, "Species", drop = FALSE], eval_weighting)
  bin_id <- findInterval(z$PredictedPrHigh, breaks, rightmost.closed = TRUE, all.inside = TRUE)
  bin_id[bin_id >= length(breaks)] <- length(breaks) - 1L
  groups <- split(seq_len(nrow(z)), bin_id, drop = TRUE)
  rows <- lapply(names(groups), function(k) {
    kk <- as.integer(k); ii <- groups[[k]]; species <- unique(z$Species[ii])
    point_pred <- weighted_mean(z$PredictedPrHigh[ii], wf$weight[ii])
    point_obs <- weighted_mean(z$ObservedHigh[ii], wf$weight[ii])
    set.seed(seed + kk)
    boot <- rep(NA_real_, bootstrap)
    if (length(species)) for (b in seq_len(bootstrap)) {
      sampled <- sample(species, length(species), replace = TRUE)
      pieces <- lapply(seq_along(sampled), function(rep_id) {
        q <- z[ii[z$Species[ii] == sampled[[rep_id]]], , drop = FALSE]
        q$ClusterID <- paste0(sampled[[rep_id]], "#", rep_id)
        q$BootstrapWeight <- wf$weight[ii[z$Species[ii] == sampled[[rep_id]]]]
        q
      })
      qb <- do.call(rbind, pieces)
      wb <- qb$BootstrapWeight
      boot[[b]] <- weighted_mean(qb$ObservedHigh, wb)
    }
    valid <- is.finite(boot)
    lower <- if (any(valid)) stats::quantile(boot[valid], .025, names = FALSE) else NA_real_
    upper <- if (any(valid)) stats::quantile(boot[valid], .975, names = FALSE) else NA_real_
    status <- if (length(species) < 2L) "INSUFFICIENT_SUPPORT" else if (sum(valid) < max(20L, bootstrap / 2)) "INSUFFICIENT_SUPPORT" else if (!is.finite(lower) || !is.finite(upper) || upper <= lower) "DEGENERATE_INTERVAL" else if(length(species)<10L) "LIMITED_SPECIES" else "OK"
    data.frame(EvalWeighting = eval_weighting,
      Bin = paste0("[", breaks[[kk]], ",", breaks[[kk + 1L]], if (kk == length(breaks) - 1L) "]" else ")"),
      RecordsUsed = length(ii), SpeciesUsed = length(species), WeightSum = sum(wf$weight[ii]),
      MeanPredicted = point_pred, ObservedRate = point_obs,
      CalibrationLower = lower, CalibrationUpper = upper,
      BootstrapValid = sum(valid), IntervalStatus = status,
      stringsAsFactors = FALSE)
  })
  if (length(rows)) do.call(rbind, rows) else data.frame()
}
