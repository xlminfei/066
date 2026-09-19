#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, warn = 1)

args <- commandArgs(trailingOnly = TRUE)
stage <- "preflight"
new_data_path <- NULL
external_out_path <- NULL
root <- Sys.getenv("V2_ROOT", unset = getwd())
if (length(args)) {
  for (i in seq_along(args)) {
    if (args[[i]] == "--stage" && i < length(args)) stage <- args[[i + 1L]]
    if (args[[i]] == "--root" && i < length(args)) root <- args[[i + 1L]]
    if (args[[i]] == "--new-data" && i < length(args)) new_data_path <- args[[i + 1L]]
    if (args[[i]] == "--out" && i < length(args)) external_out_path <- args[[i + 1L]]
  }
}
root <- normalizePath(root, winslash = "/", mustWork = TRUE)
input_dir <- file.path(root, "input")
if (!dir.exists(input_dir)) input_dir <- file.path(root, "data")
run_dir <- file.path(root, "runs", "formal_v2")
result_dir <- file.path(root, "results")
log_dir <- file.path(root, "logs")
review_dir <- file.path(root, "review")
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(run_dir, "fits"), recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)

needed <- c("brms", "rstan", "loo", "posterior", "pROC", "digest", "jsonlite")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Missing required packages: ", paste(missing, collapse = ", "))
if (stage %in% c("preflight", "smoke", "fit", "cv", "predict", "external", "all") &&
    !requireNamespace("crch", quietly = TRUE)) {
  stop("Scheme A requires the existing CRAN package crch; install it before formal fitting.")
}
suppressPackageStartupMessages({
  library(brms)
  library(rstan)
  library(posterior)
  library(loo)
  library(pROC)
  library(digest)
  library(jsonlite)
})
rstan_options(auto_write = TRUE)
options(mc.cores = min(4L, parallel::detectCores()))

VERSION <- "ratio_analysis_v2_joint_bb_vs_schemeA_site151_excluded_20260918"
MODELS <- c("Null", "Site315", "M1", "M2", "M3")
ALL_SITES <- c("Site3", "Site20", "Site117", "Site151", "Site196", "Site315")
MODEL_SITES <- c("Site3", "Site20", "Site117", "Site196", "Site315")
SEED <- 20260918L
CHAINS <- 4L
CORES <- 4L
ITER <- 4000L
WARMUP <- 2000L
ADAPT_DELTA <- 0.99
MAX_TREEDEPTH <- 12L
PRIORS <- list(intercept = 1.5, beta = 0.5, sigma = 1.0, rho_a = 1, rho_b = 1,
               log_phi_mean = log(10), log_phi_sd = 1)

sha <- function(path) digest::digest(file = path, algo = "sha256")
write_json <- function(x, path) {
  jsonlite::write_json(x, paste0(path, ".tmp"), auto_unbox = TRUE, pretty = TRUE, na = "null")
  file.rename(paste0(path, ".tmp"), path)
}
log_msg <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), ..., "\n")
}
log_diff <- function(a, b) {
  out <- rep(-Inf, length(a))
  ok <- is.finite(a) & is.finite(b) & b < a
  out[ok] <- a[ok] + log(-expm1(b[ok] - a[ok]))
  out[is.na(a) | is.na(b) | b > a] <- NA_real_
  out
}
log_mean_exp <- function(x) {
  z <- max(x)
  z + log(mean(exp(x - z)))
}
row_log_mean_exp <- function(x) {
  apply(x, 2L, log_mean_exp)
}
diagnose_fit <- function(fit, backend_fit = fit$fit) {
  sm <- posterior::summarise_draws(posterior::as_draws_array(fit),
                                   "rhat", "ess_bulk", "ess_tail")
  sp <- rstan::get_sampler_params(backend_fit, inc_warmup = FALSE)
  div <- sum(vapply(sp, function(z) sum(z[, "divergent__"]), numeric(1)))
  depth <- sum(vapply(sp, function(z) sum(z[, "treedepth__"] >= MAX_TREEDEPTH), numeric(1)))
  eb <- vapply(sp, function(z) mean(diff(z[, "energy__"])^2) / stats::var(z[, "energy__"]), numeric(1))
  ok <- all(is.finite(unlist(sm[, c("rhat", "ess_bulk", "ess_tail")]))) &&
    max(sm$rhat, na.rm = TRUE) < 1.01 &&
    min(sm$ess_bulk, na.rm = TRUE) >= 400 &&
    min(sm$ess_tail, na.rm = TRUE) >= 400 &&
    div == 0L && depth == 0L && min(eb) > 0.3
  data.frame(Status = if (ok) "PASS" else "NEEDS_REVIEW",
             MaxRhat = max(sm$rhat, na.rm = TRUE),
             MinBulkESS = min(sm$ess_bulk, na.rm = TRUE),
             MinTailESS = min(sm$ess_tail, na.rm = TRUE),
             Divergences = div, TreeDepthHits = depth,
             MinEBFMI = min(eb), stringsAsFactors = FALSE)
}

encode_raw <- function(x, site, group, freqs = NULL) {
  x <- toupper(trimws(as.character(x)))
  x[is.na(x) | x == "" | x %in% c("NA", "X", "-", "MISSING", "INDEL")] <- "MISSING"
  if (group %in% c("M1", "Site315")) {
    if (site == "Site315") {
      return(ifelse(x == "MISSING", "MISSING",
                    ifelse(x %in% c("K", "T"), "K_or_T", "other")))
    }
    ref <- c(Site3 = "C", Site20 = "K", Site117 = "K",
             Site151 = "C", Site196 = "C")[[site]]
    return(ifelse(x == "MISSING", "MISSING",
                  ifelse(x == ref, ref, "other")))
  }
  if (group == "M2") {
    return(ifelse(x == "MISSING", "MISSING",
                  ifelse(x %in% c("C", "K", "S", "T"), "CKST", "other")))
  }
  if (group == "M3") {
    keep <- names(freqs)[freqs >= 4L]
    return(ifelse(x == "MISSING", "MISSING",
                  ifelse(x %in% keep, x, "OTHER")))
  }
  stop("Unknown encoding group")
}

fixed_levels <- function(group, site, panel_values) {
  if (group %in% c("M1", "Site315")) {
    if (site == "Site315") return(c("K_or_T", "other", "MISSING"))
    ref <- c(Site3 = "C", Site20 = "K",
             Site117 = "K", Site151 = "C",
             Site196 = "C")[[site]]
    return(c(ref, "other", "MISSING"))
  }
  if (group == "M2") return(c("CKST", "other", "MISSING"))
  if (group == "M3") {
    lev <- sort(unique(c(panel_values, "OTHER", "MISSING")))
    usable <- panel_values[panel_values != "MISSING"]
    counts <- sort(table(usable), decreasing = TRUE)
    ref <- if (length(counts)) names(counts)[[1L]] else lev[[1L]]
    lev <- c(ref, setdiff(lev, c(ref, "MISSING")), intersect("MISSING", lev))
    return(lev)
  }
  character()
}

make_blueprint <- function(panel, response_species, group, sites) {
  cols <- character()
  refs <- list()
  levels <- list()
  seen <- list()
  X <- matrix(0, nrow(panel), 0L)
  if (group != "Null") {
    vars <- if (group == "Site315") "Site315" else sites
    enc_group <- if (group == "Site315") "M1" else group
    encoded <- lapply(vars, function(s) encode_raw(panel[[s]], s, enc_group,
                                                    if (enc_group == "M3") {
                                                      z <- toupper(trimws(as.character(panel[[s]])))
                                                      z[z %in% c("", "NA", "X", "-", "MISSING", "INDEL") | is.na(z)] <- "MISSING"
                                                      table(z[z != "MISSING"])
                                                    } else NULL))
    names(encoded) <- vars
    response_rows <- match(response_species, panel$Species)
    for (j in seq_along(vars)) {
      site <- vars[[j]]
      lev <- fixed_levels(group, site, encoded[[j]])
      ref <- lev[[1L]]
      refs[[site]] <- ref
      levels[[site]] <- lev
      seen[[site]] <- sort(unique(encoded[[j]][response_rows]))
      for (lv in lev[-1L]) {
        X <- cbind(X, as.integer(encoded[[j]] == lv))
        cols <- c(cols, paste(group, site, lv, sep = "_"))
      }
    }
  }
  colnames(X) <- cols
  list(X = X, columns = cols, group = group, references = refs,
       levels = levels, seen = seen, response_species = response_species,
       rank = qr(cbind(Intercept = 1, X[match(response_species, panel$Species), , drop = FALSE]))$rank,
       parameter_columns = ncol(X) + 1L)
}

