# Small, explicit checks shared by the four stages.
`%||%` <- function(x, y) if (is.null(x)) y else x
sha256_file <- function(path) digest::digest(file=path, algo="sha256")
sha256_object <- function(x) digest::digest(x, algo="sha256", serialize=TRUE)
write_csv_atomic <- function(x,path,na="") {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  tmp<-paste0(path,".tmp");write.csv(x,tmp,row.names=FALSE,na=na)
  if(!file.rename(tmp,path))stop("Cannot write ",path)
}
save_rds_atomic <- function(x,path) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  tmp<-paste0(path,".tmp");saveRDS(x,tmp)
  if(!file.rename(tmp,path))stop("Cannot write ",path)
}
write_json_atomic <- function(x,path) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  tmp<-paste0(path,".tmp");jsonlite::write_json(x,tmp,auto_unbox=TRUE,pretty=TRUE,na="null",digits=16)
  if(!file.rename(tmp,path))stop("Cannot write ",path)
}
species_weights <- function(species) {
  species<-as.character(species)
  if(!length(species)||anyNA(species)||any(!nzchar(trimws(species))))stop("Missing species")
  length(species)/(length(unique(species))*as.numeric(table(species)[species]))
}
blueprint_key <- function(route,model) paste(route,model,sep="_")
check_settings <- function() {
  if(!identical(MODELS,c("Null","M1","M2","M3"))||!identical(ROUTES,c("binary","joint_bb"))||
     !identical(DESIGNS,c(fivefold=5L,tenfold=10L))||
     TRAIN_WEIGHTING!="record_equal"||EVAL_WEIGHTING!="species_equal")
    stop("v4 implements only the declared RS model/CV grid")
  if(!identical(PREDICTOR_SITES,c("Site3","Site20","Site117","Site196","Site315")))stop("Predictor sites changed")
  validate_sampling(SAMPLING)
  if(any(!is.finite(c(B_ELPD,B_OTHER_METRICS)))||any(c(B_ELPD,B_OTHER_METRICS)<2)||
     any(c(B_ELPD,B_OTHER_METRICS)!=trunc(c(B_ELPD,B_OTHER_METRICS))))stop("Invalid bootstrap sizes")
  invisible(TRUE)
}
validate_sampling <- function(x) {
  req<-c("chains","cores","iter","warmup","adapt_delta","max_treedepth")
  if(!all(req%in%names(x))||any(!is.finite(unlist(x[req]))))stop("Invalid sampling settings")
  for(n in setdiff(req,"adapt_delta"))if(x[[n]]!=trunc(x[[n]]))stop("Noninteger sampling setting")
  if(x$chains<2||x$cores<1||x$warmup<1||x$iter<=x$warmup||x$adapt_delta<=0||
     x$adapt_delta>=1||x$max_treedepth<1)stop("Invalid sampling bounds")
  x
}
check_input_hashes <- function(root) {
  actual<-vapply(names(INPUT_SHA256),function(n)sha256_file(file.path(root,"data",n)),character(1))
  if(!identical(unname(actual),unname(INPUT_SHA256)))stop("Frozen data/fold SHA256 mismatch")
  actual
}
analysis_identity <- function(root) {
  files<-c("settings.R","run_all.R",sprintf("%02d_%s.R",1:4,c("prepare","fit","evaluate","plot")),
           file.path("R",sort(list.files(file.path(root,"R"),pattern="[.]R$"))),"stan/joint_bb.stan")
  sha256_object(setNames(vapply(files,function(f)sha256_file(file.path(root,f)),character(1)),files))
}
check_fold_tables <- function(state,fold_tables=state$fold_tables) {
  if(!is.list(fold_tables)||anyDuplicated(names(fold_tables))||
     !setequal(names(fold_tables),names(DESIGNS)))stop("Incomplete or extra fold designs")
  for(d in names(DESIGNS)) {
    if(!is.list(fold_tables[[d]])||anyDuplicated(names(fold_tables[[d]]))||
       !setequal(names(fold_tables[[d]]),ROUTES))stop("Incomplete or extra fold routes")
    for(r in ROUTES) {
      f<-fold_tables[[d]][[r]];active<-if(r=="binary")state$binary_species else state$joint_species
      if(!is.data.frame(f)||anyDuplicated(names(f))||!all(c("Species","Fold")%in%names(f)))stop("Malformed fold table")
      if(anyNA(f$Species)||any(!nzchar(trimws(f$Species)))||anyDuplicated(f$Species)||
         !setequal(f$Species,active))stop("Fold species mismatch")
      k<-DESIGNS[[d]]
      if(!is.numeric(f$Fold)||is.object(f$Fold)||any(!is.finite(f$Fold))||
         any(f$Fold!=trunc(f$Fold)|f$Fold<1|f$Fold>k)||!setequal(f$Fold,seq_len(k)))stop("Invalid fold IDs")
      if(r=="binary")for(i in seq_len(k)) {
        y<-state$observations$High[state$observations$Species%in%f$Species[f$Fold==i]]
        if(!all(c(0,1)%in%y))stop("Every binary fold must contain both classes")
      }
    }
  }
  invisible(TRUE)
}
check_cv_evidence <- function(state,evidence) {
  required<-c("Design","Route","Model","TrainWeighting","RecordID","Species","Fold","Type",
              "ObservedHigh","ObservedPoint","LogPredictiveDensityRaw")
  if(!is.data.frame(evidence)||anyDuplicated(names(evidence))||!all(required%in%names(evidence)))stop("Malformed CV evidence")
  keys<-c("Design","Route","Model","TrainWeighting","RecordID")
  if(anyNA(evidence[keys])||anyDuplicated(evidence[keys])||any(evidence$TrainWeighting!=TRAIN_WEIGHTING)||
     any(!is.finite(evidence$LogPredictiveDensityRaw)))stop("Invalid CV identity or log score")
  expected_total<-0L
  for(d in names(DESIGNS))for(r in ROUTES)for(m in MODELS) {
    obs<-state$observations
    obs<-obs[if(r=="binary")!is.na(obs$High) else obs$Informative,,drop=FALSE]
    e<-evidence[evidence$Design==d&evidence$Route==r&evidence$Model==m,,drop=FALSE]
    if(nrow(e)!=nrow(obs)||!setequal(e$RecordID,obs$RecordID))stop("CV record coverage mismatch")
    obs<-obs[match(e$RecordID,obs$RecordID),];fold<-state$fold_tables[[d]][[r]]
    if(anyNA(e$Fold)||any(e$Fold!=fold$Fold[match(e$Species,fold$Species)])||
       !identical(as.character(e$Species),as.character(obs$Species))||
       !identical(as.character(e$Type),as.character(obs$Type)))stop("CV species/type/fold mismatch")
    if(r=="binary") {
      if(anyNA(e$ObservedHigh)||any(e$ObservedHigh!=obs$High))stop("Binary truth mismatch")
    } else {
      point<-obs$Type%in%c("count","exact")
      truth<-ifelse(obs$Type=="count",obs$Events/obs$Total,obs$Exact)
      if(any(!is.finite(e$ObservedPoint[point]))||any(abs(e$ObservedPoint[point]-truth[point])>1e-12)||
         any(!is.na(e$ObservedPoint[!point])))stop("Point truth mismatch or interval imputation")
    }
    expected_total<-expected_total+nrow(obs)
  }
  if(nrow(evidence)!=expected_total)stop("Extra CV rows")
  invisible(TRUE)
}
validate_prediction_table <- function(x) {
  keys<-c("Species","Route","Model","TrainWeighting")
  required<-c(keys,"Point","PosteriorMedian","CrI_lower","CrI_upper","PI_lower","PI_upper")
  if(!is.data.frame(x)||anyDuplicated(names(x))||!nrow(x)||!all(required%in%names(x))||anyNA(x[keys])||anyDuplicated(x[keys]))stop("Invalid prediction keys or missing columns")
  if(any(!x$Route%in%ROUTES)||any(!x$Model%in%MODELS)||any(x$TrainWeighting!=TRAIN_WEIGHTING))stop("Invalid prediction grid")
  for(n in c("Point","PosteriorMedian","CrI_lower","CrI_upper"))
    if(any(!is.finite(x[[n]]))||any(x[[n]]<0|x[[n]]>1))stop("Invalid prediction ",n)
  j<-x$Route=="joint_bb"
  if(any(!is.finite(x$PI_lower[j]))||any(!is.finite(x$PI_upper[j]))||
     any(x$PI_lower[j]<0|x$PI_upper[j]>1|x$PI_lower[j]>x$PI_upper[j])||
     any(x$CrI_lower>x$CrI_upper))stop("Invalid predictive/credible interval")
  invisible(TRUE)
}
stage_files <- function(stage) {
  switch(stage,
    fit=c("fit_diagnostics.csv","fit_manifest.csv","cv_record_predictions.csv",
          "full_panel_predictions.csv","training_ppc_summary.csv"),
    evaluate=c("cv_fold_metrics.csv","cv_metrics_summary.csv","hypothesis_tests.csv",
      "roc_coordinates.csv","calibration_bins.csv","quantitative_plot_source.csv","quantitative_bias_summary.csv",
      "auc_fold_species_support.csv","bootstrap_draws.rds","bootstrap_multiplicities.rds"),
    plot=file.path("figures",c("ROC_curves.pdf","calibration.pdf","cv_metrics.pdf","hypothesis_tests.pdf",
      "quantitative_predicted_observed.pdf","species_predictions_binary_record_equal.pdf",
      "species_predictions_joint_bb_record_equal.pdf","species_prediction_plot_source.csv")),
    stop("Unknown stage"))
}
stage_receipt <- function(stage,state,out,files=stage_files(stage)) {
  expected<-stage_files(stage)
  if(!length(files)||anyDuplicated(files)||!setequal(files,expected))stop("Stage file set is incomplete")
  hashes<-setNames(vapply(expected,function(n)sha256_file(file.path(out,n)),character(1)),expected)
  save_rds_atomic(list(stage=stage,analysis_id=state$analysis_id,files=hashes),file.path(out,paste0(stage,"_receipt.rds")))
}
check_stage_receipt <- function(stage,state,out) {
  p<-file.path(out,paste0(stage,"_receipt.rds"));if(!file.exists(p))stop("Run ",stage," first")
  x<-readRDS(p);expected<-stage_files(stage)
  if(!identical(x$stage,stage)||!identical(x$analysis_id,state$analysis_id)||
     !is.character(x$files)||!identical(names(x$files),expected)||anyNA(x$files))stop("Invalid/incomplete stage receipt")
  current<-vapply(expected,function(n)sha256_file(file.path(out,n)),character(1))
  if(!identical(current,x$files))stop("Stage outputs changed: ",stage)
  invisible(TRUE)
}
check_grid <- function(x,expected,keys,values=character()) {
  metric_columns(x,c(keys,values));metric_ids(x,keys)
  if(nrow(x)!=nrow(expected)||anyDuplicated(metric_key(x,keys))||
     !setequal(metric_key(x,keys),metric_key(expected,keys)))stop("Output grid mismatch")
  invisible(TRUE)
}

