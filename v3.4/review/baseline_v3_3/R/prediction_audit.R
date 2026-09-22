# The audit starts from fitted parameters and current inputs, never from saved OOF
# scores. Pure posterior fixtures are opt-in and cannot pass the formal fit gate.
audit_key_v3 <- function(x, columns, context = "table") {
  if (!is.data.frame(x) || !all(columns %in% names(x))) stop(context, ": missing primary-key columns")
  if (anyDuplicated(names(x))) stop(context, ": duplicate column names")
  if (anyNA(x[, columns, drop = FALSE])) stop(context, ": missing primary-key values")
  z <- lapply(x[, columns, drop = FALSE], as.character)
  if (any(vapply(z, function(v) any(!nzchar(v) | grepl("\034", v, fixed = TRUE)), logical(1)))) {
    stop(context, ": empty or unsupported primary-key value")
  }
  do.call(paste, c(z, sep = "\034"))
}

audit_assert_key_grid_v3 <- function(stored, expected, columns, context = "table") {
  actual_key <- audit_key_v3(stored, columns, context)
  expected_key <- audit_key_v3(expected, columns, paste(context, "expected"))
  if (anyDuplicated(actual_key)) stop(context, ": duplicate primary key")
  if (anyDuplicated(expected_key)) stop(context, ": duplicate expected primary key")
  if (length(actual_key) != length(expected_key) || !setequal(actual_key, expected_key)) {
    stop(context, ": primary-key grid mismatch; missing=", length(setdiff(expected_key, actual_key)),
         "; extra=", length(setdiff(actual_key, expected_key)))
  }
  invisible(match(expected_key, actual_key))
}

# CSV serialization may read an all-empty character column as logical NA. Only
# empty character metadata receives that normalization; numeric/logical inactive
# fields must retain their exact NA mask. Integer/double and row order are benign.
audit_compare_table_v3 <- function(stored, expected, keys, context = "table", tolerance = 1e-10) {
  if (length(tolerance) != 1L || !is.finite(tolerance) || tolerance <= 0) stop("Invalid audit tolerance")
  index <- audit_assert_key_grid_v3(stored, expected, keys, context)
  if (!all(names(expected) %in% names(stored))) {
    stop(context, ": missing expected fields: ", paste(setdiff(names(expected), names(stored)), collapse = ", "))
  }
  stored <- stored[index, , drop = FALSE]
  max_error <- 0
  for (column in names(expected)) {
    a <- stored[[column]]; b <- expected[[column]]
    if (is.character(b) || is.factor(b)) {
      a <- as.character(a); b <- as.character(b)
      a[is.na(a) & !is.na(b) & b == ""] <- ""
      if (!identical(is.na(a), is.na(b)) || any(a[!is.na(b)] != b[!is.na(b)])) {
        stop(context, ": value mismatch in ", column)
      }
    } else if (is.numeric(b) || is.logical(b)) {
      if (!is.numeric(a) && !is.logical(a)) stop(context, ": non-numeric/non-logical field ", column)
      if (any(is.nan(a)) || any(is.nan(b))) stop(context, ": NaN is not an inactive NA in ", column)
      if (!identical(is.na(a), is.na(b))) stop(context, ": inactive/NA mask mismatch in ", column)
      valid <- !is.na(b)
      if (any(is.infinite(a[valid]) != is.infinite(b[valid]))) stop(context, ": nonfinite mismatch in ", column)
      if (any(is.infinite(b[valid]) & a[valid] != b[valid])) stop(context, ": infinity sign mismatch in ", column)
      finite <- valid & is.finite(b)
      error <- abs(as.numeric(a[finite]) - as.numeric(b[finite]))
      bound <- if (is.logical(b)) rep(0, sum(finite)) else tolerance * pmax(1, abs(b[finite]))
      if (any(!is.finite(error)) || any(error > bound)) stop(context, ": numeric mismatch in ", column,
        "; max_abs_error=", if (length(error)) max(error) else 0)
      if (length(error)) max_error <- max(max_error, error)
    } else stop(context, ": unsupported audit field type in ", column)
  }
  list(rows = nrow(expected), columns = length(names(expected)), max_absolute_error = max_error)
}

audit_logspace_difference_v3 <- function(a, b) {
  out <- rep(NA_real_, length(a))
  valid <- !is.na(a) & !is.na(b) & a > b
  out[valid] <- a[valid] + log(-expm1(b[valid] - a[valid]))
  out[is.finite(a) & is.infinite(b) & b < 0] <- a[is.finite(a) & is.infinite(b) & b < 0]
  out
}

