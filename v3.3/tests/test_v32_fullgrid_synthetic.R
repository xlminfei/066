#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
source(file.path(root,"tests","fixtures_v32.R"))
out<-file.path(root,"review","fullgrid_synthetic");state<-make_unequal_fixture_v32(out)
folds<-make_fold_tables_v3(state,output_dir=file.path(out,"results"))
fit_fake<-function(state,route,model,train_species,train_weighting,root,design,fold,stan_path,iter,warmup,chains,cores,seed,force) {
 list(route=route,model=model,train_weighting=train_weighting,train_species=train_species,
  blueprint=make_design_blueprint(state$encoded,train_species,model),key=paste(route,model,train_weighting,design,fold),diagnostics=data.frame(Status="PASS"))
}
score_fake<-function(bundle,state,held_rows) {
 o<-state$observations[held_rows,];point<-o$Type%in%c("count","exact")
 y<-ifelse(o$Type=="count",o$Events/o$Total,o$Exact)
 pred<-rep(.35+.05*match(bundle$model,V3_MODELS),nrow(o))
 data.frame(RecordID=o$RecordID,Species=o$Species,Type=o$Type,ObservedHigh=o$High,
   ObservedPoint=if(bundle$route=="binary")NA_real_ else y,
   PredictedPrHigh=if(bundle$route=="binary")pred else NA_real_,
   PredictedPoint=if(bundle$route=="joint_bb")pred else NA_real_,
   PredictedPI_lower=0,PredictedPI_upper=1,PIWidth=1,IntervalCovered=ifelse(point,TRUE,NA),
   LogPredictiveDensityRaw=log(.5)+.01*match(bundle$model,V3_MODELS),OriginalRow=held_rows)
}
env<-new.env(parent=.GlobalEnv);env$binary_record_scores<-env$joint_record_scores<-score_fake
runner<-run_cv_v3;environment(runner)<-env
ans<-runner(state,out,folds,NULL,fit_function=fit_fake,diagnostic_gate=FALSE)
stopifnot(nrow(ans$fold_metrics)==480L,nrow(ans$summary)==64L)
need<-c("LogScoreSpeciesUsed","PointSpeciesUsed","PISpeciesUsed","Bias")
stopifnot(all(need%in%names(ans$fold_metrics)),all(need%in%names(ans$summary)))
q<-subset(ans$summary,Route=="joint_bb")
stopifnot(all(q$LogScoreSpeciesUsed==12L),all(q$PointSpeciesUsed==11L),all(q$PISpeciesUsed==11L),all(is.finite(q$Bias)))
for(i in seq_len(nrow(q))) {
 row<-q[i,];e<-subset(ans$evidence,Route==row$Route&Design==row$Design&Model==row$Model&TrainWeighting==row$TrainWeighting)
 direct<-evaluate_evidence(e,row$EvalWeighting,row$Route)
 stopifnot(abs(direct$Bias-row$Bias)<1e-12)
}
V3_COMPARISON_BOOTSTRAP<-50L # only speed for deterministic orchestration fixture
postprocess_v3(out,ans$evidence)
a<-read.csv(file.path(out,"results","model_vs_null.csv"));b<-read.csv(file.path(out,"results","training_method_comparisons.csv"))
stopifnot(nrow(a)==48L,nrow(b)==32L)
if(exists("verify_comparison_outputs_v3"))verify_comparison_outputs_v3(ans$evidence,a,b)
d<-read.csv(file.path(out,"results","quantitative_bias_summary.csv"));stopifnot(nrow(d)==32L)
keys<-c("Design","Route","Model","TrainWeighting","EvalWeighting")
match_key<-function(z)do.call(paste,c(z[,keys],sep="|"))
d<-d[match(match_key(q),match_key(d)),]
stopifnot(max(abs(d$Bias-q$Bias))<1e-12)
write_quantitative_diagnostics_v32(ans$evidence,file.path(out,"results"),file.path(out,"figures"),test_only=TRUE)
write_json_atomic(list(status="PASS_SYNTHETIC_MOCK_FULLGRID",cv_tasks=240,OOFRows=nrow(ans$evidence),FoldMetrics=480,SummaryRows=64,ModelComparisons=48,TrainingComparisons=32,QuantitativeBiasRows=32,LogScoreSpecies=12,PointSpecies=11,PISpecies=11,formal_research_fits=0),file.path(out,"test_status.json"))
cat("FULLGRID_SYNTHETIC_PASS: 240 mock tasks; 480/64/48/32 keys; metric support and bias propagated\n")
