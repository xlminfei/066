compare_evidence_models <- function(evidence, eval_weighting = "species_equal") {
  if (!nrow(evidence)) stop("No evidence to compare")
  out <- list(); j <- 0L
  groups <- unique(evidence[, c("Design", "Fold", "Route", "TrainWeighting")])
  for (g in seq_len(nrow(groups))) {
    z <- evidence[evidence$Design == groups$Design[[g]] & evidence$Fold == groups$Fold[[g]] &
                   evidence$Route == groups$Route[[g]] & evidence$TrainWeighting == groups$TrainWeighting[[g]], , drop = FALSE]
    models <- intersect(V3_MODELS, unique(z$Model))
    for (m in setdiff(models, "Null")) {
      for (ref in "Null") {
        a <- z[z$Model == m, c("RecordID", "Species", "LogPredictiveDensityRaw"), drop = FALSE]
        b <- z[z$Model == ref, c("RecordID", "Species", "LogPredictiveDensityRaw"), drop = FALSE]
        if (nrow(a) != nrow(b) || anyDuplicated(a$RecordID) || anyDuplicated(b$RecordID) ||
            !setequal(a$RecordID, b$RecordID)) stop("Model comparison keys are not paired")
        b <- b[match(a$RecordID, b$RecordID), , drop = FALSE]
        d <- a$LogPredictiveDensityRaw - b$LogPredictiveDensityRaw
        wf <- build_eval_weights(a[, "Species", drop = FALSE], eval_weighting)
        mean_d <- weighted_mean(d, wf$weight)
        se <- stats::sd(d) / sqrt(length(d))
        p_approx <- if (is.finite(se) && se > 0) 2 * stats::pnorm(-abs(mean_d / se)) else if (mean_d == 0) 1 else 0
        out[[j <- j + 1L]] <- data.frame(Design = groups$Design[[g]], Fold = groups$Fold[[g]],
          Route = groups$Route[[g]], TrainWeighting = groups$TrainWeighting[[g]],
          EvalWeighting = eval_weighting, Family = "model_vs_null", Model = m, Reference = ref,
          Difference = mean_d, SE_approx = se, P_approx = p_approx,
          RecordsUsed = length(d), SpeciesUsed = length(unique(a$Species)), stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(out)) return(data.frame())
  ans <- do.call(rbind, out)
  ans$P_BH <- ave(ans$P_approx, ans$Family, FUN = function(x) stats::p.adjust(x, method = "BH"))
  ans
}

compare_training_methods <- function(evidence, eval_weighting = "species_equal") {
  out <- list(); j <- 0L
  groups <- unique(evidence[, c("Design", "Fold", "Route", "Model")])
  for (g in seq_len(nrow(groups))) {
    z <- evidence[evidence$Design == groups$Design[[g]] & evidence$Fold == groups$Fold[[g]] &
                   evidence$Route == groups$Route[[g]] & evidence$Model == groups$Model[[g]], , drop = FALSE]
    if (!all(c("record_equal", "species_equal") %in% z$TrainWeighting)) next
    a <- z[z$TrainWeighting == "species_equal", c("RecordID", "Species", "LogPredictiveDensityRaw"), drop = FALSE]
    b <- z[z$TrainWeighting == "record_equal", c("RecordID", "Species", "LogPredictiveDensityRaw"), drop = FALSE]
    if (!setequal(a$RecordID, b$RecordID) || anyDuplicated(a$RecordID) || anyDuplicated(b$RecordID)) {
      stop("Training comparison keys are not paired")
    }
    b <- b[match(a$RecordID, b$RecordID), , drop = FALSE]
    d <- a$LogPredictiveDensityRaw - b$LogPredictiveDensityRaw
    wf <- build_eval_weights(a[, "Species", drop = FALSE], eval_weighting)
    mean_d <- weighted_mean(d, wf$weight); se <- stats::sd(d) / sqrt(length(d))
    p_approx <- if (is.finite(se) && se > 0) 2 * stats::pnorm(-abs(mean_d / se)) else if (mean_d == 0) 1 else 0
    out[[j <- j + 1L]] <- data.frame(Design = groups$Design[[g]], Fold = groups$Fold[[g]],
      Route = groups$Route[[g]], Model = groups$Model[[g]],
      EvalWeighting = eval_weighting, Family = "training_method", ModelA = "species_equal",
      ModelB = "record_equal", Difference = mean_d, SE_approx = se,
      P_approx = p_approx, RecordsUsed = length(d),
      SpeciesUsed = length(unique(a$Species)), stringsAsFactors = FALSE)
  }
  if (!length(out)) return(data.frame())
  ans <- do.call(rbind, out)
  ans$P_BH <- ave(ans$P_approx, ans$Family, FUN = function(x) stats::p.adjust(x, method = "BH"))
  ans
}

make_roc_outputs <- function(evidence, output_dir) {
  z <- evidence[evidence$Route == "binary", , drop = FALSE]
  out <- list(); j <- 0L
  for (eval_weighting in V3_EVAL_WEIGHTINGS) {
    for (design in unique(z$Design)) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
      for (fold in sort(unique(z$Fold[z$Design == design]))) {
        q <- z[z$Design == design & z$Model == model & z$TrainWeighting == tw & z$Fold == fold, , drop = FALSE]
        q <- q[!is.na(q$ObservedHigh), , drop = FALSE]
        if (!nrow(q)) next
        w <- build_eval_weights(q[, "Species", drop = FALSE], eval_weighting)
        crd <- roc_coordinates(q$ObservedHigh, q$PredictedPrHigh, w$weight)
        crd$EvalWeighting <- eval_weighting; crd$Design <- design; crd$Model <- model
        crd$TrainWeighting <- tw; crd$Fold <- fold; crd$AUC <- weighted_auc(q$ObservedHigh, q$PredictedPrHigh, w$weight)
        out[[j <- j + 1L]] <- crd
      }
    }
  }
  ans <- if (length(out)) do.call(rbind, out) else data.frame()
  write_csv_atomic(ans, file.path(output_dir, "roc_coordinates.csv"))
  ans
}
