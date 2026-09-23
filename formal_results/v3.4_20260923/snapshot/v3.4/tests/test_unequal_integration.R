#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
options(warn=1)
source(file.path(root,"tests","fixtures_v32.R"))
out<-file.path(root,"review","unequal_integration")
state<-make_unequal_fixture_v32(out)
stopifnot(length(unique(table(state$observations$Species)))>1L)
# Synthetic test configuration is confined to this R process and test output root.
V3_DESIGN_K<-c(integration=2L);V3_DESIGNS<-"integration"
allfolds<-data.frame(Species=state$sites$Species,Fold=rep(1:2,each=6L))
folds<-list(integration=list(binary=allfolds[allfolds$Species%in%state$binary_species,],joint_bb=allfolds))
ctl<-modifyList(V3_SAMPLING,list(iter=600L,warmup=300L,chains=2L,cores=2L))
expected<-list()
for(route in V3_ROUTES)for(fold in 1:2) {
  active<-if(route=="binary")state$binary_species else state$joint_species
  tr<-setdiff(active,allfolds$Species[allfolds$Fold==fold])
  rr<-which(state$observations$Species%in%tr & if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
  w1<-build_train_weights(state$observations[rr,,drop=FALSE],"record_equal")
  w2<-build_train_weights(state$observations[rr,,drop=FALSE],"species_equal")
  stopifnot(check_weight_contract(w1),check_weight_contract(w2),any(abs(w1$weight-w2$weight)>1e-8))
  expected[[length(expected)+1L]]<-data.frame(Route=route,Fold=fold,Records=length(rr),Species=length(tr),MaxWeightDifference=max(abs(w1$weight-w2$weight)))
}
write_csv_atomic(do.call(rbind,expected),file.path(out,"pre_fit_weight_inequality.csv"))
# Explicitly isolated interface settings: joint uses shorter, shallower chains.
# No diagnostic thresholds or formal config are relaxed; all warnings are retained.
fit_interface<-function(state,route,model,train_species,train_weighting,root,design,fold,stan_path,iter,warmup,chains,cores,seed,force) {
  previous<-V3_SAMPLING;on.exit({V3_SAMPLING<<-previous},add=TRUE)
  if(route=="joint_bb") {
    V3_SAMPLING<<-modifyList(previous,list(adapt_delta=.9,max_treedepth=8L))
    iter<-300L;warmup<-150L
  }
  fit_bundle_v3(state,route,model,train_species,train_weighting,root,design,fold,stan_path,iter,warmup,chains,cores,seed,force)
}
ans<-run_cv_v3(state,out,folds,file.path(root,"stan","joint_bb.stan"),iter=ctl$iter,warmup=ctl$warmup,chains=ctl$chains,cores=ctl$cores,models=V3_MODELS,fit_function=fit_interface,diagnostic_gate=FALSE)
stopifnot(nrow(ans$fold_metrics)==64L,nrow(ans$summary)==32L,!anyDuplicated(names(ans$evidence)),all(ans$evidence$RunPurpose=="INTEGRATION_TEST_ONLY"),all(c("Bias","LogScoreSpeciesUsed","PointSpeciesUsed","PISpeciesUsed")%in%names(ans$summary)))
receipts<-list();bundles<-list();weight_check<-list()
for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS)for(fold in 1:2) {
  b<-readRDS(fit_path_v3(out,route,model,tw,"integration",fold))
  held<-folds$integration[[route]]$Species[folds$integration[[route]]$Fold==fold]
  tr<-setdiff(if(route=="binary")state$binary_species else state$joint_species,held)
  actual_ctl<-if(route=="joint_bb")modifyList(ctl,list(iter=300L,warmup=150L,adapt_delta=.9,max_treedepth=8L)) else ctl
  spec<-fit_spec_v3(state,route,model,tr,tw,file.path(root,"stan","joint_bb.stan"),actual_ctl,V3_SEED+fold+match(model,V3_MODELS))
  d<-validate_fitted_bundle_v3(b,spec,FALSE)
  stopifnot(!any(b$train_species%in%held),setequal(b$train_species,tr))
  actual_weights<-if(route=="binary")b$data$TrainWeight else b$data$train_weight[b$request$train_rows]
  wf<-build_train_weights(state$observations[b$request$train_rows,,drop=FALSE],tw)
  stopifnot(isTRUE(all.equal(actual_weights,wf$weight,tolerance=1e-12)))
  if(route=="joint_bb")stopifnot(all(b$data$train_weight[-b$request$train_rows]==0),all(b$data$train[-b$request$train_rows]==0))
  e<-subset(ans$evidence,Route==route&Model==model&TrainWeighting==tw&Fold==fold)
  if(model=="M3")stopifnot(any(!e$FixedEffectEstimable),any(e$UnseenEncodedCategory))
  receipts[[length(receipts)+1L]]<-cbind(data.frame(Route=route,Model=model,TrainWeighting=tw,Fold=fold,TrainingWeightVerified=TRUE,HeldOutDisjoint=TRUE),d)
  weight_check[[length(weight_check)+1L]]<-data.frame(Route=route,Model=model,TrainWeighting=tw,Fold=fold,RecordID=state$observations$RecordID[b$request$train_rows],Weight=actual_weights)
  bundles[[paste(route,model,tw,fold,sep="|")]]<-b
}
write_csv_atomic(do.call(rbind,receipts),file.path(out,"fit_diagnostics.csv"))
write_csv_atomic(do.call(rbind,weight_check),file.path(out,"verified_training_weights.csv"))
# Compare both actual branch posteriors on the same held-out species; no requirement that one be better.
posterior_diffs<-list()
for(route in V3_ROUTES)for(model in V3_MODELS)for(fold in 1:2) {
  a<-bundles[[paste(route,model,"record_equal",fold,sep="|")]];b<-bundles[[paste(route,model,"species_equal",fold,sep="|")]]
  held<-folds$integration[[route]]$Species[folds$integration[[route]]$Fold==fold]
  pd<-max(abs(colMeans(binary_prediction_draws(a,state,held))-colMeans(binary_prediction_draws(b,state,held))))
  stopifnot(a$key!=b$key,a$request$weight_hash!=b$request$weight_hash,is.finite(pd))
  posterior_diffs[[length(posterior_diffs)+1L]]<-data.frame(Route=route,Model=model,Fold=fold,MaxMeanDifference=pd,RecordEqualWeightHash=a$request$weight_hash,SpeciesEqualWeightHash=b$request$weight_hash)
}
write_csv_atomic(do.call(rbind,posterior_diffs),file.path(out,"posterior_training_comparison.csv"))
if(exists("write_quantitative_diagnostics_v32"))write_quantitative_diagnostics_v32(ans$evidence,file.path(out,"results"),file.path(out,"figures"),test_only=TRUE)
write_json_atomic(list(status="PASS_INTERFACE_ONLY",version=V3_VERSION,purpose="UNBALANCED_SYNTHETIC_DATA_ONLY",actual_fits=32,models=V3_MODELS,routes=V3_ROUTES,train_weightings=V3_TRAIN_WEIGHTINGS,records_by_species=as.list(table(state$observations$Species)),evidence_rows=nrow(ans$evidence),fold_metrics=nrow(ans$fold_metrics),summary_rows=nrow(ans$summary),training_weights_unequal_in_both_folds=TRUE,synthetic_binary_sampling=ctl,synthetic_joint_sampling=modifyList(ctl,list(iter=300L,warmup=150L,adapt_delta=.9,max_treedepth=8L)),diagnostics=as.list(table(do.call(rbind,receipts)$Status)),formal_research_fits=0),file.path(out,"integration_status.json"))
cat("UNEQUAL_INTEGRATION_PASS: 32 real synthetic fits, Null/M1/M2/M3, binary/joint, unequal species counts; no formal results\n")
