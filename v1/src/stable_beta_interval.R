# Numerically stable evaluation of the unchanged Beta interval probability.
# No clipping of observations, probabilities, log likelihoods, or posterior draws.
STABLE_BETA_INTERVAL_VERSION <- "stable_beta_logtails_20260916_v1"

stable_log_difference <- function(x, y) {
  stopifnot(length(x) == length(y))
  out <- rep(-Inf, length(x))
  good <- is.finite(x) & (y < x)
  out[good] <- x[good] + log(-expm1(y[good] - x[good]))
  out[is.na(x) | is.na(y) | y > x] <- NA_real_
  out
}

stable_beta_interval_logprob <- function(lo, hi, a, b) {
  n <- max(length(lo), length(hi), length(a), length(b))
  inputs <- list(lo, hi, a, b)
  if (!n || any(!lengths(inputs) %in% c(1L, n))) stop("Incompatible beta interval dimensions")
  lo <- rep_len(lo, n); hi <- rep_len(hi, n); a <- rep_len(a, n); b <- rep_len(b, n)
  if (any(!is.finite(c(lo, hi, a, b))) || any(a <= 0 | b <= 0) || any(lo < 0 | hi > 1 | lo >= hi))
    stop("Invalid beta shapes or interval bounds")
  result <- rep(NA_real_, n)
  full <- lo == 0 & hi == 1
  lower <- lo == 0 & !full
  upper <- hi == 1 & !full
  inner <- !full & !lower & !upper
  result[full] <- 0
  result[lower] <- stats::pbeta(hi[lower], a[lower], b[lower], log.p = TRUE)
  result[upper] <- stats::pbeta(lo[upper], a[upper], b[upper], lower.tail = FALSE, log.p = TRUE)
  if (any(inner)) {
    ix <- which(inner)
    c_hi <- stats::pbeta(hi[ix], a[ix], b[ix], log.p = TRUE)
    c_lo <- stats::pbeta(lo[ix], a[ix], b[ix], log.p = TRUE)
    s_lo <- stats::pbeta(lo[ix], a[ix], b[ix], lower.tail = FALSE, log.p = TRUE)
    s_hi <- stats::pbeta(hi[ix], a[ix], b[ix], lower.tail = FALSE, log.p = TRUE)
    lc <- stable_log_difference(c_hi, c_lo)
    ls <- stable_log_difference(s_lo, s_hi)
    # Subtract on the side with the smaller outer probability to limit cancellation.
    choose_cdf <- c_hi <= s_lo
    ans <- ifelse(choose_cdf, lc, ls)
    other <- ifelse(choose_cdf, ls, lc)
    use_other <- !is.finite(ans) & is.finite(other)
    ans[use_other] <- other[use_other]
    result[ix] <- ans
  }
  if (any(!is.finite(result)) || any(result > 1e-12))
    stop("Stable beta interval evaluation remains unresolved; no clipping or draw omission is allowed")
  result
}

stable_log_add <- function(x, y) {
  shift <- pmax(x, y)
  shift + log(exp(x - shift) + exp(y - shift))
}

stable_inflated_interval_loglik <- function(lo, hi, shape_a, shape_b, log_continuous_weight, log_endpoint) {
  probability <- stable_beta_interval_logprob(lo, hi, shape_a, shape_b)
  answer <- log_continuous_weight + probability
  if (hi == 1) answer <- stable_log_add(answer, log_endpoint)
  if (lo == 0 && hi == 1) answer[] <- 0
  if (any(!is.finite(answer)) || any(answer > 1e-12)) stop("Invalid one-inflated interval probability")
  answer
}
