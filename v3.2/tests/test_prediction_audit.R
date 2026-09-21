# Deterministic audit regression tests. All inputs and posterior draws below are
# synthetic fixtures; this file starts no sampler and uses no research records.
if (!exists("audit_cv_bundle_predictions_v3", mode = "function")) {
  source(file.path(root, "R", "prediction_audit.R"))
}
checks <- list()
check <- function(name, value) {
  result <- tryCatch(isTRUE(force(value)), error = function(e) { cat("ERROR", name, conditionMessage(e), "\n"); FALSE })
  checks[[name]] <<- result
  cat(if (result) "PASS " else "FAIL ", name, "\n", sep = "")
}
assert_error <- function(name, expr) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  check(name, inherits(error, "error"))
}

panel <- data.frame(Species = paste0("audit_species_", 1:6), Site3 = rep(c("C", "R"), 3),
  Site20 = c("K", "K", "R", "K", "T", "K"), Site117 = "K", Site151 = "C", Site196 = "C",
  Site315 = rep(c("K", "T", "R"), 2), stringsAsFactors = FALSE)
observations <- do.call(rbind, lapply(seq_len(nrow(panel)), function(i) {
  data.frame(RecordID = paste0("audit_", i, "_", 1:6), ExperimentID = paste0("experiment_", i, "_", 1:6),
    SourceID = "synthetic_audit_fixture", Species = panel$Species[i],
    Type = c("count", "count", "exact", "exact", "interval", "interval"),
    Events = c(1L, 8L, NA, NA, NA, NA), Total = c(5L, 10L, NA, NA, NA, NA),
    Exact = c(NA, NA, .3, 1, NA, NA), Lower = c(NA, NA, NA, NA, .1, .4),
    Upper = c(NA, NA, NA, NA, .4, .7), stringsAsFactors = FALSE)
}))
classified <- classify_high_low(observations)
observations <- cbind(observations, classified)
dictionary <- build_encoding_dictionary(panel)
encoded <- encode_panel(panel, dictionary)$data
state <- list(sites = panel, encoded = encoded, dictionary = dictionary, observations = observations,
  blueprints = list(), binary_species = panel$Species, joint_species = panel$Species)
train <- panel$Species[1:4]
D <- 48L
bundles <- list()
for (route in V3_ROUTES) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
  bp <- make_design_blueprint(encoded, train, model)
  pars <- list(alpha = seq(-.55, .6, length.out = D),
    beta = matrix(if (length(bp$columns)) seq(-.2, .25, length.out = D * length(bp$columns)) else numeric(),
      nrow = D, ncol = length(bp$columns)))
  if (route == "joint_bb") pars <- c(pars, list(rho = seq(.08, .3, length.out = D),
    log_phi_count = rep(log(10), D), log_phi_ratio = rep(log(16), D)))
  b <- list(route = route, model = model, train_weighting = tw, train_species = train,
    blueprint = bp, posterior = pars, key = paste("synthetic", route, model, tw, sep = "__"))
  bundles[[paste(route, model, tw, sep = "|")]] <- b
}

# Joint oracle uses production predictive draws and direct, elementary R density
# formulas in a moderate-parameter fixture, independently of the new audit scorer.
reference_joint <- function(bundle, held_rows) {
  obs <- state$observations[held_rows, , drop = FALSE]
  m <- joint_expected_draws(bundle, state, obs$Species); pars <- bundle$posterior
  replicated <- joint_record_predictive_draws(bundle, state, held_rows, V3_SEED + sum(held_rows))
  q <- posterior_quantiles(replicated)
  point <- rep(NA_real_, nrow(obs)); count <- obs$Type == "count"; exact <- obs$Type == "exact"; interval <- obs$Type == "interval"
  point[count] <- obs$Events[count] / obs$Total[count]; point[exact] <- obs$Exact[exact]
  ll <- vapply(seq_len(nrow(obs)), function(i) {
    mu <- m[, i]; phi_count <- exp(pars$log_phi_count)
    if (obs$Type[i] == "count") {
      draws <- lchoose(obs$Total[i], obs$Events[i]) + lbeta(obs$Events[i] + phi_count * mu,
        obs$Total[i] - obs$Events[i] + phi_count * (1 - mu)) - lbeta(phi_count * mu, phi_count * (1 - mu))
    } else {
      atom <- pars$rho * mu; internal <- mu * (1 - pars$rho) / (1 - atom)
      a <- exp(pars$log_phi_ratio) * internal; b <- exp(pars$log_phi_ratio) * (1 - internal)
      if (obs$Type[i] == "exact") draws <- if (obs$Exact[i] == 1) log(atom) else log1p(-atom) + dbeta(obs$Exact[i], a, b, log = TRUE)
      else draws <- log1p(-atom) + log(pbeta(obs$Upper[i], a, b) - pbeta(obs$Lower[i], a, b))
    }
    log_mean_exp(draws)
  }, numeric(1))
  covered <- overlap <- rep(NA, nrow(obs))
  covered[!interval] <- point[!interval] >= q[1, !interval] & point[!interval] <= q[3, !interval]
  overlap[interval] <- obs$Upper[interval] >= q[1, interval] & obs$Lower[interval] <= q[3, interval]
  data.frame(RecordID = obs$RecordID, ExperimentID = obs$ExperimentID, SourceID = obs$SourceID,
    Species = obs$Species, Type = obs$Type, ObservedHigh = obs$High, ObservedPoint = point,
    PredictedPrHigh = NA_real_, PredictedPoint = colMeans(m), PredictedPI_lower = q[1, ], PredictedPI_upper = q[3, ],
    PIWidth = q[3, ] - q[1, ], IntervalCovered = covered, IntervalOverlap = overlap,
    PIObservationModel = ifelse(count, "beta_binomial_at_observed_Total", "one_inflated_beta_report"),
    LogPredictiveDensityRaw = ll, OriginalRow = held_rows)
}

