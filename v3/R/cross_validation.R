make_species_folds_v3 <- function(species, k, seed) {
  species <- unique(as.character(species))
  if (length(species) < k) stop("Number of species is smaller than number of folds")
  set.seed(seed)
  data.frame(Species = species, Fold = sample(rep(seq_len(k), length.out = length(species))),
             stringsAsFactors = FALSE)
}

binary_fold_has_both <- function(state, folds) {
  vapply(sort(unique(folds$Fold)), function(k) {
    ss <- folds$Species[folds$Fold == k]
    z <- state$binary_counts[state$binary_counts$Species %in% ss & state$binary_counts$Trials > 0, , drop = FALSE]
    sum(z$HighCount) > 0 && sum(z$LowCount) > 0
  }, logical(1))
}

make_binary_folds_v3 <- function(state, k, seed, max_attempts = 200L) {
  for (attempt in 0:max_attempts) {
    folds <- make_species_folds_v3(state$binary_species, k, seed + attempt)
    if (all(binary_fold_has_both(state, folds))) {
      attr(folds, "seed_used") <- seed + attempt
      return(folds)
    }
  }
  stop("Could not construct a binary fold table with both classes in every fold")
}

make_joint_folds_v3 <- function(state, k, seed) make_species_folds_v3(state$joint_species, k, seed)

fit_path_v3 <- function(root, route, model, train_weighting, design = "full", fold = NULL) {
  tag <- if (design == "full") "full" else paste0(design, "_f", fold)
  file.path(root, "runs", "fits", paste(route, model, train_weighting, tag, sep = "__"), "fit.rds")
}

fit_bundle_v3 <- function(state, route, model, train_species, train_weighting, root,
                          design = "full", fold = NULL, stan_path,
                          iter = V3_SAMPLING$iter, warmup = V3_SAMPLING$warmup,
                          chains = V3_SAMPLING$chains, cores = V3_SAMPLING$cores,
                          seed = V3_SEED, force = FALSE) {
  path <- fit_path_v3(root, route, model, train_weighting, design, fold)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (route == "binary") {
    fit_binomial_model_v3(state, model, train_species, train_weighting, path,
                          iter, warmup, chains, cores, seed, force)
  } else {
    fit_joint_model_v3(state, model, train_species, train_weighting, path, stan_path,
                       iter, warmup, chains, cores, seed, force)
  }
}

