functions {
  real log_diff_exp_safe(real a, real b) {
    if (is_inf(a) && a < 0) return negative_infinity();
    if (is_inf(b) && b < 0) return a;
    if (b >= a) return negative_infinity();
    return a + log1m_exp(b - a);
  }
  real log_beta_interval(real lo, real hi, real a, real b) {
    if (lo == 0 && hi == 1) return 0;
    if (hi <= 0.5) return log_diff_exp_safe(beta_lcdf(hi | a, b), beta_lcdf(lo | a, b));
    return log_diff_exp_safe(beta_lccdf(lo | a, b), beta_lccdf(hi | a, b));
  }
  real record_log_lik(int kind, int events, int total, real exact_ratio,
                     real lo, real hi, real m, real rho,
                     real log_phi_count, real log_phi_ratio) {
    real phi_count = exp(log_phi_count);
    real endpoint_mass = rho * m;
    real continuous_mass = 1 - endpoint_mass;
    real mu_internal = m * (1 - rho) / (1 - endpoint_mass);
    real a = exp(log_phi_ratio) * mu_internal;
    real b = exp(log_phi_ratio) * (1 - mu_internal);
    if (kind == 1) {
      return beta_binomial_lpmf(events | total, phi_count * m, phi_count * (1 - m));
    }
    if (kind == 2) {
      if (exact_ratio == 1) return log(endpoint_mass);
      return log(continuous_mass) + beta_lpdf(exact_ratio | a, b);
    }
    if (lo == 0 && hi == 1) return 0;
    if (hi == 1) return log_sum_exp(log(endpoint_mass),
      log(continuous_mass) + beta_lccdf(lo | a, b));
    return log(continuous_mass) + log_beta_interval(lo, hi, a, b);
  }
}
data { int<lower=1,upper=2> mode; real<lower=0,upper=1> lo; real<lower=0,upper=1> hi; }
parameters { vector[3] theta; }
model {
  if (mode == 1) target += log_beta_interval(lo, hi, theta[1], theta[2]);
  else target += record_log_lik(3, 0, 1, 0.5, lo, hi, inv_logit(theta[1]), inv_logit(theta[2]), 0, theta[3]);
}