# Independent R/Rmath reference. Both tails are evaluated; the smaller large-end
# tail is preferred. Finite log-tail differences can still lose precision.
# Close tails, small shapes and narrow intervals use independent density
# quadrature over t in [0,1]; no Stan continued fraction or probability floor.
audit_log_beta_interval_v3 <- function(lo, hi, a, b) {
  if (length(lo) != 1L || length(hi) != 1L || !is.finite(lo) || !is.finite(hi) || lo < 0 || hi > 1 || lo >= hi) {
    stop("Audit beta interval requires 0 <= lo < hi <= 1")
  }
  if (length(a) != length(b) || any(!is.finite(a) | !is.finite(b) | a <= 0 | b <= 0)) stop("Invalid audit beta shapes")
  if (lo == 0 && hi == 1) return(rep(0, length(a)))
  if (lo == 0) return(stats::pbeta(hi, a, b, log.p = TRUE))
  if (hi == 1) return(stats::pbeta(lo, a, b, lower.tail = FALSE, log.p = TRUE))
  cdf_hi <- stats::pbeta(hi, a, b, log.p = TRUE)
  cdf_lo <- stats::pbeta(lo, a, b, log.p = TRUE)
  sf_lo <- stats::pbeta(lo, a, b, lower.tail = FALSE, log.p = TRUE)
  sf_hi <- stats::pbeta(hi, a, b, lower.tail = FALSE, log.p = TRUE)
  left <- audit_logspace_difference_v3(cdf_hi, cdf_lo)
  right <- audit_logspace_difference_v3(sf_lo, sf_hi)
  use_lower <- cdf_hi <= sf_lo
  out <- ifelse(use_lower, left, right)
  other <- ifelse(use_lower, right, left)
  use_other <- !is.finite(out) & is.finite(other)
  out[use_other] <- other[use_other]
  # Track the tail actually used, including the alternative-tail fallback.
  use_lower[use_other] <- !use_lower[use_other]
  tail_gap <- ifelse(use_lower, cdf_hi - cdf_lo, sf_lo - sf_hi)
  close_tails <- is.finite(tail_gap) & tail_gap < 1e-4
  small_shape <- pmin(a, b) < 1e-5
  narrow <- (hi - lo) < 1e-5 * min(lo, 1 - hi)
  for (i in which(!is.finite(out) | close_tails | small_shape | narrow)) {
    mid <- lo + (hi - lo) / 2
    candidates <- c(lo, mid, hi)
    if (a[i] > 1 && b[i] > 1) candidates <- c(candidates, max(lo, min(hi, (a[i] - 1) / (a[i] + b[i] - 2))))
    scale <- max(stats::dbeta(candidates, a[i], b[i], log = TRUE))
    if (!is.finite(scale)) stop("Audit interval density is nonfinite")
    integral <- stats::integrate(function(t) exp(stats::dbeta(lo + (hi - lo) * t, a[i], b[i], log = TRUE) - scale),
      lower = 0, upper = 1, subdivisions = 2000L, rel.tol = 1e-12, abs.tol = 0, stop.on.error = TRUE)
    if (!is.finite(integral$value) || integral$value <= 0 ||
        !is.finite(integral$abs.error) || integral$abs.error > 1e-11 * integral$value) {
      stop("Audit interval quadrature failed its precision check")
    }
    out[i] <- log(hi - lo) + scale + log(integral$value)
  }
  if (any(!is.finite(out)) || any(out > 1e-12)) stop("Invalid audit interval probability")
  pmin(out, 0)
}