evidence <- list(); receipts <- list(); contexts <- list(); rows_by_route <- list()
for (route in V3_ROUTES) {
  held_rows <- which(state$observations$Species %in% panel$Species[5:6] &
    if (route == "binary") !is.na(state$observations$High) else state$observations$Informative)
  rows_by_route[[route]] <- held_rows
  for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
    key <- paste(route, model, tw, sep = "|"); b <- bundles[[key]]
    z <- if (route == "binary") binary_record_scores(b, state, held_rows) else reference_joint(b, held_rows)
    ss <- state; ss$blueprints[[blueprint_key(route, model)]] <- b$blueprint
    status <- assess_applicability(ss, model, route, training_species = train)
    status_fields <- c("ApplicabilityStatus", "WarningCodes", "AnyMissingInputSite", "AnyMissingPredictorSite",
      "UnseenEncodedCategory", "UnseenRawResidue", "CombinationSeenInTraining", "FixedEffectEstimable", "Site151OutsideTrainingDomain")
    z <- cbind(z, status[match(z$Species, status$Species), status_fields, drop = FALSE])
    z$Design <- "fivefold"; z$Fold <- 1L; z$Route <- route; z$Model <- model; z$TrainWeighting <- tw
    z$FitKey <- b$key; z$RunPurpose <- "SYNTHETIC_AUDIT_FIXTURE"
    context <- data.frame(Design = "fivefold", Fold = 1L, Route = route, Model = model,
      TrainWeighting = tw, RunPurpose = "SYNTHETIC_AUDIT_FIXTURE", stringsAsFactors = FALSE)
    contexts[[key]] <- context
    r <- audit_cv_bundle_predictions_v3(b, state, held_rows, z[nrow(z):1, ], context, allow_fixture = TRUE)
    receipts[[length(receipts) + 1L]] <- r
    evidence[[length(evidence) + 1L]] <- z
  }
}
receipts <- do.call(rbind, receipts); evidence <- do.call(rbind, evidence); rownames(evidence) <- NULL
check("16 synthetic posterior strata and all three record types recompute", nrow(receipts) == 48L && all(receipts$Status == "PASS"))
check("OOF audit covers every held-out row without sampling", sum(receipts$RowsChecked) == nrow(evidence))
check("R independent raw likelihood matches moderate oracle", max(receipts$MaximumAbsoluteDifference) < 1e-10)

key <- "joint_bb|M1|species_equal"; b <- bundles[[key]]; context <- contexts[[key]]
z <- subset(evidence, Route == "joint_bb" & Model == "M1" & TrainWeighting == "species_equal")
bad <- z; bad$PredictedPoint[1L] <- bad$PredictedPoint[1L] + .05
# Recomputing downstream metrics from the same wrong OOF table succeeds, whereas
# anchoring its values to posterior draws must reject the wrong primitive.
check("tampered OOF can still produce internally consistent downstream metrics", is.data.frame(evaluate_evidence(bad, "species_equal", "joint_bb")))
assert_error("OOF corruption is caught even if downstream metrics were regenerated", audit_cv_bundle_predictions_v3(
  b, state, rows_by_route$joint_bb, bad, context, allow_fixture = TRUE))