prepare <- function() {
  obs <- read.csv(file.path(input_dir, "observations.csv"), stringsAsFactors = FALSE,
                  check.names = FALSE)
  sites <- read.csv(file.path(input_dir, "sites.csv"), stringsAsFactors = FALSE,
                    check.names = FALSE)
  stopifnot(nrow(obs) == 153L, nrow(sites) == 365L,
            length(unique(obs$Species)) == 51L,
            identical(sha(file.path(input_dir, "observations.csv")),
                      "3c886f7f2c11012463296b350a931543542b4e1c0d128ad3c408fda9ae824d79"),
            identical(sha(file.path(input_dir, "sites.csv")),
                      "0a99692b060f13d1faaa870d06ea7dca9a4f16bc289636bcc88f5d105ebdacb5"))
  obs$High <- NA_integer_
  count_i <- obs$Type == "count"
  exact_i <- obs$Type == "exact"
  int_i <- obs$Type == "interval"
  obs$High[count_i] <- as.integer(2 * obs$Events[count_i] >= obs$Total[count_i])
  obs$High[exact_i] <- as.integer(obs$Exact[exact_i] >= .5)
  obs$High[int_i & obs$Upper <= .5] <- 0L
  obs$High[int_i & obs$Lower >= .5] <- 1L
   site_cols <- ALL_SITES
   model_sites <- MODEL_SITES
  stopifnot(all(site_cols %in% names(sites)), !anyDuplicated(sites$Species))
  binary <- aggregate(cbind(HighCount = as.integer(!is.na(obs$High) & obs$High == 1L),
                             LowCount = as.integer(!is.na(obs$High) & obs$High == 0L),
                             UnclassifiedCount = as.integer(is.na(obs$High))),
                   by = list(Species = obs$Species), FUN = sum)
  binary_counts <- data.frame(Species = sites$Species, HighCount = 0L, LowCount = 0L,
                              UnclassifiedCount = 0L, stringsAsFactors = FALSE)
  binary_counts$HighCount <- binary$HighCount[match(binary_counts$Species, binary$Species)]
  binary_counts$LowCount <- binary$LowCount[match(binary_counts$Species, binary$Species)]
  binary_counts$UnclassifiedCount <- binary$UnclassifiedCount[match(binary_counts$Species, binary$Species)]
  binary_counts[is.na(binary_counts)] <- 0L
  binary_counts$Trials <- binary_counts$HighCount + binary_counts$LowCount
  response_binary <- binary_counts$Species[binary_counts$Trials > 0L]
  response_joint <- unique(obs$Species)
  freqs <- setNames(lapply(site_cols, function(s) {
    z <- toupper(trimws(as.character(sites[[s]])))
    z[z %in% c("", "NA", "X", "-", "MISSING", "INDEL") | is.na(z)] <- "MISSING"
    table(z[z != "MISSING"])
  }), site_cols)
  panel <- sites
  for (s in site_cols) {
    panel[[paste0("M1_", s)]] <- encode_raw(panel[[s]], s, "M1")
    panel[[paste0("M2_", s)]] <- encode_raw(panel[[s]], s, "M2")
    panel[[paste0("M3_", s)]] <- encode_raw(panel[[s]], s, "M3", freqs[[s]])
  }
  blueprints <- list()
  for (group in MODELS) {
    blueprints[[paste0("binary_", group)]] <- make_blueprint(panel, response_binary, group, model_sites)
    blueprints[[paste0("joint_", group)]] <- make_blueprint(panel, response_joint, group, model_sites)
  }
  state <- list(version = VERSION, obs = obs, sites = sites, panel = panel,
                binary_counts = binary_counts, site_cols = site_cols, model_sites = model_sites,
                freqs = freqs,
                binary_species = response_binary, joint_species = response_joint,
                blueprints = blueprints, hashes = list(observations = sha(file.path(input_dir, "observations.csv")),
                                                       sites = sha(file.path(input_dir, "sites.csv")),
                                                       created_at = as.character(Sys.time())))
  saveRDS(state, file.path(run_dir, "prepared_v2.rds"))
  write.csv(binary_counts, file.path(result_dir, "binary_counts.csv"), row.names = FALSE)
  write.csv(panel, file.path(result_dir, "panel_encoded.csv"), row.names = FALSE)
  write_json(list(status = "PASS", version = VERSION, records = nrow(obs),
                  panel_species = nrow(sites), binary_species = length(response_binary),
                  joint_species = length(response_joint), model_sites = model_sites,
                  excluded_from_predictors = "Site151",
                  counts = as.list(table(obs$Type)),
                  input_hashes = state$hashes),
             file.path(review_dir, "prepared_v2.json"))
  state
}

load_state <- function() {
  p <- file.path(run_dir, "prepared_v2.rds")
  if (!file.exists(p)) stop("prepared_v2.rds missing; run --stage prepare first")
  st <- readRDS(p)
  stopifnot(identical(st$version, VERSION))
  st
}

formula_from_X <- function(y, cols, extra = character()) {
  rhs <- c("1", cols, extra)
  stats::as.formula(paste(y, "~", paste(rhs, collapse = " + ")))
}

fit_binomial_model <- function(st, model, train_species = st$binary_species,
                               tag = "full", iter = ITER, warmup = WARMUP,
                               chains = CHAINS, cores = CORES) {
  bp <- st$blueprints[[paste0("binary_", model)]]
  out_path <- file.path(run_dir, "fits", paste0("binary_", model, "_", tag, ".rds"))
  if (file.exists(out_path)) {
    old <- readRDS(out_path)
    if (identical(old$version, VERSION) && identical(old$route, "binary") &&
        identical(old$model, model) && setequal(old$train_species, train_species))
      return(old)
  }
  rows <- st$binary_counts[st$binary_counts$Species %in% train_species &
                           st$binary_counts$Trials > 0L, , drop = FALSE]
  idx <- match(rows$Species, st$panel$Species)
  dat <- cbind(rows, as.data.frame(bp$X[idx, , drop = FALSE]))
  form <- formula_from_X("HighCount | trials(Trials)", bp$columns)
  pri <- c(brms::set_prior(sprintf("normal(0,%g)", PRIORS$intercept),
                            class = "b", coef = "Intercept"))
  if (length(bp$columns)) pri <- c(pri, brms::set_prior(sprintf("normal(0,%g)", PRIORS$beta),
                                                        class = "b"))
  fit <- brms::brm(formula = brms::bf(form, center = FALSE), data = dat, family = stats::binomial(),
                   prior = pri, drop_unused_levels = FALSE,
                   backend = "rstan", save_pars = brms::save_pars(all = TRUE),
                   seed = SEED, chains = chains, cores = cores, iter = iter,
                   warmup = warmup,
                   control = list(adapt_delta = ADAPT_DELTA,
                                  max_treedepth = MAX_TREEDEPTH),
                   silent = 2, refresh = 0)
  dg <- diagnose_fit(fit)
  bundle <- list(route = "binary", model = model, tag = tag, fit = fit,
                 blueprint = bp, data = dat, train_species = train_species,
                 diagnostics = dg, version = VERSION,
                 created_at = as.character(Sys.time()))
  saveRDS(bundle, out_path)
  bundle
}