raw_joint_loglik_audit_v3 <- function(observation, m, rho, log_phi_count, log_phi_ratio) {
  if (nrow(observation) != 1L) stop("Audit likelihood requires exactly one observation")
  n <- length(m)
  if (!n || any(vapply(list(rho, log_phi_count, log_phi_ratio), length, integer(1)) != n)) stop("Audit parameter length mismatch")
  if (any(!is.finite(m) | m <= 0 | m >= 1 | !is.finite(rho) | rho < 0 | rho > 1)) stop("Invalid audit mean/endpoint parameter")
  kind <- as.character(observation$Type[[1L]])
  if (kind == "count") {
    phi <- exp(log_phi_count); a <- phi * m; b <- phi * (1 - m)
    if (any(!is.finite(a) | !is.finite(b) | a <= 0 | b <= 0)) stop("Invalid audit count precision")
    k <- observation$Events[[1L]]; total <- observation$Total[[1L]]
    answer <- lchoose(total, k) + lbeta(k + a, total - k + b) - lbeta(a, b)
  } else {
    atom <- rho * m; continuous <- 1 - atom
    mu <- m * (1 - rho) / continuous
    a <- exp(log_phi_ratio) * mu; b <- exp(log_phi_ratio) * (1 - mu)
    if (any(!is.finite(a) | !is.finite(b) | a <= 0 | b <= 0)) stop("Invalid audit report precision")
    if (kind == "exact") {
      value <- observation$Exact[[1L]]
      answer <- if (value == 1) log(atom) else log1p(-atom) + stats::dbeta(value, a, b, log = TRUE)
    } else if (kind == "interval") {
      lo <- observation$Lower[[1L]]; hi <- observation$Upper[[1L]]
      if (lo == 0 && hi == 1) return(rep(0, n))
      component <- log1p(-atom) + audit_log_beta_interval_v3(lo, hi, a, b)
      if (hi == 1) {
        endpoint <- log(atom); scale <- pmax(component, endpoint)
        answer <- scale + log(exp(component - scale) + exp(endpoint - scale))
      } else answer <- component
    } else stop("Unsupported audit observation type: ", kind)
  }
  if (anyNA(answer) || any(is.infinite(answer) & answer > 0)) stop("Invalid independently recomputed log likelihood")
  answer
}

audit_extract_parameters_v3 <- function(bundle, allow_fixture = FALSE) {
  if (is.null(bundle$fit)) {
    if (!isTRUE(allow_fixture) || is.null(bundle$posterior)) stop("Audit requires a fitted posterior object")
  } else {
    # Never let a convenience posterior member override the validated fit payload.
    bundle$posterior <- NULL
  }
  pars <- extract_parameters_v3(bundle)
  if (!length(pars$alpha) || any(!is.finite(pars$alpha)) || !is.matrix(pars$beta) ||
      nrow(pars$beta) != length(pars$alpha) || any(!is.finite(pars$beta))) stop("Malformed audit posterior")
  pars
}

audit_project_parameters_v3 <- function(pars, encoded, blueprint) {
  x <- design_from_blueprint(encoded, blueprint)
  if (ncol(x) != ncol(pars$beta)) stop("Audit projection dimension mismatch")
  eta <- if (ncol(x)) tcrossprod(pars$beta, x) else matrix(0, length(pars$alpha), nrow(x))
  eta <- sweep(eta, 1L, pars$alpha, FUN = "+")
  stats::plogis(eta)
}

audit_report_draws_v3 <- function(u, m, pars) {
  atom <- pars$rho * m
  internal <- m * (1 - pars$rho) / (1 - atom)
  result <- rep(1, length(m)); selected <- u < 1 - atom
  result[selected] <- stats::qbeta(u[selected] / (1 - atom[selected]),
    exp(pars$log_phi_ratio[selected]) * internal[selected],
    exp(pars$log_phi_ratio[selected]) * (1 - internal[selected]))
  if (any(!is.finite(result))) stop("Nonfinite independent predictive draws")
  result
}

audit_fresh_panel_v3 <- function(state) {
  sites <- validate_sites_panel(state$sites)
  encoded <- encode_panel(sites, state$dictionary)$data
  if (!identical(encoded, state$encoded)) stop("Audit encoded panel differs from current raw panel/dictionary")
  encoded
}

