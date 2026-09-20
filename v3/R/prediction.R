posterior_quantiles <- function(draws, probs = c(.025, .5, .975)) {
  if (!is.matrix(draws)) draws <- as.matrix(draws)
  apply(draws, 2L, stats::quantile, probs = probs, names = FALSE)
}

binary_prediction_draws <- function(bundle, state, species = state$encoded$Species) {
  bp <- bundle$blueprint; idx <- match(species, state$encoded$Species)
  nd <- data.frame(High = 0L, TrainWeight = 1)
  x <- as.data.frame(bp$X[idx, , drop = FALSE])
  if (ncol(x)) names(x) <- bp$columns
  nd <- nd[rep(1L, length(species)), , drop = FALSE]
  if (ncol(x)) nd <- cbind(nd, x)
  brms::posterior_epred(bundle$fit, newdata = nd, re_formula = NA)
}

joint_expected_draws <- function(bundle, state, species = state$encoded$Species) {
  ex <- rstan::extract(bundle$fit, pars = "m", permuted = TRUE)$m
  idx <- match(species, state$encoded$Species)
  ex[, idx, drop = FALSE]
}

joint_projection_draws <- function(bundle, x_new) {
  pars <- rstan::extract(bundle$fit, pars = c("alpha", "beta"), permuted = TRUE)
  alpha <- as.numeric(pars$alpha)
  beta <- pars$beta
  if (is.null(dim(beta))) beta <- matrix(beta, ncol = ncol(x_new))
  if (ncol(x_new) == 0L) return(matrix(rep(stats::plogis(alpha), each = nrow(x_new)),
                                        nrow = length(alpha), ncol = nrow(x_new)))
  out <- matrix(NA_real_, nrow = length(alpha), ncol = nrow(x_new))
  for (d in seq_along(alpha)) out[d, ] <- stats::plogis(alpha[[d]] + as.numeric(x_new %*% beta[d, ]))
  out
}

joint_predictive_draws <- function(bundle, state, species = state$encoded$Species, seed = V3_SEED) {
  ex <- rstan::extract(bundle$fit, pars = c("m", "rho", "log_phi_ratio"), permuted = TRUE)
  idx <- match(species, state$encoded$Species)
  m <- ex$m[, idx, drop = FALSE]; rho <- as.numeric(ex$rho)
  phi <- exp(as.numeric(ex$log_phi_ratio))
  set.seed(seed)
  out <- matrix(NA_real_, nrow(m), ncol(m))
  for (d in seq_len(nrow(m))) {
    endpoint <- rho[[d]] * m[d, ]
    mu_internal <- m[d, ] * (1 - rho[[d]]) / (1 - endpoint)
    hit <- stats::runif(ncol(m)) < endpoint
    out[d, ] <- ifelse(hit, 1, stats::rbeta(ncol(m), phi[[d]] * mu_internal,
                                             phi[[d]] * (1 - mu_internal)))
  }
  out
}

summarize_prediction_draws <- function(draws, predictive_draws = NULL) {
  q <- posterior_quantiles(draws)
  out <- data.frame(Point = q[2, ], CrI_lower = q[1, ], CrI_upper = q[3, ],
                    stringsAsFactors = FALSE)
  if (is.null(predictive_draws)) {
    out$PI_lower <- NA_real_; out$PI_upper <- NA_real_
  } else {
    qp <- posterior_quantiles(predictive_draws)
    out$PI_lower <- qp[1, ]; out$PI_upper <- qp[3, ]
  }
  out
}