joint_code <- r"---(
functions {
  real ldiff(real a, real b) {
    return a + log(-expm1(b - a));
  }
}
data {
  int<lower=1> S;
  int<lower=0> K;
  int<lower=1> N;
  int<lower=0> N_count;
  int<lower=0> N_exact;
  int<lower=0> N_interval;
  matrix[S,K] X;
  array[N] int<lower=0,upper=1> train;
  array[N_count] int<lower=1,upper=S> species_count;
  array[N_count] int<lower=1,upper=N> row_count;
  array[N_count] int<lower=0> events;
  array[N_count] int<lower=1> total;
  array[N_exact] int<lower=1,upper=S> species_exact;
  array[N_exact] int<lower=1,upper=N> row_exact;
  vector<lower=0,upper=1>[N_exact] exact_ratio;
  array[N_interval] int<lower=1,upper=S> species_interval;
  array[N_interval] int<lower=1,upper=N> row_interval;
  vector<lower=0,upper=1>[N_interval] lower_ratio;
  vector<lower=0,upper=1>[N_interval] upper_ratio;
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
  real<lower=0,upper=1> rho;
  real log_phi_ratio;
  real log_phi_count;
}
transformed parameters {
  vector[S] eta = rep_vector(alpha,S) + X*beta;
  vector[S] m = inv_logit(eta);
  vector[S] endpoint_mass = rho*m;
  vector[S] w_cont = 1 - endpoint_mass;
  vector[S] mu_int;
  vector[S] shape_a;
  vector[S] shape_b;
  for (s in 1:S) {
    mu_int[s] = m[s]*(1-rho)/(1-rho*m[s]);
    shape_a[s] = exp(log_phi_ratio)*mu_int[s];
    shape_b[s] = exp(log_phi_ratio)*(1-mu_int[s]);
  }
}
model {
  alpha ~ normal(0,prior_intercept_sd);
  beta ~ normal(0,prior_beta_sd);
  rho ~ beta(prior_rho_a,prior_rho_b);
  log_phi_ratio ~ normal(prior_log_phi_mean,prior_log_phi_sd);
  log_phi_count ~ normal(prior_log_phi_mean,prior_log_phi_sd);
  for (i in 1:N_count) if (train[row_count[i]] == 1) {
    int s = species_count[i];
    target += beta_binomial_lpmf(events[i] | total[i],
      exp(log_phi_count)*m[s], exp(log_phi_count)*(1-m[s]));
  }
  for (i in 1:N_exact) if (train[row_exact[i]] == 1) {
    int s = species_exact[i];
    if (exact_ratio[i] == 1) target += log(endpoint_mass[s]);
    else target += log(w_cont[s]) + beta_lpdf(exact_ratio[i] | shape_a[s],shape_b[s]);
  }
  for (i in 1:N_interval) if (train[row_interval[i]] == 1) {
    int s = species_interval[i];
    real lo = lower_ratio[i];
    real hi = upper_ratio[i];
    if (lo == 0 && hi == 1) target += 0;
    else if (hi == 1) target += log_sum_exp(log(endpoint_mass[s]),
      log(w_cont[s]) + beta_lccdf(lo | shape_a[s],shape_b[s]));
    else if (lo == 0) target += log(w_cont[s]) + beta_lcdf(hi | shape_a[s],shape_b[s]);
    else if (lo >= mu_int[s]) target += log(w_cont[s]) + ldiff(
      beta_lccdf(lo | shape_a[s],shape_b[s]),
      beta_lccdf(hi | shape_a[s],shape_b[s]));
    else target += log(w_cont[s]) + ldiff(
      beta_lcdf(hi | shape_a[s],shape_b[s]),
      beta_lcdf(lo | shape_a[s],shape_b[s]));
  }
}
generated quantities {
  vector[N] log_lik;
  for (i in 1:N_count) {
    int s = species_count[i];
    log_lik[row_count[i]] = beta_binomial_lpmf(events[i] | total[i],
      exp(log_phi_count)*m[s], exp(log_phi_count)*(1-m[s]));
  }
  for (i in 1:N_exact) {
    int s = species_exact[i];
    if (exact_ratio[i] == 1) log_lik[row_exact[i]] = log(endpoint_mass[s]);
    else log_lik[row_exact[i]] = log(w_cont[s]) +
      beta_lpdf(exact_ratio[i] | shape_a[s],shape_b[s]);
  }
  for (i in 1:N_interval) {
    int s = species_interval[i];
    real lo = lower_ratio[i];
    real hi = upper_ratio[i];
    if (lo == 0 && hi == 1) log_lik[row_interval[i]] = 0;
    else if (hi == 1) log_lik[row_interval[i]] = log_sum_exp(log(endpoint_mass[s]),
      log(w_cont[s]) + beta_lccdf(lo | shape_a[s],shape_b[s]));
    else if (lo == 0) log_lik[row_interval[i]] = log(w_cont[s]) + beta_lcdf(hi | shape_a[s],shape_b[s]);
    else if (lo >= mu_int[s]) log_lik[row_interval[i]] = log(w_cont[s]) + ldiff(
      beta_lccdf(lo | shape_a[s],shape_b[s]),
      beta_lccdf(hi | shape_a[s],shape_b[s]));
    else log_lik[row_interval[i]] = log(w_cont[s]) + ldiff(
      beta_lcdf(hi | shape_a[s],shape_b[s]),
      beta_lcdf(lo | shape_a[s],shape_b[s]));
  }
}
)---"

joint_compiled <- NULL
get_joint_compiled <- function() {
  if (is.null(joint_compiled)) {
    joint_compiled <<- rstan::stan_model(model_code = joint_code,
                                          model_name = "ratio_v2_joint_bb")
  }
  joint_compiled
}

joint_data <- function(st, model, train_species) {
  bp <- st$blueprints[[paste0("joint_", model)]]
  obs <- st$obs
  sid <- match(obs$Species, st$panel$Species)
  tr <- as.integer(obs$Species %in% train_species)
  ic <- which(obs$Type == "count")
  ie <- which(obs$Type == "exact")
  ii <- which(obs$Type == "interval")
  list(S = nrow(st$panel), K = ncol(bp$X), N = nrow(obs),
       N_count = length(ic), N_exact = length(ie), N_interval = length(ii),
       X = bp$X, train = tr,
       species_count = sid[ic], row_count = ic,
       events = as.integer(obs$Events[ic]), total = as.integer(obs$Total[ic]),
       species_exact = sid[ie], row_exact = ie,
       exact_ratio = as.numeric(obs$Exact[ie]),
       species_interval = sid[ii], row_interval = ii,
       lower_ratio = as.numeric(obs$Lower[ii]), upper_ratio = as.numeric(obs$Upper[ii]),
       prior_intercept_sd = PRIORS$intercept, prior_beta_sd = PRIORS$beta,
       prior_rho_a = PRIORS$rho_a, prior_rho_b = PRIORS$rho_b,
       prior_log_phi_mean = PRIORS$log_phi_mean,
       prior_log_phi_sd = PRIORS$log_phi_sd)
}
fit_joint_model <- function(st, model, train_species = st$joint_species,
                            tag = "full", iter = ITER, warmup = WARMUP,
                            chains = CHAINS, cores = CORES) {
  out_path <- file.path(run_dir, "fits", paste0("joint_", model, "_", tag, ".rds"))
  if (file.exists(out_path)) {
    old <- readRDS(out_path)
    if (identical(old$version, VERSION) && identical(old$route, "joint_bb") &&
        identical(old$model, model) && setequal(old$train_species, train_species) &&
        identical(old$code_hash, sha_code(joint_code)))
      return(old)
  }
  dat <- joint_data(st, model, train_species)
  fit <- rstan::sampling(get_joint_compiled(), data = dat, seed = SEED,
                         chains = chains, cores = cores, iter = iter,
                         warmup = warmup,
                         control = list(adapt_delta = ADAPT_DELTA,
                                        max_treedepth = MAX_TREEDEPTH))
  dg <- diagnose_fit(fit, fit)
  b <- st$blueprints[[paste0("joint_", model)]]
  bundle <- list(route = "joint_bb", model = model, tag = tag, fit = fit,
                 blueprint = b, data = dat, train_species = train_species,
                 diagnostics = dg, version = VERSION,
                 code_hash = sha_code(joint_code),
                 created_at = as.character(Sys.time()))
  saveRDS(bundle, out_path)
  bundle
}
sha_code <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)

scheme_data <- function(st, model, rows = seq_len(nrow(st$obs))) {
  bp <- st$blueprints[[paste0("joint_", model)]]
  obs <- st$obs[rows, , drop = FALSE]
  sid <- match(obs$Species, st$panel$Species)
  y <- numeric(nrow(obs)); y2 <- y; cens <- rep("none", nrow(obs))
  for (i in seq_len(nrow(obs))) {
    r <- obs[i, ]
    if (r$Type == "count") {
      y[i] <- as.numeric(r$Events) / as.numeric(r$Total)
      y2[i] <- y[i]
    } else if (r$Type == "exact") {
      y[i] <- as.numeric(r$Exact); y2[i] <- y[i]
    } else {
      y[i] <- as.numeric(r$Lower); y2[i] <- as.numeric(r$Upper)
      cens[i] <- "interval"
    }
    if (y[i] <= 0) { y[i] <- 0; y2[i] <- 0; cens[i] <- "left" }
    if (y[i] >= 1) { y[i] <- 1; y2[i] <- 1; cens[i] <- "right" }
    if (cens[i] == "interval" && y[i] == 0 && y2[i] < 1) cens[i] <- "left"
    if (cens[i] == "interval" && y[i] > 0 && y2[i] == 1) { cens[i] <- "right"; y2[i] <- y[i] }
  }
  out <- data.frame(y = y, y2 = y2, cens = cens,
                    Species = obs$Species, obs_row = rows,
                    stringsAsFactors = FALSE)
  if (ncol(bp$X)) out <- cbind(out, as.data.frame(bp$X[sid, , drop = FALSE]))
  out
}

fit_schemeA_model <- function(st, model, train_rows = seq_len(nrow(st$obs)),
                              tag = "full", iter = ITER, warmup = WARMUP,
                              chains = CHAINS, cores = CORES) {
  out_path <- file.path(run_dir, "fits", paste0("schemeA_", model, "_", tag, ".rds"))
  if (file.exists(out_path)) {
    old <- readRDS(out_path)
    if (identical(old$version, VERSION) && identical(old$route, "schemeA_tobit") &&
        identical(old$model, model) && identical(old$train_rows, train_rows))
      return(old)
  }
  bp <- st$blueprints[[paste0("joint_", model)]]
  dat <- scheme_data(st, model, train_rows)
  cols <- bp$columns
  rhs <- if (length(cols)) paste(c("1", cols), collapse = " + ") else "1"
  form <- stats::as.formula(paste("y | cens(cens, y2) ~", rhs))
  pri <- brms::set_prior(sprintf("normal(0,%g)", PRIORS$intercept),
                         class = "b", coef = "Intercept")
  if (length(cols)) pri <- c(pri, brms::set_prior(sprintf("normal(0,%g)", PRIORS$beta),
                                                    class = "b"))
  pri <- c(pri, brms::set_prior(sprintf("exponential(%g)", PRIORS$sigma),
                                 class = "sigma"))
  fit <- brms::brm(formula = brms::bf(form, center = FALSE),
                   data = dat, family = stats::gaussian(), prior = pri,
                   backend = "rstan", save_pars = brms::save_pars(all = TRUE),
                   seed = SEED, chains = chains, cores = cores, iter = iter,
                   warmup = warmup,
                   control = list(adapt_delta = ADAPT_DELTA,
                                  max_treedepth = MAX_TREEDEPTH),
                   silent = 2, refresh = 0)
  dg <- diagnose_fit(fit)
  bundle <- list(route = "schemeA_tobit", model = model, tag = tag, fit = fit,
                 blueprint = bp, data = dat, train_rows = train_rows,
                 diagnostics = dg, version = VERSION,
                 created_at = as.character(Sys.time()))
  saveRDS(bundle, out_path)
  bundle
}

