functions {
  // Dual components track d/da and d/db solely to check convergence of the
  // continued fraction. The returned probability is still Stan-autodiff'd.
  vector beta_cf_product(vector x, vector y) {
    vector[3] z;
    z[1] = x[1] * y[1];
    z[2] = x[2] * y[1] + x[1] * y[2];
    z[3] = x[3] * y[1] + x[1] * y[3];
    return z;
  }
  vector beta_cf_inverse(vector x) {
    vector[3] z;
    // Lentz denominator protection is numerical scaling, never a probability
    // floor. Its value and derivatives are required to remain finite.
    real den = x[1];
    if (abs(den) < 1e-300) den = den < 0 ? -1e-300 : 1e-300;
    z[1] = 1 / den;
    z[2] = -(x[2] / den) / den;
    z[3] = -(x[3] / den) / den;
    return z;
  }
  real beta_log_cf_lower(real x, real a, real b) {
    real qab = a + b;
    real qap = a + 1;
    vector[3] one = [1, 0, 0]';
    vector[3] c = one;
    vector[3] den = [1 - qab * x / qap,
                     x * (b - 1) / square(qap), -x / qap]';
    vector[3] d = beta_cf_inverse(den);
    vector[3] h = d;
    int stable_steps = 0;
    // The fraction converges in this tail. Check the value AND its shape
    // derivatives: integer b can terminate the value before d/db converges.
    for (n in 1:10000) {
      real n2 = 2.0 * n;
      real den_even = (a + n2 - 1) * (a + n2);
      real v_even = n * (b - n) * x / den_even;
      vector[3] q_even = [v_even,
        -v_even * (1 / (a + n2 - 1) + 1 / (a + n2)),
        n * x / den_even]';
      real v_odd = -(a + n) * (qab + n) * x /
                    ((a + n2) * (a + n2 + 1));
      vector[3] q_odd = [v_odd,
        v_odd * (1 / (a + n) + 1 / (qab + n) -
                 1 / (a + n2) - 1 / (a + n2 + 1)),
        v_odd / (qab + n)]';
      vector[3] old_h = h;
      d = beta_cf_inverse(one + beta_cf_product(q_even, d));
      c = one + beta_cf_product(q_even, beta_cf_inverse(c));
      h = beta_cf_product(h, beta_cf_product(d, c));
      d = beta_cf_inverse(one + beta_cf_product(q_odd, d));
      c = one + beta_cf_product(q_odd, beta_cf_inverse(c));
      h = beta_cf_product(h, beta_cf_product(d, c));
      if (is_nan(h[1]) || is_inf(h[1]) || h[1] <= 0)
        reject("Beta continued fraction became nonfinite; a=", a, ", b=", b, ", x=", x);
      if (abs(h[1] - old_h[1]) <= 2e-14 * abs(h[1]) &&
          abs(h[2] / h[1] - old_h[2] / old_h[1]) <=
            2e-13 * (1 + abs(h[2] / h[1])) &&
          abs(h[3] / h[1] - old_h[3] / old_h[1]) <=
            2e-13 * (1 + abs(h[3] / h[1]))) stable_steps += 1;
      else stable_steps = 0;
      if (stable_steps >= 3)
        return a * log(x) + b * log1m(x) - lbeta(a, b) + log(h[1]) - log(a);
    }
    reject("Beta continued fraction failed to converge; a=", a, ", b=", b, ", x=", x);
    return not_a_number();
  }
  real beta_log_lower_stable(real x, real a, real b) {
    if (x <= 0) return negative_infinity();
    if (x >= 1) return 0;
    if (x <= (a + 1) / (a + b + 2)) return beta_log_cf_lower(x, a, b);
    return log1m_exp(beta_log_cf_lower(1 - x, b, a));
  }
  real beta_log_upper_stable(real x, real a, real b) {
    // Computing the small opposite tail directly avoids 1-CDF cancellation.
    if (x <= 0) return 0;
    if (x >= 1) return negative_infinity();
    return beta_log_lower_stable(1 - x, b, a);
  }
  real log_diff_exp_safe(real a, real b) {
    if (is_inf(a) && a < 0) return negative_infinity();
    if (is_inf(b) && b < 0) return a;
    if (b >= a) return negative_infinity();
    return a + log1m_exp(b - a);
  }
  real beta_log_interval_quadrature(real lo, real hi, real a, real b) {
    // Eight-point Gauss-Legendre, with panel doubling and convergence checks
    // for log mass and both shape derivatives. A logit change of variable
    // removes endpoint singularities; only interior intervals enter.
    vector[8] nodes = [-0.9602898564975363, -0.7966664774136267,
      -0.5255324099163290, -0.1834346424956498, 0.1834346424956498,
       0.5255324099163290, 0.7966664774136267, 0.9602898564975363]';
    vector[8] weights = [0.1012285362903763, 0.2223810344533745,
      0.3137066458778873, 0.3626837833783620, 0.3626837833783620,
      0.3137066458778873, 0.2223810344533745, 0.1012285362903763]';
    real zlo = logit(lo);
    // Stable logit(hi)-logit(lo), including very narrow intervals.
    real zwidth = log1p((hi - lo) / lo) - log1p(-(hi - lo) / (1 - lo));
    real previous = negative_infinity();
    real previous_da = 0;
    real previous_db = 0;
    int panels = 1;
    for (level in 1:10) {
      vector[8 * panels] terms;
      vector[8 * panels] log_x;
      vector[8 * panels] log_1mx;
      real half_width = zwidth / (2.0 * panels);
      real answer;
      real da;
      real db;
      for (p in 1:panels) {
        real center = zlo + (p - 0.5) * zwidth / panels;
        for (j in 1:8) {
          int k = (p - 1) * 8 + j;
          real z = center + half_width * nodes[j];
          log_x[k] = log_inv_logit(z);
          log_1mx[k] = log1m_inv_logit(z);
          // Includes dx/dz=x*(1-x), so exponents here are a and b.
          terms[k] = log(weights[j]) + a * log_x[k] + b * log_1mx[k] - lbeta(a, b);
        }
      }
      answer = log(half_width) + log_sum_exp(terms);
      da = dot_product(softmax(terms), log_x);
      db = dot_product(softmax(terms), log_1mx);
      if (level > 1 && abs(answer - previous) < 2e-11 &&
          abs(da - previous_da) < 2e-12 * (1 + abs(da)) &&
          abs(db - previous_db) < 2e-12 * (1 + abs(db))) return answer;
      previous = answer;
      previous_da = da;
      previous_db = db;
      panels *= 2;
    }
    reject("Beta interval quadrature failed to converge; a=", a, ", b=", b,
           ", lo=", lo, ", hi=", hi);
    return not_a_number();
  }
  real log_beta_interval(real lo, real hi, real a, real b) {
    real answer;
    real large_tail;
    real small_tail;
    if (!(a > 0) || !(b > 0) || !(lo >= 0) || !(hi <= 1) || !(lo < hi))
      reject("Invalid Beta interval or shape parameter");
    if (lo == 0 && hi == 1) return 0;
    if (lo == 0) return beta_log_lower_stable(hi, a, b);
    if (hi == 1) return beta_log_upper_stable(lo, a, b);
    // Even a correct tail loses relative precision when subtracting very
    // close CDF values. Integrate a narrow interior interval directly.
    if (hi - lo < 1e-5 * fmin(lo, 1 - hi))
      return beta_log_interval_quadrature(lo, hi, a, b);
    if ((lo + hi) / 2 <= (a + 1) / (a + b + 2)) {
      large_tail = beta_log_lower_stable(hi, a, b);
      small_tail = beta_log_lower_stable(lo, a, b);
    } else {
      large_tail = beta_log_upper_stable(lo, a, b);
      small_tail = beta_log_upper_stable(hi, a, b);
    }
    if (abs(large_tail - small_tail) < 1e-7)
      return beta_log_interval_quadrature(lo, hi, a, b);
    answer = log_diff_exp_safe(large_tail, small_tail);
    if (is_inf(answer) || is_nan(answer))
      return beta_log_interval_quadrature(lo, hi, a, b);
    return answer;
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
      log(continuous_mass) + beta_log_upper_stable(lo, a, b));
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
