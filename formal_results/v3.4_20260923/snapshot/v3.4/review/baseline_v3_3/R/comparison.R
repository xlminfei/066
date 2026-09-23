pair_log_score_rows <- function(a, b) {
  required <- c("RecordID", "Species", "LogPredictiveDensityRaw")
  if (!all(required %in% names(a)) || !all(required %in% names(b))) stop("Model comparison evidence lacks pairing columns")
  if (nrow(a) != nrow(b) || anyDuplicated(a$RecordID) || anyDuplicated(b$RecordID) ||
      !setequal(a$RecordID, b$RecordID)) stop("Model comparison keys are not paired")
  b <- b[match(a$RecordID, b$RecordID), , drop = FALSE]
  for(n in intersect(c("Fold","Type","ObservedHigh","ObservedPoint","OriginalRow"),intersect(names(a),names(b)))) if(!identical(a[[n]],b[[n]]))stop("Paired record mismatch: ",n)
  if (any(as.character(a$Species) != as.character(b$Species))) stop("Paired records have different species")
  if (any(!is.finite(a$LogPredictiveDensityRaw)) || any(!is.finite(b$LogPredictiveDensityRaw))) {
    stop("Model comparison contains non-finite log scores")
  }
  data.frame(RecordID = a$RecordID, Species = a$Species,
             Difference = a$LogPredictiveDensityRaw - b$LogPredictiveDensityRaw,
             stringsAsFactors = FALSE)
}

cluster_bootstrap_difference <- function(d,eval_weighting,seed,B=V3_COMPARISON_BOOTSTRAP) {
  ss<-sort(unique(as.character(d$Species)));S<-length(ss)
  sums<-vapply(ss,function(sp)sum(d$Difference[d$Species==sp]),numeric(1));nn<-vapply(ss,function(sp)sum(d$Species==sp),integer(1))
  means<-sums/nn;point<-if(eval_weighting=="species_equal")mean(means) else sum(sums)/sum(nn)
  if(S<2||B<2)return(list(mean=point,se=NA_real_,lower=NA_real_,upper=NA_real_,p=NA_real_,status="INSUFFICIENT_SPECIES"))
  set.seed(seed);ix<-matrix(sample.int(S,S*B,replace=TRUE),nrow=S)
  boot<-if(eval_weighting=="species_equal")colMeans(matrix(means[ix],S)) else colSums(matrix(sums[ix],S))/colSums(matrix(nn[ix],S))
  se<-sd(boot);status<-if(se<=sqrt(.Machine$double.eps))"DEGENERATE_BOOTSTRAP" else if(S<10)"LIMITED_SPECIES" else "CONDITIONAL_OOF_APPROXIMATION"
  list(mean=point,se=se,lower=unname(quantile(boot,.025)),upper=unname(quantile(boot,.975)),p=if(status=="CONDITIONAL_OOF_APPROXIMATION")2*pnorm(-abs(point/se)) else NA_real_,status=status)
}

add_comparison_adjustment <- function(ans) {
  if (!nrow(ans)) return(ans)
  g <- interaction(ans$Family, ans$Scope, ans$EvalWeighting, ans$Route, ans$Design, drop = TRUE)
  ans$P_BH <- ave(ans$P_approx, g, FUN = function(x) stats::p.adjust(x, method = "BH"))
  ans
}

compare_evidence_models <- function(evidence, eval_weighting = "species_equal", scope = "design") {
  if (!nrow(evidence)) stop("No evidence to compare")
  if (!scope %in% c("design", "fold")) stop("scope must be design or fold")
  group_cols <- c("Design", "Route", "TrainWeighting", if (scope == "fold") "Fold")
  groups <- unique(evidence[, group_cols, drop = FALSE])
  out <- list(); j <- 0L
  for (g in seq_len(nrow(groups))) {
    z <- evidence
    for (nm in group_cols) z <- z[z[[nm]] == groups[[nm]][[g]], , drop = FALSE]
    models <- intersect(V3_MODELS, unique(z$Model))
    for (m in setdiff(models, "Null")) {
      a <- z[z$Model == m, , drop = FALSE]
      b <- z[z$Model == "Null", , drop = FALSE]
      d <- pair_log_score_rows(a, b)
      stat <- cluster_bootstrap_difference(d, eval_weighting, V3_SEED + match(groups$Design[[g]],V3_DESIGNS)*100L + match(groups$Route[[g]],V3_ROUTES))
      out[[j <- j + 1L]] <- data.frame(Scope = scope, Design = groups$Design[[g]],
        Fold = if (scope == "fold") groups$Fold[[g]] else NA_integer_, Route = groups$Route[[g]],
        TrainWeighting = groups$TrainWeighting[[g]], EvalWeighting = eval_weighting,
        Family = "model_vs_null", Model = m, Reference = "Null", Difference = stat$mean,
        SE_approx = stat$se, CI95_lower = stat$lower, CI95_upper = stat$upper,
        Z_approx = if (is.finite(stat$se) && stat$se > 0) stat$mean / stat$se else NA_real_,
        P_approx = if(scope=="design")stat$p else NA_real_, IntervalStatus=stat$status, UncertaintyScope="fixed_OOF_predictions_species_bootstrap_no_refitting", RecordsUsed = nrow(d), SpeciesUsed = length(unique(d$Species)),
        BootstrapReplicates = V3_COMPARISON_BOOTSTRAP, stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(data.frame())
  add_comparison_adjustment(do.call(rbind, out))
}

compare_training_methods <- function(evidence, eval_weighting = "species_equal", scope = "design") {
  if (!nrow(evidence)) stop("No evidence to compare")
  if (!scope %in% c("design", "fold")) stop("scope must be design or fold")
  group_cols <- c("Design", "Route", "Model", if (scope == "fold") "Fold")
  groups <- unique(evidence[, group_cols, drop = FALSE])
  out <- list(); j <- 0L
  for (g in seq_len(nrow(groups))) {
    z <- evidence
    for (nm in group_cols) z <- z[z[[nm]] == groups[[nm]][[g]], , drop = FALSE]
    a <- z[z$TrainWeighting == "species_equal", , drop = FALSE]
    b <- z[z$TrainWeighting == "record_equal", , drop = FALSE]
    if (!nrow(a) || !nrow(b)) next
    d <- pair_log_score_rows(a, b)
    stat <- cluster_bootstrap_difference(d, eval_weighting, V3_SEED + match(groups$Design[[g]],V3_DESIGNS)*100L + match(groups$Route[[g]],V3_ROUTES))
    out[[j <- j + 1L]] <- data.frame(Scope = scope, Design = groups$Design[[g]],
      Fold = if (scope == "fold") groups$Fold[[g]] else NA_integer_, Route = groups$Route[[g]],
      Model = groups$Model[[g]], EvalWeighting = eval_weighting,
      Family = "training_method", ModelA = "species_equal", ModelB = "record_equal",
      Difference = stat$mean, SE_approx = stat$se, CI95_lower = stat$lower, CI95_upper = stat$upper,
      Z_approx = if (is.finite(stat$se) && stat$se > 0) stat$mean / stat$se else NA_real_,
      P_approx = if(scope=="design")stat$p else NA_real_, IntervalStatus=stat$status, UncertaintyScope="fixed_OOF_predictions_species_bootstrap_no_refitting", RecordsUsed = nrow(d), SpeciesUsed = length(unique(d$Species)),
      BootstrapReplicates = V3_COMPARISON_BOOTSTRAP, stringsAsFactors = FALSE)
  }
  if (!length(out)) return(data.frame())
  add_comparison_adjustment(do.call(rbind, out))
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