draw_scheme_params <- function(fit, newdata) {
  if (!all(c("y", "y2", "cens") %in% names(newdata))) {
    newdata <- cbind(data.frame(y = 0, y2 = 0, cens = "none"), newdata)
  }
  mu <- brms::posterior_linpred(fit, newdata = newdata, transform = FALSE,
                                re_formula = NA)
  # Keep sigma in the same posterior draw order as posterior_linpred().
  # rstan::extract(permuted=TRUE) can reorder draws relative to brms predictions.
  sig <- as.numeric(posterior::as_draws_matrix(fit$fit)[, "sigma"])
  list(mu = mu, sigma = sig)
}
scheme_expected <- function(mu, sigma) {
  if (!requireNamespace("crch", quietly = TRUE))
    stop("Scheme A expected-value calculation requires crch")
  out <- matrix(NA_real_, nrow(mu), ncol(mu))
  for (d in seq_len(nrow(mu))) {
    out[d, ] <- as.numeric(crch:::ecnorm(mean = mu[d, ], sd = sigma[d],
                                         left = 0, right = 1))
  }
  out
}
scheme_predictive <- function(mu, sigma) {
  out <- matrix(NA_real_, nrow(mu), ncol(mu))
  for (d in seq_len(nrow(mu))) {
    out[d, ] <- pmin(pmax(stats::rnorm(ncol(mu), mu[d, ], sigma[d]), 0), 1)
  }
  out
}
joint_expected <- function(fit) {
  ex <- rstan::extract(fit, pars = "m", permuted = TRUE)$m
  matrix(ex, nrow = nrow(ex), ncol = ncol(ex))
}
joint_expected_from_X <- function(fit, X) {
  ex <- rstan::extract(fit, pars = c("alpha", "beta"), permuted = TRUE)
  alpha <- as.numeric(ex$alpha)
  beta <- ex$beta
  if (is.null(beta)) beta <- matrix(0, nrow = length(alpha), ncol = 0L)
  out <- matrix(NA_real_, length(alpha), nrow(X))
  for (d in seq_along(alpha)) {
    eta <- rep(alpha[[d]], nrow(X))
    if (ncol(X)) eta <- eta + as.numeric(X %*% as.numeric(beta[d, ]))
    out[d, ] <- stats::plogis(eta)
  }
  out
}
joint_predictive_exact_from_m <- function(fit, m) {
  ex <- rstan::extract(fit, pars = c("rho", "log_phi_ratio"), permuted = TRUE)
  rho <- as.numeric(ex$rho)
  phi <- exp(as.numeric(ex$log_phi_ratio))
  out <- matrix(NA_real_, nrow(m), ncol(m))
  for (d in seq_len(nrow(m))) {
    mu_int <- m[d, ] * (1 - rho[d]) / (1 - rho[d] * m[d, ])
    a <- phi[d] * mu_int
    b <- phi[d] * (1 - mu_int)
    hit <- stats::runif(ncol(m)) < rho[d] * m[d, ]
    out[d, ] <- ifelse(hit, 1, stats::rbeta(ncol(m), a, b))
  }
  out
}

binary_predictions_X <- function(bundle, X) {
  bp <- bundle$blueprint
  nd <- cbind(data.frame(Trials = 1L), as.data.frame(X))
  names(nd) <- c("Trials", bp$columns)
  ep <- brms::posterior_epred(bundle$fit, newdata = nd, re_formula = NA)
  list(point = colMeans(ep),
       lower = apply(ep, 2L, quantile, probs = .025),
        upper = apply(ep, 2L, quantile, probs = .975),
        draws = ep)
}
binary_predictions <- function(bundle, st, model, species = st$panel$Species) {
  bp <- bundle$blueprint
  idx <- match(species, st$panel$Species)
  binary_predictions_X(bundle, bp$X[idx, , drop = FALSE])
}
quant_predictions_X <- function(bundle, X, scheme = FALSE) {
  bp <- bundle$blueprint
  nd <- as.data.frame(X)
  names(nd) <- bp$columns
  if (scheme) {
    nd <- cbind(data.frame(y = 0, y2 = 0, cens = "none"), nd)
    dr <- draw_scheme_params(bundle$fit, nd)
    ex <- scheme_expected(dr$mu, dr$sigma)
    pi <- scheme_predictive(dr$mu, dr$sigma)
  } else {
    ex <- joint_expected_from_X(bundle$fit, X)
    pi <- joint_predictive_exact_from_m(bundle$fit, ex)
  }
  list(point = colMeans(ex),
       lower = apply(ex, 2L, quantile, probs = .025),
       upper = apply(ex, 2L, quantile, probs = .975),
       pi_lower = apply(pi, 2L, quantile, probs = .025),
       pi_upper = apply(pi, 2L, quantile, probs = .975),
        expected_draws = ex, predictive_draws = pi)
}

quant_predictions <- function(bundle, st, scheme = FALSE,
                               species = st$panel$Species) {
  bp <- bundle$blueprint
  idx <- match(species, st$panel$Species)
  quant_predictions_X(bundle, bp$X[idx, , drop = FALSE], scheme = scheme)
}

encoded_panel_for_model <- function(st, model, panel) {
  group <- model
  vars <- if (group == "Site315") "Site315" else if (group == "Null") character() else st$model_sites
  enc_group <- if (group == "Site315") "M1" else group
  encoded <- lapply(vars, function(s) {
    encode_raw(panel[[s]], s, enc_group,
               if (enc_group == "M3") st$freqs[[s]] else NULL)
  })
  names(encoded) <- vars
  encoded
}

design_matrix_for_panel <- function(st, model, outcome, panel) {
  bp <- st$blueprints[[paste0(outcome, "_", model)]]
  encoded <- encoded_panel_for_model(st, model, panel)
  X <- matrix(0, nrow(panel), 0L)
  if (length(encoded)) {
    for (site in names(encoded)) {
      lev <- bp$levels[[site]]
      for (lv in lev[-1L]) X <- cbind(X, as.integer(encoded[[site]] == lv))
    }
  }
  colnames(X) <- bp$columns
  stopifnot(ncol(X) == length(bp$columns), all(is.finite(X)))
  X
}

prediction_status <- function(st, model, outcome = c("binary", "joint"),
                              panel = st$panel) {
  outcome <- match.arg(outcome)
  bp <- st$blueprints[[paste0(outcome, "_", model)]]
  encoded <- encoded_panel_for_model(st, model, panel)
  if (!length(encoded)) return(rep("supported", nrow(panel)))
  status <- rep("supported", nrow(panel))
  for (j in seq_along(encoded)) {
    site <- names(encoded)[[j]]
    status[!encoded[[j]] %in% bp$seen[[site]]] <- "unseen_category_extrapolation"
    status[encoded[[j]] == "MISSING"] <- "missing_input_extrapolation"
  }
  status
}

make_folds <- function(species, k, seed) {
  set.seed(seed)
  data.frame(Species = species,
             Fold = sample(rep(seq_len(k), length.out = length(species))),
             stringsAsFactors = FALSE)
}
fold_gate_binary <- function(st, folds) {
  z <- st$binary_counts
  vapply(seq_len(max(folds$Fold)), function(k) {
    ss <- folds$Species[folds$Fold == k]
    zz <- z[z$Species %in% ss & z$Trials > 0, ]
    sum(zz$HighCount) > 0 && sum(zz$LowCount) > 0
  }, logical(1))
}
make_stratified_tenfold <- function(st, seed = SEED + 10L) {
  b <- st$binary_counts
  mixed <- b$Species[b$Trials > 0 & b$HighCount > 0 & b$LowCount > 0]
  hi_only <- b$Species[b$Trials > 0 & b$HighCount > 0 & b$LowCount == 0]
  lo_only <- b$Species[b$Trials > 0 & b$LowCount > 0 & b$HighCount == 0]
  set.seed(seed)
  f <- integer(nrow(b))
  f[match(sample(mixed), b$Species)] <- rep(seq_len(10L), length.out = length(mixed))
  f[match(sample(hi_only), b$Species)] <- rep(seq_len(10L), length.out = length(hi_only))
  f[match(sample(lo_only), b$Species)] <- rep(seq_len(10L), length.out = length(lo_only))
  data.frame(Species = b$Species[b$Trials > 0], Fold = f[b$Trials > 0],
             stringsAsFactors = FALSE)
}

