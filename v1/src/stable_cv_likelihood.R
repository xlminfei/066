# Fixed-draw numerical evaluation only; original Stan objects are never mutated.
source("/project/work/ratio_analysis_20260914/scripts/stable_beta_interval.R")
stable_draw_matrix <- function(fit, variable) {
  a <- rstan::extract(fit, pars = variable, permuted = FALSE, inc_warmup = FALSE)
  matrix(a, nrow = dim(a)[1] * dim(a)[2], ncol = dim(a)[3])
}
stable_cv_loglik <- function(fit, source_rows, held, species) {
  original <- stable_draw_matrix(fit, "log_lik")
  stopifnot(ncol(original) == nrow(source_rows), !anyDuplicated(held))
  corrected <- original
  intervals <- which(source_rows$Type == "interval")
  if (length(intervals)) {
    shapes_a <- stable_draw_matrix(fit, "shape_a")
    shapes_b <- stable_draw_matrix(fit, "shape_b")
    continuous <- stable_draw_matrix(fit, "log_continuous_weight")
    endpoint <- stable_draw_matrix(fit, "log_endpoint")
    for (i in intervals) {
      s <- match(source_rows$Species[i], species)
      stopifnot(!is.na(s))
      corrected[, i] <- stable_inflated_interval_loglik(source_rows$Lower[i], source_rows$Upper[i],
        shapes_a[, s], shapes_b[, s], continuous[, s], endpoint[, s])
    }
  }
  if (any(!is.finite(corrected))) stop("Nonfinite values remain outside the numerically corrected interval probabilities")
  finite <- is.finite(original)
  training <- setdiff(seq_len(ncol(original)), held)
  difference <- corrected - original
  max_finite <- function(x) if (any(is.finite(x))) max(abs(x[is.finite(x)])) else 0
  log_mean <- function(x) matrixStats::logSumExp(x) - log(length(x))
  old_score <- log_mean(rowSums(original[, held, drop = FALSE]))
  new_score <- log_mean(rowSums(corrected[, held, drop = FALSE]))
  diagnostic <- data.frame(Draws = nrow(original), HeldoutRows = length(held),
    OriginalNonfiniteHeldout = sum(!finite[, held, drop = FALSE]),
    OriginalNonfiniteTraining = sum(!finite[, training, drop = FALSE]),
    CorrectedNonfinite = sum(!is.finite(corrected)),
    MaxAbsFiniteHeldoutLogDifference = max_finite(difference[, held, drop = FALSE]),
    MaxAbsFiniteTrainingLogDifference = max_finite(difference[, training, drop = FALSE]),
    MaxAbsTrainingJointLogDifference = max_finite(rowSums(difference[, training, drop = FALSE])),
    MaxAbsHeldoutEventProbabilityDifference = max(abs(exp(corrected[, intersect(held, intervals), drop = FALSE]) -
      exp(original[, intersect(held, intervals), drop = FALSE])), 0),
    OriginalELPDAllowingNegativeInfinity = old_score, StableELPD = new_score,
    ELPDDifference = new_score - old_score)
  list(log_lik = corrected[, held, drop = FALSE], diagnostic = diagnostic)
}