audit_recompute_cv_scores_v3 <- function(bundle, state, held_rows, allow_fixture = FALSE) {
  if (!length(held_rows) || anyNA(held_rows) || anyDuplicated(held_rows) ||
      any(held_rows != as.integer(held_rows) | held_rows < 1L | held_rows > nrow(state$observations))) stop("Invalid audit held-out rows")
  obs <- state$observations[held_rows, , drop = FALSE]
  if (any(obs$Species %in% bundle$train_species)) stop("Audit held-out species overlap training species")
  encoded <- audit_fresh_panel_v3(state)
  index <- match(obs$Species, encoded$Species); if (anyNA(index)) stop("Unknown audit species")
  pars <- audit_extract_parameters_v3(bundle, allow_fixture)
  m <- audit_project_parameters_v3(pars, encoded[index, , drop = FALSE], bundle$blueprint)
  n <- nrow(obs); missing <- rep(NA_real_, n)
  result <- data.frame(RecordID = obs$RecordID, ExperimentID = obs$ExperimentID, SourceID = obs$SourceID,
    Species = obs$Species, Type = obs$Type, ObservedHigh = obs$High, ObservedPoint = missing,
    PredictedPrHigh = missing, PredictedPoint = missing, PredictedPI_lower = missing,
    PredictedPI_upper = missing, PIWidth = missing, IntervalCovered = rep(NA, n),
    IntervalOverlap = rep(NA, n), PIObservationModel = rep("not_applicable", n),
    LogPredictiveDensityRaw = missing, OriginalRow = held_rows, stringsAsFactors = FALSE)
  if (bundle$route == "binary") {
    if (anyNA(obs$High)) stop("Audit binary rows are unclassified")
    result$PredictedPrHigh <- colMeans(m)
    result$LogPredictiveDensityRaw <- vapply(seq_len(n), function(i) {
      log_mean_exp(if (obs$High[i] == 1L) log(m[, i]) else log1p(-m[, i]))
    }, numeric(1))
  } else if (bundle$route == "joint_bb") {
    if (any(!obs$Informative)) stop("Audit joint rows are uninformative")
    result$PredictedPoint <- colMeans(m)
    set.seed(V3_SEED + sum(held_rows))
    replicated <- m
    for (i in seq_len(n)) {
      if (obs$Type[i] == "count") {
        phi <- exp(pars$log_phi_count)
        p <- stats::rbeta(nrow(m), phi * m[, i], phi * (1 - m[, i]))
        replicated[, i] <- stats::rbinom(nrow(m), obs$Total[i], p) / obs$Total[i]
      } else replicated[, i] <- audit_report_draws_v3(stats::runif(nrow(m)), m[, i], pars)
      result$LogPredictiveDensityRaw[i] <- log_mean_exp(raw_joint_loglik_audit_v3(
        obs[i, , drop = FALSE], m[, i], pars$rho, pars$log_phi_count, pars$log_phi_ratio))
    }
    q <- matrix(apply(replicated, 2L, stats::quantile, probs = c(.025, .975), names = FALSE), nrow = 2L)
    count <- obs$Type == "count"; exact <- obs$Type == "exact"; interval <- obs$Type == "interval"
    result$ObservedPoint[count] <- obs$Events[count] / obs$Total[count]
    result$ObservedPoint[exact] <- obs$Exact[exact]
    result$PredictedPI_lower <- q[1L, ]; result$PredictedPI_upper <- q[2L, ]
    result$PIWidth <- q[2L, ] - q[1L, ]
    result$IntervalCovered[!interval] <- result$ObservedPoint[!interval] >= q[1L, !interval] & result$ObservedPoint[!interval] <= q[2L, !interval]
    result$IntervalOverlap[interval] <- obs$Upper[interval] >= q[1L, interval] & obs$Lower[interval] <= q[2L, interval]
    result$PIObservationModel <- ifelse(count, "beta_binomial_at_observed_Total", "one_inflated_beta_report")
  } else stop("Invalid audit route")
  if (any(!is.finite(result$LogPredictiveDensityRaw))) stop("Nonfinite independent held-out log score")
  status_state <- state
  status_state$blueprints[[blueprint_key(bundle$route, bundle$model)]] <- bundle$blueprint
  status <- assess_applicability(status_state, bundle$model, bundle$route, training_species = bundle$train_species)
  fields <- c("ApplicabilityStatus", "WarningCodes", "AnyMissingInputSite", "AnyMissingPredictorSite",
    "UnseenEncodedCategory", "UnseenRawResidue", "CombinationSeenInTraining", "FixedEffectEstimable", "Site151OutsideTrainingDomain")
  status <- status[match(result$Species, status$Species), fields, drop = FALSE]
  result <- cbind(result, status); rownames(result) <- NULL
  attr(result, "audit_draw_count") <- length(pars$alpha)
  result
}

audit_receipt_v3 <- function(context, check, type, rows, columns, draws, max_error, tolerance,
                             status = "PASS", reason = "") {
  value <- function(name, default = NA) if (name %in% names(context)) context[[name]][[1L]] else default
  data.frame(Check = check, Design = value("Design"), Fold = value("Fold", NA_integer_),
    Route = value("Route"), Model = value("Model"), TrainWeighting = value("TrainWeighting"),
    RunPurpose = value("RunPurpose", "unspecified"), RecordType = type, RowsChecked = rows, ColumnsChecked = columns, PosteriorDraws = draws,
    MaximumAbsoluteDifference = max_error, AbsoluteAndRelativeTolerance = tolerance,
    RecomputeSource = "fitted_posterior_parameters_and_current_inputs", Coverage = "all_rows_in_fit_stratum",
    Status = status, Reason = reason, stringsAsFactors = FALSE)
}

