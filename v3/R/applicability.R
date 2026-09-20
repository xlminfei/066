applicability_status <- function(has_response = FALSE, missing_predictor = FALSE,
                                 unseen_category = FALSE, unseen_combination = FALSE,
                                 fixed_effect_estimable = TRUE,
                                 site151_outside_domain = FALSE,
                                 unseen_raw_residue = FALSE) {
  codes <- character()
  if (isTRUE(missing_predictor)) codes <- c(codes, "missing_predictor")
  if (isTRUE(unseen_category)) codes <- c(codes, "unseen_category")
  if (isTRUE(unseen_raw_residue)) codes <- c(codes, "unseen_raw_residue")
  if (isTRUE(unseen_combination)) codes <- c(codes, "unseen_combination")
  if (!isTRUE(fixed_effect_estimable)) codes <- c(codes, "fixed_effect_not_estimable")
  if (isTRUE(site151_outside_domain)) codes <- c(codes, "site151_outside_training_domain")
  status <- if (!isTRUE(has_response)) "unlabelled_projection" else if (length(codes)) "review_required" else "supported"
  list(ApplicabilityStatus = status, WarningCodes = codes)
}

assess_applicability <- function(state, model, route = "joint_bb", training_species = NULL) {
  blueprint_route <- if (route == "joint_bb") "joint" else route
  bp <- state$blueprints[[paste0(blueprint_route, "_", model)]]
  if (is.null(bp)) stop("Blueprint not found")
  encoded <- state$encoded
  response <- training_species %||% if (route == "binary") state$binary_species else state$joint_species
  vars <- bp$variables
  rows <- vector("list", nrow(encoded))
  for (i in seq_len(nrow(encoded))) {
    vals <- if (length(vars)) encoded[i, vars, drop = FALSE] else encoded[i, , drop = FALSE]
    raw_all <- setNames(vapply(V3_SITE_COLUMNS, function(site) normalize_residue(state$sites[[site]][[i]]), character(1)), V3_SITE_COLUMNS)
    missing_input <- any(raw_all == "MISSING")
    missing_pred <- length(vars) > 0 && any(vapply(vals, function(x) identical(as.character(x), "MISSING"), logical(1)))
    unseen_cat <- length(vars) > 0 && any(vapply(seq_along(vars), function(j) {
      site <- sub(paste0("^", model, "_"), "", vars[[j]])
      !as.character(encoded[[vars[[j]]]][i]) %in% bp$seen[[site]]
    }, logical(1)))
    unseen_raw <- length(vars) > 0 && any(vapply(sub(paste0("^", model, "_"), "", vars), function(site) {
      !raw_all[[site]] %in% bp$raw_seen[[site]]
    }, logical(1)))
    combo <- if (length(vars)) do.call(paste, c(encoded[i, vars, drop = FALSE], sep = "|")) else "(intercept-only)"
    unseen_combo <- !combo %in% bp$training_combinations
    row_x <- design_from_blueprint(encoded[i, , drop = FALSE], bp)
    fixed_est <- row_in_span(bp$train_matrix, c(1, row_x))
    codes <- applicability_status(
      has_response = encoded$Species[[i]] %in% response,
      missing_predictor = missing_pred,
      unseen_category = unseen_cat,
      unseen_raw_residue = unseen_raw,
      unseen_combination = unseen_combo,
      fixed_effect_estimable = fixed_est,
      site151_outside_domain = normalize_residue(state$sites$Site151[[i]]) != "C"
    )
    rows[[i]] <- data.frame(Species = encoded$Species[[i]], Model = model, Route = route,
      HasResponseData = encoded$Species[[i]] %in% response,
      AnyMissingPredictorSite = missing_pred, UnseenEncodedCategory = unseen_cat,
      AnyMissingInputSite = missing_input, UnseenRawResidue = unseen_raw,
      CombinationSeenInTraining = !unseen_combo,
      FixedEffectEstimable = fixed_est,
      Site151OutsideTrainingDomain = normalize_residue(state$sites$Site151[[i]]) != "C",
      ApplicabilityStatus = codes$ApplicabilityStatus,
      WarningCodes = paste(codes$WarningCodes, collapse = ";"), stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}
