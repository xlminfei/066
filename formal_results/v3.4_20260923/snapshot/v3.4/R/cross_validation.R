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

validate_fold_tables_v3 <- function(state, fold_tables) {
  designs <- names(fold_tables)
  if (!is.list(fold_tables) || !length(fold_tables) || is.null(designs) ||
      anyNA(designs) || any(!nzchar(designs)) || anyDuplicated(designs) ||
      !setequal(designs, V3_DESIGNS)) {
    stop("Fold designs must match the complete configured design set")
  }
  for (design in V3_DESIGNS) {
    fset <- fold_tables[[design]]
    routes <- names(fset)
    if (!is.list(fset) || is.null(routes) || anyNA(routes) ||
        anyDuplicated(routes) || !setequal(routes, V3_ROUTES)) {
      stop("Fold routes must match binary and joint_bb exactly for ", design)
    }
    k <- V3_DESIGN_K[[design]]
    if (length(k) != 1L || !is.numeric(k) || !is.finite(k) || k < 1 || k != trunc(k)) {
      stop("Invalid configured fold count for ", design)
    }
    for (route in V3_ROUTES) {
      f <- fset[[route]]
      if (!is.data.frame(f) || anyDuplicated(names(f)) ||
          !all(c("Species", "Fold") %in% names(f))) {
        stop("Malformed fold table for ", design, "/", route)
      }
      species <- as.character(f$Species)
      active <- as.character(if (route == "binary") state$binary_species else state$joint_species)
      if (length(species) != nrow(f) || anyNA(species) || any(!nzchar(trimws(species))) ||
          anyDuplicated(species) || !setequal(species, active)) {
        stop("Fold species universe does not match route for ", design, "/", route)
      }
      ids <- f$Fold
      # Validate every row before unique()/sort() can hide missing values.
      if (!(is.integer(ids) || is.double(ids)) || is.object(ids) || !is.null(dim(ids)) ||
          length(ids) != nrow(f) || any(!is.finite(ids)) ||
          any(ids != trunc(ids) | ids < 1 | ids > k)) {
        stop("Fold IDs must be finite integers in 1..K for ", design, "/", route)
      }
      if (!setequal(unique(ids), seq_len(k))) stop("Fold IDs are incomplete for ", design, "/", route)
    }
  }
  invisible(TRUE)
}

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
  fit_state <- state
  if (design != "full") {
    fit_state$blueprints[[blueprint_key(route, model)]] <- make_design_blueprint(
      state$encoded, train_species, model, predictor_sites = V3_PREDICTOR_SITES)
  }
  if (route == "binary") {
    fit_binomial_model_v3(fit_state, model, train_species, train_weighting, path,
                          iter, warmup, chains, cores, seed, force)
  } else {
    fit_joint_model_v3(fit_state, model, train_species, train_weighting, path, stan_path,
                       iter, warmup, chains, cores, seed, force)
  }
}