bad <- z; bad$LogPredictiveDensityRaw[1L] <- bad$LogPredictiveDensityRaw[1L] + .1
assert_error("raw log-score tampering fails posterior audit", audit_cv_bundle_predictions_v3(b, state, rows_by_route$joint_bb, bad, context, allow_fixture = TRUE))
bad <- z; bad$PredictedPrHigh[1L] <- .5
assert_error("inactive joint probability must remain NA", audit_cv_bundle_predictions_v3(b, state, rows_by_route$joint_bb, bad, context, allow_fixture = TRUE))
bad <- z; bad$ObservedPoint[bad$Type == "interval"] <- .5
assert_error("interval observations cannot become pseudo point targets", audit_cv_bundle_predictions_v3(b, state, rows_by_route$joint_bb, bad, context, allow_fixture = TRUE))
bad <- z; bad$PIObservationModel[1L] <- "one_inflated_beta_report"
assert_error("count predictive distribution label cannot be changed", audit_cv_bundle_predictions_v3(b, state, rows_by_route$joint_bb, bad, context, allow_fixture = TRUE))
bad <- z; bad$RecordID[1L] <- bad$RecordID[2L]
assert_error("duplicate OOF records are rejected", audit_cv_bundle_predictions_v3(b, state, rows_by_route$joint_bb, bad, context, allow_fixture = TRUE))
assert_error("fixture posterior cannot pass without explicit fixture opt-in", audit_cv_bundle_predictions_v3(b, state, rows_by_route$joint_bb, z, context))
bad_state <- state; bad_state$encoded$M1_Site3[1L] <- "MISSING"
assert_error("stale encoded state is rejected", audit_cv_bundle_predictions_v3(b, bad_state, rows_by_route$joint_bb, z, context, allow_fixture = TRUE))

full <- external_prediction_table(state, bundles, state$sites)
full_receipts <- list()
for (key in names(bundles)) {
  b <- bundles[[key]]; context <- contexts[[key]]; context$Design <- "full"; context$Fold <- NA_integer_
  z <- subset(full, Route == b$route & Model == b$model & TrainWeighting == b$train_weighting)
  full_receipts[[length(full_receipts) + 1L]] <- audit_full_bundle_predictions_v3(b, state, z[nrow(z):1, ], context, allow_fixture = TRUE)
}
full_receipts <- do.call(rbind, full_receipts)
check("every panel row is recomputed for every route/model/training fixture", sum(full_receipts$RowsChecked) == 96L && all(full_receipts$Status == "PASS"))
b <- bundles[["joint_bb|M1|species_equal"]]; context <- contexts[["joint_bb|M1|species_equal"]]
z <- subset(full, Route == "joint_bb" & Model == "M1" & TrainWeighting == "species_equal")
bad <- z; bad$Point[1L] <- bad$Point[1L] + .05
assert_error("wrong full-panel posterior mean is rejected", audit_full_bundle_predictions_v3(b, state, bad, context, allow_fixture = TRUE))
bad <- z; bad$PI_lower[1L] <- bad$PI_lower[1L] + .01
assert_error("wrong full-panel predictive interval is rejected", audit_full_bundle_predictions_v3(b, state, bad, context, allow_fixture = TRUE))
bad <- z; bad$Species[1L] <- bad$Species[2L]
assert_error("duplicated full-panel species is rejected", audit_full_bundle_predictions_v3(b, state, bad, context, allow_fixture = TRUE))

model_table <- do.call(rbind, lapply(V3_EVAL_WEIGHTINGS, function(w) compare_evidence_models(evidence, w)))
training_table <- do.call(rbind, lapply(V3_EVAL_WEIGHTINGS, function(w) compare_training_methods(evidence, w)))
comparison_receipts <- verify_comparison_outputs_v3(evidence, model_table, training_table, designs = "fivefold")
check("small-grid model/training comparisons include exact keys and recomputed values", identical(comparison_receipts$RowsChecked, c(24L, 16L)))
assert_error("missing model comparison key is rejected", validate_comparison_grid_v3(model_table[-1L, ], training_table, designs = "fivefold"))
assert_error("duplicated training comparison key is rejected", validate_comparison_grid_v3(model_table, rbind(training_table, training_table[1L, ]), designs = "fivefold"))
bad <- training_table; bad$ModelA[1L] <- "record_equal"
assert_error("reversed/incorrect comparison identity is rejected", validate_comparison_grid_v3(model_table, bad, designs = "fivefold"))
bad <- model_table; bad$Difference[1L] <- bad$Difference[1L] + .1
assert_error("comparison value tampering is rejected after grid validation", verify_comparison_outputs_v3(evidence, bad, training_table, designs = "fivefold"))
# Full production identity universe is 48 + 32 design-level comparisons.
second <- evidence; second$Design <- "tenfold"; all_designs <- rbind(evidence, second)
models_full <- do.call(rbind, lapply(V3_EVAL_WEIGHTINGS, function(w) compare_evidence_models(all_designs, w)))
training_full <- do.call(rbind, lapply(V3_EVAL_WEIGHTINGS, function(w) compare_training_methods(all_designs, w)))
check("formal comparison universe is 48 plus 32 without fitting", identical(unname(validate_comparison_grid_v3(models_full, training_full)), c(48L, 32L)))