audit_cv_bundle_predictions_v3 <- function(bundle, state, held_rows, stored, context,
                                            tolerance = 1e-10, allow_fixture = FALSE) {
  expected <- audit_recompute_cv_scores_v3(bundle, state, held_rows, allow_fixture)
  draws <- attr(expected, "audit_draw_count")
  for (name in c("Design", "Fold", "Route", "Model", "TrainWeighting")) expected[[name]] <- context[[name]][[1L]]
  if (bundle$route != context$Route[[1L]] || bundle$model != context$Model[[1L]] ||
      bundle$train_weighting != context$TrainWeighting[[1L]]) stop("Audit fit/evidence context mismatch")
  expected$FitKey <- bundle$key
  if ("RunPurpose" %in% names(context)) expected$RunPurpose <- context$RunPurpose[[1L]]
  keys <- c("Design", "Route", "Model", "TrainWeighting", "RecordID")
  label <- paste("posterior_to_OOF", paste(unlist(context[c("Design", "Route", "Model", "TrainWeighting", "Fold")]), collapse = "/"))
  audit_compare_table_v3(stored, expected, keys, label, tolerance)
  receipts <- lapply(unique(as.character(expected$Type)), function(type) {
    z <- expected[expected$Type == type, , drop = FALSE]; s <- stored[stored$Type == type, , drop = FALSE]
    result <- audit_compare_table_v3(s, z, keys, paste(label, type), tolerance)
    audit_receipt_v3(context, "posterior_to_OOF", type, result$rows, result$columns, draws,
      result$max_absolute_error, tolerance)
  })
  receipts <- do.call(rbind, receipts)
  if (is.null(bundle$fit)) receipts$RecomputeSource <- "explicit_synthetic_posterior_fixture_and_current_inputs"
  receipts
}

audit_recompute_full_predictions_v3 <- function(bundle, state, allow_fixture = FALSE) {
  encoded <- audit_fresh_panel_v3(state)
  pars <- audit_extract_parameters_v3(bundle, allow_fixture)
  m <- audit_project_parameters_v3(pars, encoded, bundle$blueprint)
  q <- matrix(apply(m, 2L, stats::quantile, probs = c(.025, .5, .975), names = FALSE), nrow = 3L)
  result <- data.frame(Species = state$sites$Species, Route = bundle$route, Model = bundle$model,
    TrainWeighting = bundle$train_weighting, Point = colMeans(m), PosteriorMedian = q[2L, ],
    CrI_lower = q[1L, ], CrI_upper = q[3L, ], PI_lower = NA_real_, PI_upper = NA_real_, stringsAsFactors = FALSE)
  if (bundle$route == "joint_bb") {
    set.seed(V3_SEED); u <- stats::runif(nrow(m)); replicated <- m
    for (i in seq_len(ncol(m))) replicated[, i] <- audit_report_draws_v3(u, m[, i], pars)
    qp <- matrix(apply(replicated, 2L, stats::quantile, probs = c(.025, .975), names = FALSE), nrow = 2L)
    result$PI_lower <- qp[1L, ]; result$PI_upper <- qp[2L, ]
  }
  status_state <- list(encoded = encoded, sites = state$sites,
    blueprints = setNames(list(bundle$blueprint), blueprint_key(bundle$route, bundle$model)))
  status <- assess_applicability(status_state, bundle$model, bundle$route, training_species = bundle$train_species)
  result <- cbind(result, status[, setdiff(names(status), c("Species", "Model", "Route")), drop = FALSE])
  result$PredictionTarget <- if (bundle$route == "binary") "Pr_HIGH" else "mean_ratio_and_future_exact_report_PI"
  attr(result, "audit_draw_count") <- length(pars$alpha)
  result
}

audit_full_bundle_predictions_v3 <- function(bundle, state, stored, context,
                                              tolerance = 1e-10, allow_fixture = FALSE) {
  if (bundle$route != context$Route[[1L]] || bundle$model != context$Model[[1L]] ||
      bundle$train_weighting != context$TrainWeighting[[1L]]) stop("Audit fit/full-panel context mismatch")
  expected <- audit_recompute_full_predictions_v3(bundle, state, allow_fixture)
  result <- audit_compare_table_v3(stored, expected, c("Species", "Route", "Model", "TrainWeighting"),
    "posterior_to_full_panel", tolerance)
  receipt <- audit_receipt_v3(context, "posterior_to_full_panel", "all_panel_species", result$rows, result$columns,
    attr(expected, "audit_draw_count"), result$max_absolute_error, tolerance)
  if (is.null(bundle$fit)) receipt$RecomputeSource <- "explicit_synthetic_posterior_fixture_and_current_inputs"
  receipt
}