# Sampling diagnostic thresholds are unchanged from v3.4.
diagnostic_metrics_pass <- function(draws) {
  cols<-c("rhat","ess_bulk","ess_tail")
  if(!nrow(draws)||!all(cols%in%names(draws)))return(FALSE)
  v<-as.matrix(as.data.frame(draws)[,cols,drop=FALSE])
  all(is.finite(v)) && max(draws$rhat)<1.01 && min(draws$ess_bulk)>=400 && min(draws$ess_tail)>=400
}
diagnose_draws <- function(array, sp, max_treedepth) {
  summary<-posterior::summarise_draws(posterior::as_draws_array(array),"rhat","ess_bulk","ess_tail")
  divergences<-sum(vapply(sp,function(x)sum(x[,"divergent__"]),numeric(1)))
  hits<-sum(vapply(sp,function(x)sum(x[,"treedepth__"]>=max_treedepth),numeric(1)))
  ebfmi<-vapply(sp,function(x)mean(diff(x[,"energy__"])^2)/var(x[,"energy__"]),numeric(1))
  ok<-all(is.finite(array))&&diagnostic_metrics_pass(summary)&&length(sp)>0&&divergences==0&&hits==0&&all(is.finite(ebfmi))&&min(ebfmi)>.3
  data.frame(Status=if(ok)"PASS" else "FAILED_DIAGNOSTICS",MaxRhat=if(all(is.finite(summary$rhat)))max(summary$rhat) else NA_real_,MinBulkESS=if(all(is.finite(summary$ess_bulk)))min(summary$ess_bulk) else NA_real_,MinTailESS=if(all(is.finite(summary$ess_tail)))min(summary$ess_tail) else NA_real_,Divergences=divergences,TreeDepthHits=hits,MinEBFMI=if(length(ebfmi))min(ebfmi) else NA_real_,ParametersChecked=nrow(summary),DiagnosticScope="sampled_parameters_and_lp; deterministic_outputs_checked_separately")
}
diagnose_brms_fit <- function(fit,max_treedepth=SAMPLING$max_treedepth) {
  a<-as.array(fit);vars<-dimnames(a)[[3]];keep<-grepl("^b_|^lp__$",vars)
  if(!any(keep))stop("No binary parameters in fit")
  diagnose_draws(a[,,keep,drop=FALSE],rstan::get_sampler_params(fit$fit,inc_warmup=FALSE),max_treedepth)
}
diagnose_rstan_fit <- function(fit,max_treedepth=SAMPLING$max_treedepth) {
  a<-as.array(fit);vars<-dimnames(a)[[3]]
  keep<-grepl("^(alpha|beta\\[|rho$|log_phi_ratio$|log_phi_count$|lp__$)",vars)
  if(!all(c("alpha","rho","log_phi_ratio","log_phi_count")%in%vars))stop("Missing joint parameters")
  diagnose_draws(a[,,keep,drop=FALSE],rstan::get_sampler_params(fit,inc_warmup=FALSE),max_treedepth)
}