summarize_cv_metrics_v3 <- function(evidence, fold_metrics) {
  keys <- unique(fold_metrics[, c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")])
  rows <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    k <- keys[i, , drop = FALSE]
    z <- fold_metrics[fold_metrics$Design == k$Design[[1L]] & fold_metrics$Route == k$Route[[1L]] &
                      fold_metrics$Model == k$Model[[1L]] & fold_metrics$TrainWeighting == k$TrainWeighting[[1L]] &
                      fold_metrics$EvalWeighting == k$EvalWeighting[[1L]], , drop = FALSE]
    e <- evidence[evidence$Design == k$Design[[1L]] & evidence$Route == k$Route[[1L]] &
                  evidence$Model == k$Model[[1L]] & evidence$TrainWeighting == k$TrainWeighting[[1L]], , drop = FALSE]
    row <- evaluate_evidence(e, k$EvalWeighting[[1L]], k$Route[[1L]])
    pooled_auc <- row$AUC[[1L]]
    if (k$Route[[1L]] == "binary") {
      if (any(!is.finite(z$AUC))) stop("AUC is missing for a binary fold in the formal summary")
      fold_mean_auc <- mean(z$AUC)
      row$AUC <- fold_mean_auc
      row$FoldMeanAUC <- fold_mean_auc
      row$PooledAUC <- pooled_auc
    } else {
      row$FoldMeanAUC <- NA_real_
      row$PooledAUC <- NA_real_
    }
    row$Design <- k$Design[[1L]]; row$Model <- k$Model[[1L]]
    row$TrainWeighting <- k$TrainWeighting[[1L]]; row$EvalWeighting <- k$EvalWeighting[[1L]]
    row$FoldCount <- length(unique(z$Fold))
    row$Aggregation <- if (k$Route[[1L]] == "binary") "full_design_records; AUC_is_unweighted_fold_mean_and_PooledAUC_is_record_evidence" else "full_design_records"
    desired <- c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting", "FoldCount", "RecordsUsed", "SpeciesUsed", "LogScoreRecordsUsed", "LogScoreSpeciesUsed", "PointSpeciesUsed", "PISpeciesUsed", "WeightSum", "ELPD", "MeanLogScore", "AUC", "PooledAUC", "FoldMeanAUC", "Brier", "MAE", "RMSE", "Bias", "PointRecords", "PICoverage", "MeanPIWidth", "PIRecords", "Aggregation")
    row <- row[, intersect(desired, names(row)), drop = FALSE]
    rows[[i]] <- row
  }
  ans <- do.call(rbind, rows); rownames(ans) <- NULL
  key_cols <- c("Design", "Route", "Model", "TrainWeighting", "EvalWeighting")
  if (anyDuplicated(ans[, key_cols, drop = FALSE])) stop("CV summary contains duplicate primary keys")
  ans
}

run_cv_v3 <- function(state, root, fold_tables, stan_path,
                      iter = V3_SAMPLING$iter, warmup = V3_SAMPLING$warmup,
                      chains = V3_SAMPLING$chains, cores = V3_SAMPLING$cores,
                      seed = V3_SEED, force = FALSE, models = V3_MODELS, train_weightings = V3_TRAIN_WEIGHTINGS, fit_function = fit_bundle_v3, diagnostic_gate = TRUE) {
  validate_fold_tables_v3(state, fold_tables)
  evidence_rows <- list(); metric_rows <- list(); weight_rows <- list(); j <- 0L; m <- 0L
  for (design in V3_DESIGNS) {
    folds <- fold_tables[[design]]
    for (route in V3_ROUTES) {
      active_species <- if (route == "binary") state$binary_species else state$joint_species
      f <- folds[[route]]
      for (model in models) for (train_weighting in train_weightings) {
        for (fold_id in sort(unique(f$Fold))) {
          held_species <- f$Species[f$Fold == fold_id]
          train_species <- setdiff(active_species, held_species)
          bundle <- fit_function(state, route, model, train_species, train_weighting, root,
                                  design, fold_id, stan_path, iter, warmup, chains, cores,
                                  seed + fold_id + match(model, V3_MODELS), force)
          if (diagnostic_gate && !identical(as.character(bundle$diagnostics$Status[[1L]]), "PASS")) {
            stop("Formal CV fit failed diagnostics: ", design, "/", route, "/", model,
                 "/", train_weighting, "/fold", fold_id)
          }
          held_rows <- which(state$observations$Species %in% held_species &
            if (route == "binary") !is.na(state$observations$High) else state$observations$Informative)
          scored <- if (route == "binary") binary_record_scores(bundle, state, held_rows) else
            joint_record_scores(bundle, state, held_rows)
          if (!nrow(scored)) stop("No held-out records for CV fit")
          fold_state <- state
          fold_state$blueprints[[blueprint_key(route, model)]] <- bundle$blueprint
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
          scored$RunPurpose <- if(diagnostic_gate)"formal" else "INTEGRATION_TEST_ONLY"
          evidence_rows[[j <- j + 1L]] <- scored
          active_rows <- state$observations$Species %in% train_species &
            if (route == "binary") !is.na(state$observations$High) else state$observations$Informative
          rec <- state$observations[active_rows, "Species", drop = FALSE]
          wf <- build_train_weights(rec, train_weighting)
          wf$Design <- design; wf$Route <- route; wf$Model <- model
          wf$TrainWeighting <- train_weighting; wf$Fold <- fold_id; wf$FitKey <- bundle$key; wf$Stage <- "cv"
          weight_rows[[length(weight_rows) + 1L]] <- wf
          for (eval_weighting in V3_EVAL_WEIGHTINGS) {
            r <- evaluate_evidence(scored, eval_weighting, route)
            r$Design <- design; r$Fold <- fold_id; r$Model <- model; r$TrainWeighting <- train_weighting
            desired <- c("Design", "Fold", "Route", "Model", "TrainWeighting", "EvalWeighting", "RecordsUsed", "SpeciesUsed", "LogScoreRecordsUsed", "LogScoreSpeciesUsed", "PointSpeciesUsed", "PISpeciesUsed", "WeightSum", "ELPD", "MeanLogScore", "AUC", "Brier", "MAE", "RMSE", "Bias", "PointRecords", "PICoverage", "MeanPIWidth", "PIRecords", "Aggregation")
            metric_rows[[m <- m + 1L]] <- r[, intersect(desired, names(r)), drop = FALSE]
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
  validate_cv_evidence_v3(state,evidence,fold_tables,models,train_weightings)
  summary <- summarize_cv_metrics_v3(evidence, fold_metrics)
  write_csv_atomic(summary, file.path(root, "results", "cv_metrics_summary.csv"))
  list(evidence = evidence, fold_metrics = fold_metrics, summary = summary, weights = weights)
}

validate_cv_evidence_v3 <- function(state,evidence,fold_tables,models=V3_MODELS,train_weightings=V3_TRAIN_WEIGHTINGS) {
  keys<-c("Design","Route","Model","TrainWeighting","RecordID")
  if(anyDuplicated(evidence[,keys]))stop("Duplicate CV evidence keys")
  expected_total<-0L
  for(design in names(fold_tables))for(route in V3_ROUTES)for(m in models)for(tw in train_weightings) {
    expected<-state$observations[state$observations$Species%in%fold_tables[[design]][[route]]$Species & if(route=="binary")!is.na(state$observations$High) else state$observations$Informative,,drop=FALSE]
    e<-evidence[evidence$Design==design&evidence$Route==route&evidence$Model==m&evidence$TrainWeighting==tw,,drop=FALSE]
    if(nrow(e)!=nrow(expected)||!setequal(e$RecordID,expected$RecordID))stop("CV record coverage mismatch")
    z<-expected[match(e$RecordID,expected$RecordID),];f<-fold_tables[[design]][[route]]
    if(any(e$Species!=z$Species)||any(e$Fold!=f$Fold[match(e$Species,f$Species)]))stop("CV species/fold mismatch")
    expected_total<-expected_total+nrow(expected)
  }
  if(nrow(evidence)!=expected_total)stop("Extra CV evidence rows")
  invisible(TRUE)
}
