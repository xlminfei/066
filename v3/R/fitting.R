diagnose_brms_fit_v3 <- function(fit, max_treedepth = V3_SAMPLING$max_treedepth) {
  require_v3_packages(TRUE)
  draws <- posterior::summarise_draws(posterior::as_draws_array(fit), "rhat", "ess_bulk", "ess_tail")
  sp <- tryCatch(rstan::get_sampler_params(fit$fit, inc_warmup = FALSE), error = function(e) list())
  divergences <- if (length(sp)) sum(vapply(sp, function(x) sum(x[, "divergent__"]), numeric(1))) else NA_real_
  depth_hits <- if (length(sp)) sum(vapply(sp, function(x) sum(x[, "treedepth__"] >= max_treedepth), numeric(1))) else NA_real_
  ebfmi <- if (length(sp)) vapply(sp, function(x) mean(diff(x[, "energy__"])^2) / stats::var(x[, "energy__"]), numeric(1)) else NA_real_
  vals <- unlist(draws[, c("rhat", "ess_bulk", "ess_tail")])
  pass <- all(is.finite(vals)) && max(draws$rhat, na.rm = TRUE) < 1.01 &&
    min(draws$ess_bulk, na.rm = TRUE) >= 400 && min(draws$ess_tail, na.rm = TRUE) >= 400 &&
    isTRUE(divergences == 0) && isTRUE(depth_hits == 0) &&
    all(is.finite(ebfmi)) && min(ebfmi) > 0.3
  data.frame(Status = if (pass) "PASS" else "FAILED_DIAGNOSTICS",
             MaxRhat = max(draws$rhat, na.rm = TRUE),
             MinBulkESS = min(draws$ess_bulk, na.rm = TRUE),
             MinTailESS = min(draws$ess_tail, na.rm = TRUE),
             Divergences = divergences, TreeDepthHits = depth_hits,
             MinEBFMI = if (length(ebfmi)) min(ebfmi) else NA_real_,
             stringsAsFactors = FALSE)
}

diagnose_rstan_fit_v3 <- function(fit, max_treedepth = V3_SAMPLING$max_treedepth) {
  require_v3_packages(TRUE)
  draws <- posterior::summarise_draws(posterior::as_draws_array(fit), "rhat", "ess_bulk", "ess_tail")
  sp <- rstan::get_sampler_params(fit, inc_warmup = FALSE)
  divergences <- sum(vapply(sp, function(x) sum(x[, "divergent__"]), numeric(1)))
  depth_hits <- sum(vapply(sp, function(x) sum(x[, "treedepth__"] >= max_treedepth), numeric(1)))
  ebfmi <- vapply(sp, function(x) mean(diff(x[, "energy__"])^2) / stats::var(x[, "energy__"]), numeric(1))
  pass <- all(is.finite(unlist(draws[, c("rhat", "ess_bulk", "ess_tail")]))) &&
    max(draws$rhat, na.rm = TRUE) < 1.01 && min(draws$ess_bulk, na.rm = TRUE) >= 400 &&
    min(draws$ess_tail, na.rm = TRUE) >= 400 && divergences == 0 && depth_hits == 0 &&
    min(ebfmi) > 0.3
  data.frame(Status = if (pass) "PASS" else "FAILED_DIAGNOSTICS",
             MaxRhat = max(draws$rhat, na.rm = TRUE),
             MinBulkESS = min(draws$ess_bulk, na.rm = TRUE),
             MinTailESS = min(draws$ess_tail, na.rm = TRUE),
             Divergences = divergences, TreeDepthHits = depth_hits,
             MinEBFMI = min(ebfmi), stringsAsFactors = FALSE)
}

binary_training_data <- function(state, model, train_species, train_weighting) {
  obs <- state$observations
  keep <- obs$Species %in% train_species & !is.na(obs$High)
  dat <- obs[keep, c("RecordID", "Species", "High"), drop = FALSE]
  if (!nrow(dat)) stop("No classified training records for binary fit")
  bp <- state$blueprints[[paste0("binary_", model)]]
  idx <- match(dat$Species, state$encoded$Species)
  x <- as.data.frame(bp$X[idx, , drop = FALSE])
  if (ncol(x)) names(x) <- bp$columns
  dat <- cbind(dat, x)
  wf <- build_train_weights(dat[, c("Species"), drop = FALSE], train_weighting)
  dat$TrainWeight <- wf$weight
  dat$High <- as.integer(dat$High)
  dat
}

fit_binomial_model_v3 <- function(state, model, train_species, train_weighting,
                                  out_path, iter = V3_SAMPLING$iter,
                                  warmup = V3_SAMPLING$warmup,
                                  chains = V3_SAMPLING$chains, cores = V3_SAMPLING$cores,
                                  seed = V3_SEED, force = FALSE) {
  require_v3_packages(TRUE)
  dat <- binary_training_data(state, model, train_species, train_weighting)
  request <- fit_identity("binary", model, train_weighting,
                          which(state$observations$Species %in% train_species &
                                  !is.na(state$observations$High)), state,
                          model_code_hash = sha256_object("brms_bernoulli_v3"),
                          sampling = list(iter = iter, warmup = warmup, chains = chains,
                                          cores = cores, seed = seed))
  key <- identity_key(request)
  if (!force && cache_is_valid(out_path, request, "binary", model, train_weighting)) return(readRDS(out_path))
  rhs <- c("1", state$blueprints[[paste0("binary_", model)]]$columns)
  form <- stats::as.formula(sprintf("High | weights(TrainWeight, scale = FALSE) ~ %s",
                                    paste(rhs, collapse = " + ")))
  pri <- brms::set_prior(sprintf("normal(0,%g)", V3_PRIORS$intercept),
                         class = "b", coef = "Intercept")
  if (length(state$blueprints[[paste0("binary_", model)]]$columns)) {
    pri <- c(pri, brms::set_prior(sprintf("normal(0,%g)", V3_PRIORS$beta), class = "b"))
  }
  fit <- brms::brm(brms::bf(form, center = FALSE), data = dat,
                   family = brms::bernoulli(), prior = pri,
                   backend = "rstan", save_pars = brms::save_pars(all = TRUE),
                   seed = seed, chains = chains, cores = cores, iter = iter, warmup = warmup,
                   control = list(adapt_delta = V3_SAMPLING$adapt_delta,
                                  max_treedepth = V3_SAMPLING$max_treedepth),
                   silent = 2, refresh = 0)
  diagnostics <- diagnose_brms_fit_v3(fit)
  bundle <- list(version = V3_VERSION, key = key, request = request, route = "binary",
                 model = model, train_weighting = train_weighting, fit = fit,
                 blueprint = state$blueprints[[paste0("binary_", model)]], data = dat,
                 train_species = train_species, diagnostics = diagnostics)
  save_rds_atomic(bundle, out_path)
  bundle
}

