options(warn = 1)
root <- "/project/work/ratio_analysis_20260914"
helper <- file.path(root, "scripts", "stable_beta_interval.R")
if (file.exists(helper)) {
  source(helper)
} else {
  # Red-stage reproduction of the installed Stan Math 1 - inc_beta CCDF path.
  stable_beta_interval_logprob <- function(lo, hi, a, b) {
    x <- log(1 - pbeta(lo, a, b)); y <- log(1 - pbeta(hi, a, b))
    x + log(-expm1(y - x))
  }
}
check <- function(ok, why) if (!isTRUE(ok)) stop(why)
expected <- 24 * log(.2) + log1p(-(.1 / .2)^24)
got <- stable_beta_interval_logprob(.8, .9, 1, 24)
check(is.finite(got) && abs(got - expected) < 1e-12,
      "Positive beta tail interval must equal its finite analytic log probability")
check(abs(stable_beta_interval_logprob(.1, .2, 24, 1) - expected) < 1e-12, "Reflection identity")
check(abs(stable_beta_interval_logprob(.4, .5, 1, 1) - log(.1)) < 1e-12, "Uniform interval")
check(stable_beta_interval_logprob(0, 1, .01, 500) == 0, "Entire interval probability one")
check(abs(stable_beta_interval_logprob(.8, 1, 1, 24) - 24 * log(.2)) < 1e-12, "Upper endpoint tail")
check(abs(stable_beta_interval_logprob(0, .2, 24, 1) - 24 * log(.2)) < 1e-12, "Lower endpoint tail")
check(inherits(try(stable_beta_interval_logprob(.8, .7, 1, 2), silent = TRUE), "try-error"), "Reversed interval rejected")
check(inherits(try(stable_beta_interval_logprob(.2, .8, 0, 2), silent = TRUE), "try-error"), "Invalid shape rejected")
cat("STABLE_BETA_INTERVAL_ANALYTIC_TESTS_PASS\n")