loglik_scheme <- function(mu, sigma, dat) {
  out <- matrix(NA_real_, nrow(mu), nrow(dat))
  for (j in seq_len(nrow(dat))) {
    if (dat$cens[j] == "none") out[, j] <- dnorm(dat$y[j], mu[, j], sigma, log = TRUE)
    else if (dat$cens[j] == "left") out[, j] <- pnorm(dat$y[j], mu[, j], sigma, log.p = TRUE)
    else if (dat$cens[j] == "right") out[, j] <- pnorm(dat$y[j], mu[, j], sigma,
                                                        lower.tail = FALSE, log.p = TRUE)
    else {
      a <- pnorm(dat$y2[j], mu[, j], sigma, log.p = TRUE)
      b <- pnorm(dat$y[j], mu[, j], sigma, log.p = TRUE)
      out[, j] <- log_diff(a, b)
    }
  }
  out
}
score_binary_records <- function(bundle, st, species) {
  rows <- st$binary_counts[st$binary_counts$Species %in% species &
                           st$binary_counts$Trials > 0L, , drop = FALSE]
  bp <- bundle$blueprint
  idx <- match(rows$Species, st$panel$Species)
  nd <- cbind(data.frame(Trials = 1L), as.data.frame(bp$X[idx, , drop = FALSE]))
  names(nd) <- c("Trials", bp$columns)
  p <- brms::posterior_epred(bundle$fit, newdata = nd, re_formula = NA)
  prob <- colMeans(p)
  oo <- st$obs[st$obs$Species %in% species & !is.na(st$obs$High), , drop = FALSE]
  map <- match(oo$Species, rows$Species)
  ll <- vapply(seq_len(nrow(oo)), function(j)
    log_mean_exp(dbinom(oo$High[j], 1L, p[, map[j]], log = TRUE)),
    numeric(1))
  obs_rows <- which(st$obs$Species %in% species & !is.na(st$obs$High))
  stopifnot(length(obs_rows) == nrow(oo),
            identical(as.character(st$obs$RecordID[obs_rows]), as.character(oo$RecordID)))
  list(score = ll, record = oo$RecordID, obs_rows = obs_rows,
       species = oo$Species, type = oo$Type, prob = prob,
       auc_y = oo$High == 1L, auc_p = prob[map])
}
score_joint_records <- function(bundle, st, held_rows) {
  ll <- rstan::extract(bundle$fit, pars = "log_lik", permuted = TRUE)$log_lik
  md <- rstan::extract(bundle$fit, pars = "m", permuted = TRUE)$m
  sid <- match(st$obs$Species[held_rows], st$panel$Species)
  z <- st$obs[held_rows, , drop = FALSE]
  observed_point <- rep(NA_real_, nrow(z))
  observed_point[z$Type == "count"] <- z$Events[z$Type == "count"] / z$Total[z$Type == "count"]
  observed_point[z$Type == "exact"] <- z$Exact[z$Type == "exact"]
  list(score = vapply(held_rows, function(i) log_mean_exp(ll[, i]), numeric(1)),
       record = z$RecordID, obs_rows = held_rows, species = z$Species,
       type = z$Type, point = colMeans(md[, sid, drop = FALSE]),
       observed_point = observed_point)
}
score_scheme_records <- function(bundle, st, held_rows) {
  dat <- scheme_data(st, bundle$model, held_rows)
  bp <- bundle$blueprint
  dr <- draw_scheme_params(bundle$fit, dat[, bp$columns, drop = FALSE])
  ll <- loglik_scheme(dr$mu, dr$sigma, dat)
  ex <- scheme_expected(dr$mu, dr$sigma)
  z <- st$obs[held_rows, , drop = FALSE]
  observed_point <- rep(NA_real_, nrow(z))
  observed_point[z$Type == "count"] <- z$Events[z$Type == "count"] / z$Total[z$Type == "count"]
  observed_point[z$Type == "exact"] <- z$Exact[z$Type == "exact"]
  list(score = row_log_mean_exp(ll), record = z$RecordID, obs_rows = held_rows,
       species = z$Species, type = z$Type, point = colMeans(ex),
       observed_point = observed_point)
}

auc_value <- function(y, p) {
  if (length(unique(y)) < 2L) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(y, p, levels = c(FALSE, TRUE),
                                  direction = "<", quiet = TRUE)))
}
point_error_summary <- function(st, held_rows, point) {
  use <- st$obs$Type[held_rows] %in% c("count", "exact")
  if (!any(use)) return(list(MAE = NA_real_, PointRecords = 0L, AbsErrorSum = 0))
  z <- st$obs[held_rows[use], , drop = FALSE]
  observed <- ifelse(z$Type == "count", z$Events / z$Total, z$Exact)
  err <- abs(point[use] - observed)
  list(MAE = mean(err), PointRecords = length(err), AbsErrorSum = sum(err))
}

record_score_frame <- function(st, route, design, model, fold, held_rows, sc) {
  rows <- sc$obs_rows
  z <- st$obs[rows, , drop = FALSE]
  n <- nrow(z)
  out <- data.frame(Route = route, Design = design, Model = model, Fold = fold,
                    RecordID = z$RecordID, Species = z$Species, Type = z$Type,
                    Score = as.numeric(sc$score),
                    ObservedHigh = NA_real_, PredictedPrHigh = NA_real_,
                    ObservedPoint = NA_real_, PredictedPoint = NA_real_,
                    Events = z$Events, Total = z$Total, Exact = z$Exact,
                    Lower = z$Lower, Upper = z$Upper,
                    stringsAsFactors = FALSE)
  if (route == "binary") {
    out$ObservedHigh <- as.numeric(sc$auc_y)
    out$PredictedPrHigh <- as.numeric(sc$auc_p)
  } else {
    out$ObservedPoint <- as.numeric(sc$observed_point)
    out$PredictedPoint <- as.numeric(sc$point)
  }
  out
}

run_cv_route <- function(st, route = c("binary", "joint_bb", "schemeA_tobit"),
                          folds, tag = "fivefold") {
  route <- match.arg(route)
  out <- list()
  records <- list()
  for (model in MODELS) {
    for (k in sort(unique(folds$Fold))) {
      held_species <- folds$Species[folds$Fold == k]
      train_species <- setdiff(folds$Species, held_species)
      fit_tag <- paste0("cv_", tag, "_", model, "_f", k)
      if (route == "binary") {
        bundle <- fit_binomial_model(st, model, train_species, fit_tag)
        sc <- score_binary_records(bundle, st, held_species)
        records[[length(records) + 1L]] <- record_score_frame(
          st, route, tag, model, k, sc$obs_rows, sc)
        out[[length(out) + 1L]] <- data.frame(Route = route, Design = tag, Model = model,
          Fold = k, ELPD = sum(sc$score), AUC = auc_value(sc$auc_y, sc$auc_p),
          MAE = NA_real_, PointRecords = 0L, AbsErrorSum = 0,
          Records = length(sc$score), Species = length(unique(sc$species)))
      } else if (route == "joint_bb") {
        bundle <- fit_joint_model(st, model, train_species, fit_tag)
        held_rows <- which(st$obs$Species %in% held_species)
        sc <- score_joint_records(bundle, st, held_rows)
        pe <- point_error_summary(st, held_rows, sc$point)
        records[[length(records) + 1L]] <- record_score_frame(
          st, route, tag, model, k, held_rows, sc)
        out[[length(out) + 1L]] <- data.frame(Route = route, Design = tag, Model = model,
          Fold = k, ELPD = sum(sc$score), AUC = NA_real_,
          MAE = pe$MAE, PointRecords = pe$PointRecords, AbsErrorSum = pe$AbsErrorSum,
          Records = length(sc$score), Species = length(held_species))
      } else {
        held_rows <- which(st$obs$Species %in% held_species)
        train_rows <- which(!st$obs$Species %in% held_species)
        bundle <- fit_schemeA_model(st, model, train_rows, fit_tag)
        sc <- score_scheme_records(bundle, st, held_rows)
        pe <- point_error_summary(st, held_rows, sc$point)
        records[[length(records) + 1L]] <- record_score_frame(
          st, route, tag, model, k, held_rows, sc)
        out[[length(out) + 1L]] <- data.frame(Route = route, Design = tag, Model = model,
          Fold = k, ELPD = sum(sc$score), AUC = NA_real_,
          MAE = pe$MAE, PointRecords = pe$PointRecords, AbsErrorSum = pe$AbsErrorSum,
          Records = length(sc$score), Species = length(held_species))
      }
    }
  }
  list(folds = do.call(rbind, out), records = do.call(rbind, records))
}