joint_stan_code <- function(stan_path = file.path(dirname(dirname(getwd())), "stan", "joint_bb.stan")) {
  if (!file.exists(stan_path)) stop("Stan source not found: ", stan_path)
  paste(readLines(stan_path, warn = FALSE), collapse = "\n")
}

joint_training_data <- function(state, model, train_species, train_weighting) {
  obs <- state$observations
  n <- nrow(obs); sid <- match(obs$Species, state$encoded$Species)
  train_rows <- which(obs$Species %in% train_species & obs$Informative)
  if (!length(train_rows)) stop("No informative training records for joint fit")
  wf <- build_train_weights(obs[train_rows, c("Species"), drop = FALSE], train_weighting)
  train_weight <- numeric(n); train_weight[train_rows] <- wf$weight
  kind <- match(obs$Type, c("count", "exact", "interval")); kind[is.na(kind)] <- 3L
  events <- rep(0L, n); total <- rep(1L, n); exact <- rep(0, n)
  lower <- rep(0, n); upper <- rep(1, n)
  count <- obs$Type == "count"; exact_i <- obs$Type == "exact"; interval <- obs$Type == "interval"
  events[count] <- as.integer(obs$Events[count]); total[count] <- as.integer(obs$Total[count])
  exact[exact_i] <- obs$Exact[exact_i]
  lower[interval] <- obs$Lower[interval]; upper[interval] <- obs$Upper[interval]
  bp <- state$blueprints[[paste0("joint_", model)]]
  X <- bp$X
  if (!ncol(X)) X <- matrix(0, nrow(state$encoded), 1L)
  list(S = nrow(state$encoded), K = ncol(X), N = n, X = X,
       train = as.integer(train_weight > 0), train_weight = train_weight,
       kind = as.integer(kind), events = events, total = total,
       exact_ratio = as.numeric(exact), lower_ratio = as.numeric(lower),
       upper_ratio = as.numeric(upper), species_id = as.integer(sid),
       prior_intercept_sd = V3_PRIORS$intercept, prior_beta_sd = V3_PRIORS$beta,
       prior_rho_a = V3_PRIORS$rho_a, prior_rho_b = V3_PRIORS$rho_b,
       prior_log_phi_mean = V3_PRIORS$log_phi_mean,
       prior_log_phi_sd = V3_PRIORS$log_phi_sd,
       train_rows = train_rows)
}

fit_joint_model_v3 <- function(state, model, train_species, train_weighting,
                               out_path, stan_path,
                               iter = V3_SAMPLING$iter, warmup = V3_SAMPLING$warmup,
                               chains = V3_SAMPLING$chains, cores = V3_SAMPLING$cores,
                               seed = V3_SEED, force = FALSE) {
  require_v3_packages(TRUE)
  code <- joint_stan_code(stan_path)
  dat <- joint_training_data(state, model, train_species, train_weighting)
  request <- fit_identity("joint_bb", model, train_weighting, dat$train_rows, state,
                          model_code_hash = sha256_object(code),
                          sampling = list(iter = iter, warmup = warmup, chains = chains,
                                          cores = cores, seed = seed))
  key <- identity_key(request)
  if (!force && cache_is_valid(out_path, request, "joint_bb", model, train_weighting)) return(readRDS(out_path))
  if (!exists(".v3_joint_compiled", envir = .GlobalEnv, inherits = FALSE) ||
      !identical(get(".v3_joint_compiled_hash", envir = .GlobalEnv, inherits = FALSE), sha256_object(code))) {
    assign(".v3_joint_compiled", rstan::stan_model(model_code = code, model_name = "ratio_v3_joint_bb"), envir = .GlobalEnv)
    assign(".v3_joint_compiled_hash", sha256_object(code), envir = .GlobalEnv)
  }
  stan_dat <- dat[setdiff(names(dat), "train_rows")]
  fit <- rstan::sampling(get(".v3_joint_compiled", envir = .GlobalEnv), data = stan_dat,
                         seed = seed, chains = chains, cores = cores, iter = iter,
                         warmup = warmup,
                         control = list(adapt_delta = V3_SAMPLING$adapt_delta,
                                        max_treedepth = V3_SAMPLING$max_treedepth))
  diagnostics <- diagnose_rstan_fit_v3(fit)
  bundle <- list(version = V3_VERSION, key = key, request = request,
                 route = "joint_bb", model = model, train_weighting = train_weighting,
                 fit = fit, blueprint = state$blueprints[[paste0("joint_", model)]],
                 data = dat, train_species = train_species, diagnostics = diagnostics,
                 code_hash = sha256_object(code))
  save_rds_atomic(bundle, out_path)
  bundle
}
