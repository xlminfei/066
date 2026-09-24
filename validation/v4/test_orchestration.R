# Full 128-task orchestration with explicit stand-ins and saved v3.4 predictions.
# This is NOT 128 new fits; the two genuine synthetic fits are tested separately.
args<-commandArgs(TRUE);repo<-args[1];out<-args[2]
root<-file.path(repo,"v4");source(file.path(root,"R/load.R"));load_v4(root)
state<-prepare_stage(root,out)
reference<-file.path(repo,"formal_results/v3.4_20260923/snapshot/v3.4/results")
old_oof<-read.csv(file.path(reference,"cv_record_predictions.csv"),stringsAsFactors=FALSE)
old_panel<-read.csv(file.path(reference,"full_panel_predictions.csv"),stringsAsFactors=FALSE)
old_ppc<-read.csv(file.path(reference,"training_ppc_summary.csv"),stringsAsFactors=FALSE)
env<-new.env(parent=.GlobalEnv);sys.source(file.path(root,"02_fit.R"),envir=env)
calls<-list()
env$fit_spec<-function(state,route,model,train_species,stan_path,sampling=SAMPLING,seed=SEED) {
  active<-if(route=="binary")state$binary_species else state$joint_species
  held<-setdiff(active,train_species);design<-"full";fold<-NA_integer_
  if(length(held)) {
    matches<-list()
    for(d in names(DESIGNS))for(f in seq_len(DESIGNS[[d]])) {
      ft<-state$fold_tables[[d]][[route]]
      if(setequal(held,ft$Species[ft$Fold==f]))matches[[length(matches)+1L]]<-list(d=d,f=f)
    }
    stopifnot(length(matches)==1L);design<-matches[[1]]$d;fold<-matches[[1]]$f
  }
  rows<-which(state$observations$Species%in%train_species &
    if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
  stopifnot(!length(intersect(train_species,held)),all(state$observations$Species[rows]%in%train_species))
  expected_seed<-if(design=="full")SEED else SEED+fold+match(model,MODELS);stopifnot(seed==expected_seed)
  req<-list(route=route,model=model,train_rows=rows,training_species=train_species,seed=seed)
  list(request=req,key=sha256_object(req),route=route,model=model,train_species=train_species,
       train_weighting=TRAIN_WEIGHTING,design=design,fold=fold)
}
fake_fit<-function(spec,path) {
  calls[[length(calls)+1L]]<<-data.frame(Route=spec$route,Model=spec$model,Design=spec$design,Fold=spec$fold,Seed=spec$request$seed)
  spec$diagnostics<-data.frame(Status="PASS",MaxRhat=1,MinBulkESS=1000,MinTailESS=1000,
    Divergences=0,TreeDepthHits=0,MinEBFMI=1,ParametersChecked=1,DiagnosticScope="MOCK_ORCHESTRATION_ONLY")
  spec$blueprint<-make_design_blueprint(state$encoded,spec$train_species,spec$model)
  save_rds_atomic(list(Purpose="MOCK_ORCHESTRATION_ONLY",request=spec$request),path)
  spec
}
env$panel_prediction<-function(bundle,state)old_panel[old_panel$Route==bundle$route&
  old_panel$Model==bundle$model&old_panel$TrainWeighting==TRAIN_WEIGHTING,]
env$ppc_summary_for_bundle<-function(bundle,state)old_ppc[old_ppc$Route==bundle$route&
  old_ppc$Model==bundle$model&old_ppc$TrainWeighting==TRAIN_WEIGHTING&old_ppc$EvalWeighting==EVAL_WEIGHTING,]
score<-function(bundle,state,held_rows) {
  z<-old_oof[old_oof$Route==bundle$route&old_oof$Model==bundle$model&
    old_oof$TrainWeighting==TRAIN_WEIGHTING&old_oof$Design==bundle$design&old_oof$Fold==bundle$fold,]
  z<-z[match(state$observations$RecordID[held_rows],z$RecordID),]
  fields<-c("RecordID","ExperimentID","SourceID","Species","Type","ObservedHigh","ObservedPoint","PredictedPrHigh",
    "PredictedPoint","PredictedPI_lower","PredictedPI_upper","PIWidth","IntervalCovered","IntervalOverlap",
    "PIObservationModel","LogPredictiveDensityRaw","OriginalRow")
  z[fields]
}
env$binary_record_scores<-env$joint_record_scores<-score
evidence<-env$fit_stage(root,state,out,fit_function=fake_fit)
stopifnot(length(calls)==128,nrow(evidence)==2440)
check_stage_receipt("fit",state,out)
evaluate_stage(state,evidence,out);stage_receipt("evaluate",state,out)
plot_stage(state,out);check_complete_outputs(state,out)
write.csv(do.call(rbind,calls),file.path(out,"mock_calls.csv"),row.names=FALSE)
write_json_atomic(list(status="PASS",purpose="ORCHESTRATION_WITH_STAND_INS_AND_SAVED_PREDICTIONS",
  scheduled_tasks=128L,new_mcmc_fits=0L,OOF_rows=2440L,panel_rows=2920L,
  fold_metric_rows=120L,summary_rows=16L,hypothesis_rows=30L,
  production_bootstrap_sizes=c(ELPD=B_ELPD,Other=B_OTHER_METRICS)),
  file.path(out,"orchestration_status.json"))
writeLines(c("VALIDATION ONLY: these 128 fit files are stand-ins, not posterior objects.",
  "Predictions are retained v3.4 record-equal fits; v4 evaluation and plotting executed anew.",
  "This validates dispatch, output grids, receipts and plotting; it is not a new formal v4 run."),
  file.path(out,"README_TEST_ONLY.txt"))
cat("V4_ORCHESTRATION_AND_PLOTS_PASS: 128 stand-ins, zero new fits\n")