full_predict <- function(st) {
  rows <- list()
  for (model in MODELS) {
    status_binary <- prediction_status(st, model, outcome = "binary")
    status_ratio <- prediction_status(st, model, outcome = "joint")
    bb <- readRDS(file.path(run_dir, "fits", paste0("binary_", model, "_full.rds")))
    pb <- binary_predictions(bb, st, model)
    qb <- data.frame(Species = st$panel$Species, Model = model,
                     Route = "binary", Point = pb$point,
                     CrI_lower = pb$lower, CrI_upper = pb$upper,
                     PI_lower = NA_real_, PI_upper = NA_real_,
                      Status = status_binary, stringsAsFactors = FALSE)
    rows[[length(rows) + 1L]] <- qb
    jj <- readRDS(file.path(run_dir, "fits", paste0("joint_", model, "_full.rds")))
    pj <- quant_predictions(jj, st, scheme = FALSE)
    qj <- data.frame(Species = st$panel$Species, Model = model,
                     Route = "joint_bb", Point = pj$point,
                     CrI_lower = pj$lower, CrI_upper = pj$upper,
                     PI_lower = pj$pi_lower, PI_upper = pj$pi_upper,
                      Status = status_ratio, stringsAsFactors = FALSE)
    rows[[length(rows) + 1L]] <- qj
    ss <- readRDS(file.path(run_dir, "fits", paste0("schemeA_", model, "_full.rds")))
    ps <- quant_predictions(ss, st, scheme = TRUE)
    qs <- data.frame(Species = st$panel$Species, Model = model,
                     Route = "schemeA_tobit", Point = ps$point,
                     CrI_lower = ps$lower, CrI_upper = ps$upper,
                     PI_lower = ps$pi_lower, PI_upper = ps$pi_upper,
                      Status = status_ratio, stringsAsFactors = FALSE)
    rows[[length(rows) + 1L]] <- qs
  }
  out <- do.call(rbind, rows)
  write.csv(out, file.path(result_dir, "full_panel_predictions_v2.csv"), row.names = FALSE)
  quant <- out$Route != "binary"
  stopifnot(all(is.finite(out$Point)), all(out$Point >= 0 & out$Point <= 1),
            all(is.finite(out$CrI_lower)), all(is.finite(out$CrI_upper)),
            all(out$CrI_lower >= 0 & out$CrI_upper <= 1),
            all(is.finite(out$PI_lower[quant])), all(is.finite(out$PI_upper[quant])),
            all(out$PI_lower[quant] >= 0 & out$PI_upper[quant] <= 1))
  out
}

external_predict <- function(st, input_path,
                             output_path = file.path(result_dir, "external_predictions_v2.csv")) {
  input_path <- normalizePath(input_path, winslash = "/", mustWork = TRUE)
  dat <- read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE,
                  colClasses = "character")
  required <- c("Species", st$site_cols)
  if (!all(required %in% names(dat)))
    stop("新物种输入必须包含 Species 和六个位点列：", paste(st$site_cols, collapse = ", "))
  if (!nrow(dat)) stop("新物种输入没有数据行")
  if (anyNA(dat$Species) || any(!nzchar(trimws(dat$Species))) || anyDuplicated(dat$Species))
    stop("新物种输入的 Species 必须非空且唯一")
  panel <- dat[, required, drop = FALSE]
  allowed_residues <- c(strsplit("ACDEFGHIKLMNPQRSTVWY", "")[[1L]],
                        "", "NA", "X", "-", "MISSING", "INDEL")
  for (s in st$site_cols) {
    z <- toupper(trimws(as.character(panel[[s]])))
    if (any(!is.na(z) & !z %in% allowed_residues))
      stop("新物种输入的 ", s, " 含无法解释的残基符号；请提供单字母氨基酸或 MISSING/INDEL")
  }
  rows <- list()
  for (model in MODELS) {
    xb <- design_matrix_for_panel(st, model, "binary", panel)
    sb <- readRDS(file.path(run_dir, "fits", paste0("binary_", model, "_full.rds")))
    pb <- binary_predictions_X(sb, xb)
    status_b <- prediction_status(st, model, outcome = "binary", panel = panel)
    rows[[length(rows) + 1L]] <- data.frame(
      Species = panel$Species, Model = model, Route = "binary",
      Point = pb$point, CrI_lower = pb$lower, CrI_upper = pb$upper,
      PI_lower = NA_real_, PI_upper = NA_real_, Status = status_b,
      stringsAsFactors = FALSE)

    xj <- design_matrix_for_panel(st, model, "joint", panel)
    sj <- readRDS(file.path(run_dir, "fits", paste0("joint_", model, "_full.rds")))
    pj <- quant_predictions_X(sj, xj, scheme = FALSE)
    status_q <- prediction_status(st, model, outcome = "joint", panel = panel)
    rows[[length(rows) + 1L]] <- data.frame(
      Species = panel$Species, Model = model, Route = "joint_bb",
      Point = pj$point, CrI_lower = pj$lower, CrI_upper = pj$upper,
      PI_lower = pj$pi_lower, PI_upper = pj$pi_upper, Status = status_q,
      stringsAsFactors = FALSE)

    sa <- readRDS(file.path(run_dir, "fits", paste0("schemeA_", model, "_full.rds")))
    pa <- quant_predictions_X(sa, xj, scheme = TRUE)
    rows[[length(rows) + 1L]] <- data.frame(
      Species = panel$Species, Model = model, Route = "schemeA_tobit",
      Point = pa$point, CrI_lower = pa$lower, CrI_upper = pa$upper,
      PI_lower = pa$pi_lower, PI_upper = pa$pi_upper, Status = status_q,
      stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, rows)
  raw_miss <- do.call(cbind, lapply(st$site_cols, function(s)
    encode_raw(panel[[s]], s, "M1") == "MISSING"))
  out$AnyMissingSite <- rowSums(raw_miss) > 0L
  out$PredictionSource <- "external_fixed_six_site_table"
  if (!grepl("^/", output_path)) output_path <- file.path(root, output_path)
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  write.csv(out, output_path, row.names = FALSE)
  wide_rows <- lapply(split(out, out$Model), function(z) {
    b <- z[z$Route == "binary", , drop = FALSE]
    j <- z[z$Route == "joint_bb", , drop = FALSE]
    s <- z[z$Route == "schemeA_tobit", , drop = FALSE]
    stopifnot(nrow(b) == nrow(j), nrow(b) == nrow(s),
              identical(as.character(b$Species), as.character(j$Species)),
              identical(as.character(b$Species), as.character(s$Species)))
    data.frame(
      Species = b$Species, Model = z$Model[[1L]],
      PrHigh = b$Point, PrHigh_CrI_lower95 = b$CrI_lower,
      PrHigh_CrI_upper95 = b$CrI_upper,
      JointRatio = j$Point, JointRatio_CrI_lower95 = j$CrI_lower,
      JointRatio_CrI_upper95 = j$CrI_upper,
      JointRatio_PI_lower95 = j$PI_lower, JointRatio_PI_upper95 = j$PI_upper,
      SchemeARatio = s$Point, SchemeARatio_CrI_lower95 = s$CrI_lower,
      SchemeARatio_CrI_upper95 = s$CrI_upper,
      SchemeARatio_PI_lower95 = s$PI_lower, SchemeARatio_PI_upper95 = s$PI_upper,
      Status_binary = b$Status, Status_joint = j$Status, Status_schemeA = s$Status,
      AnyMissingSite = b$AnyMissingSite, PredictionSource = b$PredictionSource,
      stringsAsFactors = FALSE)
  })
  wide <- do.call(rbind, wide_rows)
  wide_path <- sub("\\.csv$", "_wide.csv", output_path)
  write.csv(wide, wide_path, row.names = FALSE)
  quant <- out$Route != "binary"
  stopifnot(all(is.finite(out$Point)), all(out$Point >= 0 & out$Point <= 1),
            all(is.finite(out$CrI_lower)), all(is.finite(out$CrI_upper)),
            all(out$CrI_lower >= 0 & out$CrI_upper <= 1),
            all(is.finite(out$PI_lower[quant])), all(is.finite(out$PI_upper[quant])),
            all(out$PI_lower[quant] >= 0 & out$PI_upper[quant] <= 1))
  out
}

aggregate_scores <- function(tab, route) {
  sub <- tab[tab$Route == route, , drop = FALSE]
  agg <- aggregate(ELPD ~ Model, sub, sum)
  names(agg)[2] <- "ELPD"
  null <- agg$ELPD[match("Null", agg$Model)]
  agg$DeltaELPD_Null <- agg$ELPD - null
  models <- as.character(agg$Model)
  auc <- data.frame(Model = models, AUC = vapply(models, function(m) {
    z <- sub$AUC[sub$Model == m]
    z <- z[is.finite(z)]
    if (length(z)) mean(z) else NA_real_
  }, numeric(1)), stringsAsFactors = FALSE)
  err <- do.call(rbind, lapply(models, function(m) {
    z <- sub[sub$Model == m, , drop = FALSE]
    n <- sum(z$PointRecords, na.rm = TRUE)
    s <- sum(z$AbsErrorSum, na.rm = TRUE)
    data.frame(Model = m, MAE = if (n > 0) s / n else NA_real_,
               PointRecords = n, stringsAsFactors = FALSE)
  }))
  merge(merge(agg, auc, by = "Model", all.x = TRUE),
        err, by = "Model", all.x = TRUE)
}