run_cv_v3 <- function(state, root, fold_tables, stan_path,
                      iter = V3_SAMPLING$iter, warmup = V3_SAMPLING$warmup,
                      chains = V3_SAMPLING$chains, cores = V3_SAMPLING$cores,
                      seed = V3_SEED, force = FALSE) {
  evidence_rows <- list(); metric_rows <- list(); weight_rows <- list(); j <- 0L; m <- 0L
  for (design in names(fold_tables)) {
    folds <- fold_tables[[design]]
    for (route in V3_ROUTES) {
      active_species <- if (route == "binary") state$binary_species else state$joint_species
      f <- folds[[route]]
      if (!setequal(f$Species, active_species)) stop("Fold species universe does not match route")
      for (model in V3_MODELS) for (train_weighting in V3_TRAIN_WEIGHTINGS) {
        for (fold_id in sort(unique(f$Fold))) {
          held_species <- f$Species[f$Fold == fold_id]
          train_species <- setdiff(active_species, held_species)
          bundle <- fit_bundle_v3(state, route, model, train_species, train_weighting, root,
                                  design, fold_id, stan_path, iter, warmup, chains, cores,
                                  seed + fold_id + match(model, V3_MODELS), force)
          if (!identical(as.character(bundle$diagnostics$Status[[1L]]), "PASS")) {
            stop("Formal CV fit failed diagnostics: ", design, "/", route, "/", model,
                 "/", train_weighting, "/fold", fold_id)
          }
          held_rows <- which(state$observations$Species %in% held_species &
            if (route == "binary") !is.na(state$observations$High) else state$observations$Informative)
          scored <- if (route == "binary") binary_record_scores(bundle, state, held_rows) else
            joint_record_scores(bundle, state, held_rows)
          if (!nrow(scored)) stop("No held-out records for CV fit")
          fold_blueprint <- make_design_blueprint(state$encoded, train_species, model)
          fold_state <- state
          fold_key <- paste0(if (route == "joint_bb") "joint" else route, "_", model)
          fold_state$blueprints[[fold_key]] <- fold_blueprint
          fold_status <- assess_applicability(fold_state, model, route, training_species = train_species)
          fold_status <- fold_status[, c("Species", "ApplicabilityStatus", "WarningCodes",
                                         "AnyMissingInputSite", "AnyMissingPredictorSite",
                                         "UnseenEncodedCategory", "UnseenRawResidue",
                                         "CombinationSeenInTraining", "FixedEffectEstimable",
                                         "Site151OutsideTrainingDomain"), drop = FALSE]
          scored <- merge(scored, fold_status, by = "Species", all.x = TRUE, sort = FALSE)
          scored$Design <- design; scored$Fold <- fold_id; scored$Route <- route
          scored$Model <- model; scored$TrainWeighting <- train_weighting
          scored$FitKey <- bundle$key
          evidence_rows[[j <- j + 1L]] <- scored
          active_rows <- if (route == "binary") state$observations$Species %in% train_species &
            !is.na(state$observations$High) else state$observations$Species %in% train_species &
            state$observations$Informative
          rec <- state$observations[active_rows, c("Species"), drop = FALSE]
          wf <- build_train_weights(rec, train_weighting)
          wf$Design <- design; wf$Route <- route; wf$Model <- model
          wf$TrainWeighting <- train_weighting; wf$Fold <- fold_id; wf$FitKey <- bundle$key; wf$Stage <- "cv"
          weight_rows[[length(weight_rows) + 1L]] <- wf
          for (eval_weighting in V3_EVAL_WEIGHTINGS) {
            metric_rows[[m <- m + 1L]] <- cbind(
              data.frame(Design = design, Fold = fold_id, Route = route, Model = model,
                         TrainWeighting = train_weighting, stringsAsFactors = FALSE),
              evaluate_evidence(scored, eval_weighting, route))
          }
        }
      }
    }
  }
  evidence <- do.call(rbind, evidence_rows); rownames(evidence) <- NULL
  fold_metrics <- do.call(rbind, metric_rows); rownames(fold_metrics) <- NULL
  weights <- do.call(rbind, weight_rows); rownames(weights) <- NULL
  write_csv_atomic(evidence, file.path(root, "results", "cv_record_predictions.csv"))
  write_csv_atomic(fold_metrics, file.path(root, "results", "cv_fold_metrics.csv"))
  write_csv_atomic(weights, file.path(root, "results", "training_weights_cv.csv"))
  full_weights_path <- file.path(root, "results", "training_weights_full.csv")
  if (file.exists(full_weights_path)) {
    full_weights <- utils::read.csv(full_weights_path, stringsAsFactors = FALSE)
    all_names <- union(names(full_weights), names(weights))
    for (nm in setdiff(all_names, names(full_weights))) full_weights[[nm]] <- NA
    for (nm in setdiff(all_names, names(weights))) weights[[nm]] <- NA
    write_csv_atomic(rbind(full_weights[, all_names, drop = FALSE], weights[, all_names, drop = FALSE]),
                     file.path(root, "results", "training_weights.csv"))
  } else {
    write_csv_atomic(weights, file.path(root, "results", "training_weights.csv"))
  }
  summary_rows <- list(); q <- 0L
  keys <- unique(fold_metrics[, c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")])
  for (i in seq_len(nrow(keys))) {
    z <- fold_metrics[fold_metrics$Design == keys$Design[[i]] & fold_metrics$Route == keys$Route[[i]] &
                        fold_metrics$Model == keys$Model[[i]] & fold_metrics$TrainWeighting == keys$TrainWeighting[[i]] &
                        fold_metrics$EvalWeighting == keys$EvalWeighting[[i]], , drop = FALSE]
    e <- evidence[evidence$Design == keys$Design[[i]] & evidence$Route == keys$Route[[i]] &
                    evidence$Model == keys$Model[[i]] & evidence$TrainWeighting == keys$TrainWeighting[[i]], , drop = FALSE]
    row <- evaluate_evidence(e, keys$EvalWeighting[[i]], keys$Route[[i]])
    row <- cbind(data.frame(Design = keys$Design[[i]], stringsAsFactors = FALSE), row)
    row$AUC <- if (all(is.na(z$AUC))) NA_real_ else mean(z$AUC, na.rm = TRUE)
    row$Aggregation <- "all_fold_records_for_logscore_and_error; fold_mean_for_AUC"
    summary_rows[[q <- q + 1L]] <- row
  }
  summary <- do.call(rbind, summary_rows); rownames(summary) <- NULL
  write_csv_atomic(summary, file.path(root, "results", "cv_metrics_summary.csv"))
  list(evidence = evidence, fold_metrics = fold_metrics, summary = summary, weights = weights)
}
