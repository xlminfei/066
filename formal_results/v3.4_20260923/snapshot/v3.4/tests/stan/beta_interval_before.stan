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
data {
  int<lower=1> S;
  int<lower=0> K;
  int<lower=1> N;
  matrix[S, K] X;
  array[N] int<lower=0, upper=1> train;
  vector<lower=0>[N] train_weight;
  array[N] int<lower=1, upper=3> kind;
  array[N] int<lower=0> events;
  array[N] int<lower=1> total;
  vector<lower=0, upper=1>[N] exact_ratio;
  vector<lower=0, upper=1>[N] lower_ratio;
  vector<lower=0, upper=1>[N] upper_ratio;
  array[N] int<lower=1, upper=S> species_id;
  real<lower=0> prior_intercept_sd;
  real<lower=0> prior_beta_sd;
  real<lower=0> prior_rho_a;
  real<lower=0> prior_rho_b;
  real prior_log_phi_mean;
  real<lower=0> prior_log_phi_sd;
}
parameters {
  real alpha;
  vector[K] beta;
  real<lower=0, upper=1> rho;
  real log_phi_ratio;
  real log_phi_count;
}
transformed parameters {
  vector[S] eta = rep_vector(alpha, S) + X * beta;
  vector[S] m = inv_logit(eta);
}
model {
  alpha ~ normal(0, prior_intercept_sd);
  beta ~ normal(0, prior_beta_sd);
  rho ~ beta(prior_rho_a, prior_rho_b);
  log_phi_ratio ~ normal(prior_log_phi_mean, prior_log_phi_sd);
  log_phi_count ~ normal(prior_log_phi_mean, prior_log_phi_sd);
  for (i in 1:N) if (train[i] == 1 && train_weight[i] > 0)
    target += train_weight[i] * record_log_lik(kind[i], events[i], total[i], exact_ratio[i],
      lower_ratio[i], upper_ratio[i], m[species_id[i]], rho, log_phi_count, log_phi_ratio);
}
generated quantities {
  vector[N] log_lik;
  for (i in 1:N)
    log_lik[i] = record_log_lik(kind[i], events[i], total[i], exact_ratio[i],
      lower_ratio[i], upper_ratio[i], m[species_id[i]], rho, log_phi_count, log_phi_ratio);
}
