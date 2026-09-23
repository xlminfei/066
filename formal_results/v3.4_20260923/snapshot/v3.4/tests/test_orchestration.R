#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
state<-load_state_v3(root);folds<-make_fold_tables_v3(state)
# Pure orchestration fixture supplies deterministic parameters/scoring; no MCMC.
# It tests all 240 CV task identities; test_integration.R independently tests real fits.
fit_fake<-function(state,route,model,train_species,train_weighting,root,design,fold,stan_path,iter,warmup,chains,cores,seed,force) {
  bp<-make_design_blueprint(state$encoded,train_species,model)
  list(route=route,model=model,train_weighting=train_weighting,train_species=train_species,blueprint=bp,key=paste(route,model,train_weighting,design,fold),diagnostics=data.frame(Status="PASS"))
}
score_fake<-function(bundle,state,held_rows) {
  o<-state$observations[held_rows,];y<-ifelse(o$Type=="count",o$Events/o$Total,o$Exact)
  data.frame(Species=o$Species,RecordID=o$RecordID,ObservedHigh=o$High,ObservedPoint=if(bundle$route=="binary")NA_real_ else y,PredictedPrHigh=if(bundle$route=="binary")rep(.6,nrow(o)) else NA_real_,PredictedPoint=if(bundle$route=="joint_bb")rep(.5,nrow(o)) else NA_real_,Type=o$Type,
    PredictedPI_lower=0,PredictedPI_upper=1,PIWidth=1,IntervalCovered=ifelse(is.na(y),NA,TRUE),LogPredictiveDensityRaw=-1,OriginalRow=held_rows)
}
# A separate lexical environment replaces only sampler/scoring boundaries.
env<-new.env(parent=.GlobalEnv);env$binary_record_scores<-env$joint_record_scores<-score_fake
runner<-run_cv_v3;environment(runner)<-env
out<-tempfile("v31_grid_");dir.create(out)
ans<-runner(state,out,folds,NULL,fit_function=fit_fake)
stopifnot(nrow(ans$evidence)==4880L,nrow(ans$fold_metrics)==480L,nrow(ans$summary)==64L,!anyDuplicated(names(ans$fold_metrics)))
assert_error<-function(expr){stopifnot(inherits(tryCatch(force(expr),error=identity),"error"))}
bad<-ans$evidence[-1,];assert_error(validate_cv_evidence_v3(state,bad,folds))
bad<-ans$fold_metrics;bad$AUC[bad$Route=="binary"][1]<-NA;assert_error(summarize_cv_metrics_v3(ans$evidence,bad))
badfolds<-folds;names(badfolds$fivefold)[2]<-"joint";assert_error(validate_fold_tables_v3(state,badfolds))
# Config and input provenance invalidation without modifying actual project files.
s<-state;s$input_hashes[[1]]<-"changed"
r1<-fit_identity("joint_bb","Null","species_equal",1:10,state,"code")
r2<-fit_identity("joint_bb","Null","species_equal",1:10,s,"code");stopifnot(identity_key(r1)!=identity_key(r2))
s<-state;s$blueprints$joint_bb_Null$rank<-2
r2<-fit_identity("joint_bb","Null","species_equal",1:10,s,"code");stopifnot(identity_key(r1)!=identity_key(r2))
r2<-fit_identity("joint_bb","Null","species_equal",1:10,state,"code",sampling=modifyList(V3_SAMPLING,list(adapt_delta=.98)));stopifnot(identity_key(r1)!=identity_key(r2))
old<-V3_EVAL_WEIGHTINGS;V3_EVAL_WEIGHTINGS<-rev(old);r2<-fit_identity("joint_bb","Null","species_equal",1:10,state,"code");stopifnot(identical(r1,r2));V3_EVAL_WEIGHTINGS<-old
# Old COMPLETE must not survive a failing rerun.
tmp<-tempfile();dir.create(tmp);write_json_atomic(list(status="COMPLETE"),file.path(tmp,"review","final_v3_status.json"))
assert_error(run_with_status_v3(tmp,"all",function()stop("intentional regression failure")))
stopifnot(jsonlite::read_json(file.path(tmp,"review","final_v3_status.json"))$status=="FAILED")
write_json_atomic(list(status="PASS",CVTasks=240,OOFRows=4880,FoldMetrics=480,SummaryRows=64,purpose="mock_sampler_orchestration_only"),file.path(root,"review","orchestration_test.json"))
cat("ORCHESTRATION_PASS: 240 tasks; 4880/480/64 rows; failure and identity tests\n")