upper_ref <- 100 * log(.6) + log1p(-exp(100 * (log(.5) - log(.6))))
lower_ref <- 200 * log(.7) + log1p(-exp(200 * (log(.6) - log(.7))))
check("independent R likelihood handles the old upper-tail counterexample", abs(audit_log_beta_interval_v3(.4, .5, 1, 100) - upper_ref) < 1e-11)
check("independent R likelihood handles the old lower-tail counterexample", abs(audit_log_beta_interval_v3(.6, .7, 200, 1) - lower_ref) < 1e-11)
check("fraction-scale quadrature resolves a 1e-12 uniform interval", abs(audit_log_beta_interval_v3(.45, .45 + 1e-12, 1, 1) - log((.45 + 1e-12) - .45)) < 1e-11)

# Numeric/logical NA masks survive CSV roundtrip; integer/double and row names do
# not trigger false failures, while missing a newly added metric field does.
roundtrip <- tempfile(fileext = ".csv"); write_csv_atomic(model_table, roundtrip)
loaded <- read.csv(roundtrip, stringsAsFactors = FALSE)
check("comparison roundtrip tolerates benign CSV type differences", is.data.frame(verify_comparison_outputs_v3(evidence,
  loaded[nrow(loaded):1, ], training_table, designs = "fivefold")))
target <- data.frame(Key = "k", AddedMetric = .12, Inactive = NA_real_)
bad_target <- target; bad_target$Inactive <- NaN
assert_error("NaN cannot masquerade as an inactive NA", audit_compare_table_v3(bad_target, target, "Key"))
assert_error("newly required numeric fields cannot silently disappear", audit_compare_table_v3(target[, c("Key", "Inactive")], target, "Key"))

qd <- quantitative_diagnostics_v32(evidence)
quantitative_receipts <- verify_quantitative_outputs_v32(evidence, qd$summary, qd$plot_source)
check("quantitative summaries and sources recompute under shuffled keys", all(verify_quantitative_outputs_v32(evidence,
  qd$summary[nrow(qd$summary):1, ], qd$plot_source[nrow(qd$plot_source):1, ])$Status == "PASS"))
bad <- qd$summary; bad$Bias[1L] <- bad$Bias[1L] + .1
assert_error("quantitative Bias tampering is rejected", verify_quantitative_outputs_v32(evidence, bad, qd$plot_source))
bad <- qd$plot_source; bad$EvaluationWeight[1L] <- bad$EvaluationWeight[1L] + .1
assert_error("plot EvaluationWeight tampering is rejected", verify_quantitative_outputs_v32(evidence, qd$summary, bad))
bad <- qd$plot_source; bad$SignedError[1L] <- bad$SignedError[1L] + .1
assert_error("plot SignedError tampering is rejected", verify_quantitative_outputs_v32(evidence, qd$summary, bad))
bad <- qd$summary; bad$PointSpeciesUsed[1L] <- bad$PointSpeciesUsed[1L] + 1L
assert_error("quantitative support-count tampering is rejected", verify_quantitative_outputs_v32(evidence, bad, qd$plot_source))
assert_error("missing quantitative plot key is rejected", verify_quantitative_outputs_v32(evidence, qd$summary, qd$plot_source[-1L, ]))
bad <- qd$summary; bad$Bias <- NULL
assert_error("missing required Bias field is rejected", verify_quantitative_outputs_v32(evidence, bad, qd$plot_source))

out <- file.path(root, "review", "audit_deterministic")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
write_csv_atomic(data.frame(Test = names(checks), Pass = unlist(checks), row.names = NULL), file.path(out, "assertions.csv"))
write_csv_atomic(receipts, file.path(out, "posterior_to_OOF_receipts.csv"))
write_csv_atomic(full_receipts, file.path(out, "posterior_to_full_panel_receipts.csv"))
write_csv_atomic(comparison_receipts, file.path(out, "comparison_receipts.csv"))
write_csv_atomic(quantitative_receipts, file.path(out, "quantitative_receipts.csv"))
write_json_atomic(list(status = if (all(unlist(checks))) "PASS_SYNTHETIC_ONLY" else "FAIL", assertions = length(checks),
  samplers_started = 0L, research_data_fits = 0L, coverage = "synthetic parameter fixtures; 16 CV strata; 16 full-panel strata; negative tampering tests"),
  file.path(out, "audit_test_status.json"))
if (!all(unlist(checks))) stop("prediction audit regressions failed: ", paste(names(checks)[!unlist(checks)], collapse = "; "))
cat("PREDICTION_AUDIT_PASS: synthetic fixtures and tampering negatives only; no research fits\n")