validate_comparison_grid_v3 <- function(model_table, training_table, designs = V3_DESIGNS,
                                         routes = V3_ROUTES, models = V3_MODELS,
                                         train_weightings = V3_TRAIN_WEIGHTINGS,
                                         eval_weightings = V3_EVAL_WEIGHTINGS) {
  expected_model <- expand.grid(Design = designs, Route = routes, Model = setdiff(models, "Null"),
    TrainWeighting = train_weightings, EvalWeighting = eval_weightings, stringsAsFactors = FALSE)
  expected_model$Scope <- "design"; expected_model$Family <- "model_vs_null"; expected_model$Reference <- "Null"
  expected_training <- expand.grid(Design = designs, Route = routes, Model = models,
    EvalWeighting = eval_weightings, stringsAsFactors = FALSE)
  expected_training$Scope <- "design"; expected_training$Family <- "training_method"
  expected_training$ModelA <- "species_equal"; expected_training$ModelB <- "record_equal"
  if (!all(c("record_equal", "species_equal") %in% train_weightings)) expected_training <- expected_training[FALSE, , drop = FALSE]
  for (name in c("model_table", "training_table")) {
    table <- get(name)
    if (!"Fold" %in% names(table) || any(!is.na(table$Fold))) stop("Design-level comparison requires inactive Fold=NA: ", name)
  }
  audit_compare_table_v3(model_table, expected_model, names(expected_model), "model_vs_null_grid")
  audit_compare_table_v3(training_table, expected_training, names(expected_training), "training_method_grid")
  invisible(c(model_vs_null = nrow(expected_model), training_method = nrow(expected_training)))
}

verify_comparison_outputs_v3 <- function(evidence, model_table, training_table,
                                         designs = V3_DESIGNS, routes = V3_ROUTES,
                                         models = V3_MODELS, train_weightings = V3_TRAIN_WEIGHTINGS,
                                         eval_weightings = V3_EVAL_WEIGHTINGS, tolerance = 1e-10) {
  counts <- validate_comparison_grid_v3(model_table, training_table, designs, routes, models,
    train_weightings, eval_weightings)
  model_expected <- do.call(rbind, lapply(eval_weightings, function(w) compare_evidence_models(evidence, w, "design")))
  training_expected <- do.call(rbind, lapply(eval_weightings, function(w) compare_training_methods(evidence, w, "design")))
  model_result <- audit_compare_table_v3(model_table, model_expected,
    c("Scope", "Design", "Route", "Model", "TrainWeighting", "EvalWeighting", "Family", "Reference"),
    "model_vs_null_recomputed", tolerance)
  training_result <- audit_compare_table_v3(training_table, training_expected,
    c("Scope", "Design", "Route", "Model", "EvalWeighting", "Family", "ModelA", "ModelB"),
    "training_method_recomputed", tolerance)
  data.frame(Check = c("model_vs_null_grid_and_recompute", "training_method_grid_and_recompute"),
    RowsChecked = as.integer(counts), ColumnsChecked = c(model_result$columns, training_result$columns),
    MaximumAbsoluteDifference = c(model_result$max_absolute_error, training_result$max_absolute_error),
    Status = "PASS", stringsAsFactors = FALSE)
}

# Both new section-7.3 tables are recomputed from already verified OOF evidence.
verify_quantitative_outputs_v32 <- function(evidence, bias_table, plot_table, tolerance = 1e-10) {
  expected <- quantitative_diagnostics_v32(evidence)
  summary_keys <- c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")
  bias <- audit_compare_table_v3(bias_table, expected$summary, summary_keys,
    "quantitative_bias_recomputed", tolerance)
  points <- audit_compare_table_v3(plot_table, expected$plot_source,
    c(summary_keys, "RecordID"), "quantitative_plot_source_recomputed", tolerance)
  data.frame(Check = c("quantitative_bias_recomputed", "quantitative_plot_source_recomputed"),
    RowsChecked = c(bias$rows, points$rows), ColumnsChecked = c(bias$columns, points$columns),
    MaximumAbsoluteDifference = c(bias$max_absolute_error, points$max_absolute_error),
    Status = "PASS", stringsAsFactors = FALSE)
}