run_smoke <- function(st) {
  log_msg("SMOKE_START")
  b <- fit_binomial_model(st, "M1", st$binary_species, "smoke",
                          iter = 300L, warmup = 150L, chains = 2L, cores = 2L)
  j <- fit_joint_model(st, "M1", st$joint_species, "smoke",
                       iter = 300L, warmup = 150L, chains = 2L, cores = 2L)
  s <- fit_schemeA_model(st, "M1", seq_len(nrow(st$obs)), "smoke",
                          iter = 300L, warmup = 150L, chains = 2L, cores = 2L)
  mb3 <- fit_binomial_model(st, "M3", st$binary_species, "smoke",
                            iter = 300L, warmup = 150L, chains = 2L, cores = 2L)
  mj3 <- fit_joint_model(st, "M3", st$joint_species, "smoke",
                         iter = 300L, warmup = 150L, chains = 2L, cores = 2L)
  ms3 <- fit_schemeA_model(st, "M3", seq_len(nrow(st$obs)), "smoke",
                           iter = 300L, warmup = 150L, chains = 2L, cores = 2L)
  stopifnot(file.exists(file.path(run_dir, "fits", "binary_M1_smoke.rds")),
            file.exists(file.path(run_dir, "fits", "joint_M1_smoke.rds")),
            file.exists(file.path(run_dir, "fits", "schemeA_M1_smoke.rds")),
            file.exists(file.path(run_dir, "fits", "binary_M3_smoke.rds")),
            file.exists(file.path(run_dir, "fits", "joint_M3_smoke.rds")),
            file.exists(file.path(run_dir, "fits", "schemeA_M3_smoke.rds")))
  bp <- binary_predictions(b, st, "M1")
  qj <- quant_predictions(j, st, FALSE)
  qs <- quant_predictions(s, st, TRUE)
  stopifnot(all(is.finite(bp$point)), all(is.finite(qj$pi_lower)),
            all(is.finite(qs$pi_upper)),
            all(qj$pi_lower <= qj$pi_upper),
            all(qs$pi_lower <= qs$pi_upper))
  smoke_panel <- st$panel[1:2, c("Species", st$site_cols), drop = FALSE]
  smoke_panel$Species <- c("SMOKE_seen", "SMOKE_unseen")
  b3 <- st$blueprints$joint_M3
  found_unseen <- FALSE
  for (site in st$model_sites) {
    enc <- encode_raw(st$panel[[site]], site, "M3", st$freqs[[site]])
    candidate <- which(!enc %in% b3$seen[[site]])
    if (length(candidate)) {
      smoke_panel$Site3[2] <- smoke_panel$Site3[2]
      smoke_panel[[site]][2] <- st$panel[[site]][candidate[[1L]]]
      found_unseen <- TRUE
      break
    }
  }
  stopifnot(found_unseen)
  xb3 <- design_matrix_for_panel(st, "M3", "binary", smoke_panel)
  xj3 <- design_matrix_for_panel(st, "M3", "joint", smoke_panel)
  pb3 <- binary_predictions_X(mb3, xb3)
  pj3 <- quant_predictions_X(mj3, xj3, scheme = FALSE)
  ps3 <- quant_predictions_X(ms3, xj3, scheme = TRUE)
  st3b <- prediction_status(st, "M3", "binary", smoke_panel)
  st3q <- prediction_status(st, "M3", "joint", smoke_panel)
  stopifnot(all(is.finite(pb3$point)), all(is.finite(pj3$point)),
            all(is.finite(pj3$pi_lower)), all(is.finite(ps3$point)),
            all(is.finite(ps3$pi_upper)),
            any(st3b != "supported"), any(st3q != "supported"))
  write_json(list(status = "PASS", version = VERSION,
                  binary = b$diagnostics$Status, joint = j$diagnostics$Status,
                  schemeA = s$diagnostics$Status,
                  posterior_dimensions = list(binary = dim(bp$draws),
                                              joint_expected = dim(qj$expected_draws),
                                              schemeA_expected = dim(qs$expected_draws))),
             file.path(review_dir, "smoke_v2.json"))
  log_msg("SMOKE_PASS")
  invisible(TRUE)
}

run_full_fits <- function(st) {
  dir.create(file.path(run_dir, "fits"), recursive = TRUE, showWarnings = FALSE)
  diag <- list()
  for (model in MODELS) {
    log_msg("FIT_BINARY", model)
    d <- fit_binomial_model(st, model)$diagnostics; d$Route <- "binary"; d$Model <- model; diag[[length(diag)+1L]] <- d
    log_msg("FIT_JOINT_BB", model)
    d <- fit_joint_model(st, model)$diagnostics; d$Route <- "joint_bb"; d$Model <- model; diag[[length(diag)+1L]] <- d
    log_msg("FIT_SCHEME_A", model)
    d <- fit_schemeA_model(st, model)$diagnostics; d$Route <- "schemeA_tobit"; d$Model <- model; diag[[length(diag)+1L]] <- d
  }
  diagnostics <- do.call(rbind, diag)
  write.csv(diagnostics, file.path(result_dir, "full_diagnostics_v2.csv"), row.names = FALSE)
  stopifnot(all(diagnostics$Status == "PASS"))
  diagnostics
}

summarize_ppc <- function(route, model, subset, statistic, observed, replicated) {
  q <- quantile(replicated, c(.025, .5, .975), names = FALSE)
  inside <- is.finite(observed) && observed >= q[[1L]] && observed <= q[[3L]]
  status <- if (!is.finite(observed)) "DESCRIPTIVE_ONLY" else if (inside) "IN_RANGE" else "REVIEW_REQUIRED"
  data.frame(Route = route, Model = model, Subset = subset,
             Statistic = statistic, Observed = observed,
             PPC_Lower95 = q[[1L]], PPC_Median = q[[2L]],
             PPC_Upper95 = q[[3L]],
             Status = status,
             stringsAsFactors = FALSE)
}
model_fit_checks <- function(st) {
  rows <- list()
  for (model in MODELS) {
    jb <- readRDS(file.path(run_dir, "fits", paste0("joint_", model, "_full.rds")))
    jd <- rstan::extract(jb$fit, pars = c("m", "rho", "shape_a",
                                          "shape_b", "log_phi_count"),
                         permuted = TRUE)
    nd <- min(400L, nrow(jd$m))
    set.seed(SEED + 100L)
    use <- sample(seq_len(nrow(jd$m)), nd)
    obs <- st$obs
    ci <- which(obs$Type == "count")
    ei <- which(obs$Type == "exact")
    ii <- which(obs$Type == "interval")
    sid <- match(obs$Species, st$panel$Species)
    rc <- matrix(NA_real_, nd, length(ci))
    re <- matrix(NA_real_, nd, length(ei))
    ri <- matrix(NA_real_, nd, length(ii))
    for (j in seq_len(nd)) {
      d <- use[[j]]
      phi <- exp(jd$log_phi_count[d])
      pc <- stats::rbeta(length(ci), phi * jd$m[d, sid[ci]],
                         phi * (1 - jd$m[d, sid[ci]]))
      rc[j, ] <- stats::rbinom(length(ci), obs$Total[ci], pc) / obs$Total[ci]
      hit <- stats::runif(length(ei)) < jd$rho[d] * jd$m[d, sid[ei]]
      re[j, ] <- ifelse(hit, 1,
                        stats::rbeta(length(ei), jd$shape_a[d, sid[ei]],
                                     jd$shape_b[d, sid[ei]]))
      if (length(ii)) {
        hit_i <- stats::runif(length(ii)) < jd$rho[d] * jd$m[d, sid[ii]]
        ri[j, ] <- ifelse(hit_i, 1,
                          stats::rbeta(length(ii), jd$shape_a[d, sid[ii]],
                                       jd$shape_b[d, sid[ii]]))
      }
    }
    if (length(ci)) {
      observed <- obs$Events[ci] / obs$Total[ci]
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "count", "OneFraction",
        mean(observed == 1), rowMeans(rc == 1))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "count", "ZeroFraction",
        mean(observed == 0), rowMeans(rc == 0))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "count", "SD",
        stats::sd(observed), apply(rc, 1L, stats::sd))
    }
    if (length(ei)) {
      observed <- obs$Exact[ei]
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "exact", "Mean",
        mean(observed), rowMeans(re))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "exact", "SD",
        stats::sd(observed), apply(re, 1L, stats::sd))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "exact", "OneFraction",
        mean(observed == 1), rowMeans(re == 1))
    }
    if (length(ii)) {
      inside <- rowMeans(sweep(ri, 2L, obs$Lower[ii], ">=") &
                         sweep(ri, 2L, obs$Upper[ii], "<="))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "joint_bb", model, "interval", "IntervalCoverage",
        NA_real_, inside)
    }
    sb <- readRDS(file.path(run_dir, "fits", paste0("schemeA_", model, "_full.rds")))
    dat <- scheme_data(st, model)
    dr <- draw_scheme_params(sb$fit, dat[, sb$blueprint$columns, drop = FALSE])
    nd2 <- min(400L, nrow(dr$mu))
    use2 <- sample(seq_len(nrow(dr$mu)), nd2)
    rs <- matrix(NA_real_, nd2, nrow(dat))
    for (j in seq_len(nd2))
      rs[j, ] <- pmin(pmax(stats::rnorm(nrow(dat), dr$mu[use2[[j]], ],
                                         dr$sigma[use2[[j]]]), 0), 1)
    if (length(ci)) {
      observed <- obs$Events[ci] / obs$Total[ci]
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "count", "OneFraction",
        mean(observed == 1), rowMeans(rs[, ci, drop = FALSE] == 1))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "count", "ZeroFraction",
        mean(observed == 0), rowMeans(rs[, ci, drop = FALSE] == 0))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "count", "SD",
        stats::sd(observed), apply(rs[, ci, drop = FALSE], 1L, stats::sd))
    }
    if (length(ei)) {
      observed <- obs$Exact[ei]
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "exact", "Mean",
        mean(observed), rowMeans(rs[, ei, drop = FALSE]))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "exact", "SD",
        stats::sd(observed), apply(rs[, ei, drop = FALSE], 1L, stats::sd))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "exact", "OneFraction",
        mean(observed == 1), rowMeans(rs[, ei, drop = FALSE] == 1))
    }
    if (length(ii)) {
      inside <- rowMeans(sweep(rs[, ii, drop = FALSE], 2L, obs$Lower[ii], ">=") &
                         sweep(rs[, ii, drop = FALSE], 2L, obs$Upper[ii], "<="))
      rows[[length(rows) + 1L]] <- summarize_ppc(
        "schemeA_tobit", model, "interval", "IntervalCoverage",
        NA_real_, inside)
    }
  }
  out <- do.call(rbind, rows)
  write.csv(out, file.path(result_dir, "model_fit_checks_v2.csv"), row.names = FALSE)
  flags <- sum(out$Status == "REVIEW_REQUIRED")
  write_json(list(status = if (flags) "COMPLETE_WITH_REVIEW_FLAGS" else "PASS",
                  route_models = 10L, rows = nrow(out),
                  review_flags = flags,
                  descriptive_only_rows = sum(out$Status == "DESCRIPTIVE_ONLY"),
                  note = "Training-data posterior predictive checks; not independent validation"),
             file.path(review_dir, "model_fit_checks_v2.json"))
  out
}