make_prediction_table <- function(state, bundles, output_path = NULL) {
  rows <- list(); j <- 0L
  for (train_weighting in V3_TRAIN_WEIGHTINGS) {
    for (model in V3_MODELS) {
      bb <- bundles[[paste("binary", model, train_weighting, sep = "|")]]
      jj <- bundles[[paste("joint_bb", model, train_weighting, sep = "|")]]
      status_b <- assess_applicability(state, model, "binary")
      status_j <- assess_applicability(state, model, "joint_bb")
      bdraw <- binary_prediction_draws(bb, state)
      bsum <- summarize_prediction_draws(bdraw)
      bsum <- cbind(data.frame(Species = state$encoded$Species, Route = "binary", Model = model,
                               TrainWeighting = train_weighting, stringsAsFactors = FALSE), bsum)
      bsum$PI_lower <- NA_real_; bsum$PI_upper <- NA_real_
      bsum <- cbind(bsum, status_b[, setdiff(names(status_b), c("Species", "Model", "Route")), drop = FALSE])
      jdraw <- joint_expected_draws(jj, state)
      jpi <- joint_predictive_draws(jj, state, seed = V3_SEED + match(model, V3_MODELS) +
                                      100L * match(train_weighting, V3_TRAIN_WEIGHTINGS))
      jsum <- summarize_prediction_draws(jdraw, jpi)
      jsum <- cbind(data.frame(Species = state$encoded$Species, Route = "joint_bb", Model = model,
                               TrainWeighting = train_weighting, stringsAsFactors = FALSE), jsum)
      jsum <- cbind(jsum, status_j[, setdiff(names(status_j), c("Species", "Model", "Route")), drop = FALSE])
      rows[[j <- j + 1L]] <- bsum; rows[[j <- j + 1L]] <- jsum
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  if (nrow(out) != nrow(state$encoded) * length(V3_MODELS) * length(V3_ROUTES) *
      length(V3_TRAIN_WEIGHTINGS)) stop("Prediction row count does not match v3 grid")
  if (any(is.finite(out$Point) & (out$Point < 0 | out$Point > 1))) stop("Point predictions out of range")
  if (any(is.finite(out$CrI_lower) & out$CrI_lower > out$CrI_upper, na.rm = TRUE)) stop("CrI bounds invalid")
  if (!is.null(output_path)) write_csv_atomic(out, output_path)
  out
}

binary_record_scores <- function(bundle, state, held_rows) {
  obs <- state$observations[held_rows, , drop = FALSE]
  use <- !is.na(obs$High)
  if (!any(use)) return(data.frame())
  obs <- obs[use, , drop = FALSE]; rows <- which(use); species <- obs$Species
  draws <- binary_prediction_draws(bundle, state, species)
  p <- colMeans(draws)
  ll <- vapply(seq_len(nrow(obs)), function(i) {
    log_mean_exp(if (obs$High[[i]] == 1L) log(draws[, i]) else log1p(-draws[, i]))
  }, numeric(1))
  data.frame(RecordID = obs$RecordID, ExperimentID = obs$ExperimentID, SourceID = obs$SourceID,
             Species = species, Type = obs$Type, ObservedHigh = obs$High,
             ObservedPoint = NA_real_, PredictedPrHigh = p, PredictedPoint = NA_real_,
             LogPredictiveDensityRaw = ll, OriginalRow = held_rows[rows], stringsAsFactors = FALSE)
}

joint_record_scores <- function(bundle, state, held_rows) {
  if (!length(held_rows)) return(data.frame())
  obs <- state$observations[held_rows, , drop = FALSE]
  ll_draws <- rstan::extract(bundle$fit, pars = "log_lik", permuted = TRUE)$log_lik
  m <- joint_expected_draws(bundle, state, obs$Species)
  ll <- vapply(seq_along(held_rows), function(i) log_mean_exp(ll_draws[, held_rows[[i]]]), numeric(1))
  observed <- rep(NA_real_, nrow(obs)); count <- obs$Type == "count"; exact <- obs$Type == "exact"
  observed[count] <- obs$Events[count] / obs$Total[count]; observed[exact] <- obs$Exact[exact]
  data.frame(RecordID = obs$RecordID, ExperimentID = obs$ExperimentID, SourceID = obs$SourceID,
             Species = obs$Species, Type = obs$Type, ObservedHigh = obs$High,
             ObservedPoint = observed, PredictedPrHigh = NA_real_, PredictedPoint = colMeans(m),
             LogPredictiveDensityRaw = ll, OriginalRow = held_rows, stringsAsFactors = FALSE)
}

external_prediction_table <- function(state, bundles, new_sites, output_path = NULL,
                                       models = V3_MODELS, train_weightings = V3_TRAIN_WEIGHTINGS) {
  if (!all(c("Species", V3_SITE_COLUMNS) %in% names(new_sites))) {
    stop("new_sites must contain Species and all six site columns")
  }
  if (anyDuplicated(new_sites$Species)) stop("new_sites Species must be unique")
  enc <- encode_panel(new_sites, state$dictionary)
  rows <- list(); j <- 0L
  for (tw in train_weightings) for (model in models) {
    bp_b <- state$blueprints[[paste0("binary_", model)]]
    bp_j <- state$blueprints[[paste0("joint_", model)]]
    xb <- design_from_blueprint(enc$data, bp_b)
    xj <- design_from_blueprint(enc$data, bp_j)
    bb <- bundles[[paste("binary", model, tw, sep = "|")]]
    jj <- bundles[[paste("joint_bb", model, tw, sep = "|")]]
    nd <- data.frame(High = 0L, TrainWeight = 1)
    nd <- nd[rep(1L, nrow(new_sites)), , drop = FALSE]
    if (ncol(xb)) { colnames(xb) <- bp_b$columns; nd <- cbind(nd, as.data.frame(xb)) }
    bdraw <- brms::posterior_epred(bb$fit, newdata = nd, re_formula = NA)
    bsum <- summarize_prediction_draws(bdraw)
    bstatus <- assess_applicability(list(encoded = enc$data, sites = new_sites,
                                         blueprints = state$blueprints), model, "binary",
                                    training_species = state$binary_species)
    rows[[j <- j + 1L]] <- cbind(data.frame(Species = new_sites$Species, Model = model,
      Route = "binary", TrainWeighting = tw, stringsAsFactors = FALSE), bsum, bstatus[, -c(1:3), drop = FALSE])
    jdraw <- joint_projection_draws(jj, xj)
    # Recompute predictive report draws from the projection m and the same endpoint-mixture parameters.
    pars <- rstan::extract(jj$fit, pars = c("rho", "log_phi_ratio"), permuted = TRUE)
    set.seed(V3_SEED + j); jpi <- matrix(NA_real_, nrow(jdraw), ncol(jdraw))
    for (d in seq_len(nrow(jdraw))) {
      endpoint <- as.numeric(pars$rho)[d] * jdraw[d, ]
      mu_internal <- jdraw[d, ] * (1 - as.numeric(pars$rho)[d]) / (1 - endpoint)
      hit <- stats::runif(ncol(jdraw)) < endpoint
      phi <- exp(as.numeric(pars$log_phi_ratio)[d])
      jpi[d, ] <- ifelse(hit, 1, stats::rbeta(ncol(jdraw), phi * mu_internal, phi * (1 - mu_internal)))
    }
    jsum <- summarize_prediction_draws(jdraw, jpi)
    jstatus <- assess_applicability(list(encoded = enc$data, sites = new_sites,
                                         blueprints = state$blueprints), model, "joint_bb",
                                    training_species = state$joint_species)
    rows[[j <- j + 1L]] <- cbind(data.frame(Species = new_sites$Species, Model = model,
      Route = "joint_bb", TrainWeighting = tw, stringsAsFactors = FALSE), jsum, jstatus[, -c(1:3), drop = FALSE])
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  if (!is.null(output_path)) write_csv_atomic(out, output_path)
  out
}