run_cv <- function(st) {
  folds5b <- make_folds(st$binary_species, 5L, SEED)
  folds5j <- make_folds(st$joint_species, 5L, SEED + 1L)
  tenb <- make_stratified_tenfold(st)
  tenj <- make_folds(st$joint_species, 10L, SEED + 11L)
  stopifnot(nrow(folds5b) == length(st$binary_species),
            nrow(tenb) == length(st$binary_species),
            nrow(folds5j) == length(st$joint_species),
            nrow(tenj) == length(st$joint_species),
            setequal(folds5b$Species, st$binary_species),
            setequal(tenb$Species, st$binary_species),
            setequal(folds5j$Species, st$joint_species),
            setequal(tenj$Species, st$joint_species))
  ten_ok <- all(fold_gate_binary(st, tenb))
  write.csv(folds5b, file.path(result_dir, "folds_binary_species_5.csv"), row.names = FALSE)
  write.csv(folds5j, file.path(result_dir, "folds_joint_species_5.csv"), row.names = FALSE)
  write.csv(tenb, file.path(result_dir, "folds_binary_candidate_10.csv"), row.names = FALSE)
  write.csv(tenj, file.path(result_dir, "folds_joint_species_10.csv"), row.names = FALSE)
  write_json(list(binary_tenfold_gate = ten_ok,
                  binary_tenfold_fold_has_both = fold_gate_binary(st, tenb)),
             file.path(review_dir, "tenfold_gate_v2.json"))
  all_tabs <- list()
  record_tabs <- list()
  for (design in list(list(tag = "5", b = folds5b, j = folds5j))) {
    for (route in c("binary", "joint_bb", "schemeA_tobit")) {
      f <- if (route == "binary") design$b else design$j
      log_msg("CV_ROUTE", route, design$tag)
      key <- paste(route, design$tag)
      result <- run_cv_route(st, route, f, paste0("species", design$tag))
      all_tabs[[key]] <- result$folds
      record_tabs[[key]] <- result$records
    }
  }
  if (ten_ok) {
    for (route in c("binary", "joint_bb", "schemeA_tobit")) {
      log_msg("CV_ROUTE", route, "10")
      f <- if (route == "binary") tenb else tenj
      key <- paste(route, "10")
      result <- run_cv_route(st, route, f, "species10")
      all_tabs[[key]] <- result$folds
      record_tabs[[key]] <- result$records
    }
  }
  tab <- do.call(rbind, all_tabs)
  record_tab <- do.call(rbind, record_tabs)
  write.csv(tab, file.path(result_dir, "cv_fold_scores_v2.csv"), row.names = FALSE)
  write.csv(record_tab, file.path(result_dir, "cv_record_scores_v2.csv"), row.names = FALSE)
  keys <- unique(paste(tab$Route, tab$Design, sep = "|"))
  comparisons <- do.call(rbind, lapply(keys, function(key) {
    bits <- strsplit(key, "|", fixed = TRUE)[[1L]]
    z <- aggregate_scores(tab[tab$Route == bits[[1L]] & tab$Design == bits[[2L]], , drop = FALSE],
                           bits[[1L]])
    z$Route <- bits[[1L]]
    z$Design <- bits[[2L]]
    z
  }))
  write.csv(comparisons, file.path(result_dir, "cv_comparisons_v2.csv"), row.names = FALSE)
  comparisons
}

run_preflight <- function() {
  st <- prepare()
  stopifnot(file.exists(file.path(run_dir, "prepared_v2.rds")))
  script_path <- file.path(root, "scripts", "v2_pipeline.R")
  if (!file.exists(script_path)) script_path <- file.path(root, "src", "v2_pipeline.R")
  src <- readLines(script_path, warn = FALSE)
  if (any(grepl("^\\s*Phylogeny_only|^\\s*tree\\.nwk|^\\s*L_A", src)))
    stop("v2 source contains a forbidden tree/P-model data symbol")
  ten_gate_folds <- make_stratified_tenfold(st)
  fold_gate <- fold_gate_binary(st, ten_gate_folds)
  write_json(list(status = "PASS", version = VERSION,
                  package_versions = sapply(needed, function(x) as.character(packageVersion(x))),
                  fivefold = TRUE, tenfold_binary_gate = fold_gate,
                  complete_dummy_columns = TRUE,
                  model_sites = st$model_sites,
                  excluded_from_predictors = "Site151",
                  input_hashes = st$hashes,
                  run_root = root),
             file.path(review_dir, "preflight_v2.json"))
  log_msg("PREFLIGHT_PASS")
  st
}

if (stage == "preflight") {
  run_preflight()
} else if (stage == "prepare") {
  prepare()
} else if (stage == "smoke") {
  st <- if (file.exists(file.path(run_dir, "prepared_v2.rds"))) load_state() else run_preflight()
  run_smoke(st)
} else if (stage == "fit") {
  st <- load_state()
  run_full_fits(st)
} else if (stage == "predict") {
  st <- load_state()
  full_predict(st)
} else if (stage == "external") {
  st <- load_state()
  if (is.null(new_data_path)) stop("--stage external 必须同时提供 --new-data <CSV>")
  external_predict(st, new_data_path,
                   if (is.null(external_out_path)) file.path(result_dir, "external_predictions_v2.csv")
                   else external_out_path)
} else if (stage == "cv") {
  st <- load_state()
  run_cv(st)
} else if (stage == "all") {
  st <- if (file.exists(file.path(run_dir, "prepared_v2.rds"))) load_state() else run_preflight()
  smoke_file <- file.path(review_dir, "smoke_v2.json")
  if (!file.exists(smoke_file) || jsonlite::read_json(smoke_file, simplifyVector = TRUE)$status != "PASS") {
    run_smoke(st)
  } else {
    log_msg("SMOKE_ALREADY_PASS")
  }
  diagnostics <- run_full_fits(st)
  ppc <- model_fit_checks(st)
  full_predict(st)
  run_cv(st)
  final_status <- if (any(diagnostics$Status != "PASS")) "FAILED_DIAGNOSTICS" else
    if (any(ppc$Status == "REVIEW_REQUIRED")) "COMPLETE_WITH_REVIEW_FLAGS" else "COMPLETE"
  write_json(list(status = final_status, version = VERSION,
                  diagnostics = if (all(diagnostics$Status == "PASS")) "PASS_ALL_FULL_MODELS" else "REVIEW_REQUIRED",
                  model_fit_checks = jsonlite::read_json(file.path(review_dir, "model_fit_checks_v2.json"), simplifyVector = TRUE),
                   outputs = list(full_panel = "results/full_panel_predictions_v2.csv",
                                  cv_fold_scores = "results/cv_fold_scores_v2.csv",
                                  cv_scores = "results/cv_record_scores_v2.csv",
                                  comparisons = "results/cv_comparisons_v2.csv"),
                  created_at = as.character(Sys.time())),
             file.path(review_dir, "final_v2_status.json"))
  log_msg("FORMAL_V2_COMPLETE")
} else {
  stop("Unknown stage: ", stage)
}

