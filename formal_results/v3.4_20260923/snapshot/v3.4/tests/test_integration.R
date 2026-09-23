#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
options(warn=1)
out<-file.path(root,"review","integration")
dir.create(file.path(out,"input"),recursive=TRUE,showWarnings=FALSE)
p<-data.frame(Species=paste0("test_",1:6),Site3=rep(c("C","R"),3),Site20="K",Site117="K",Site151="C",Site196="C",Site315=rep(c("K","T","R"),2))
obs<-do.call(rbind,lapply(seq_len(nrow(p)),function(i)data.frame(RecordID=paste0("test",i,"_",1:5),ExperimentID=paste0("experiment",i,"_",1:5),SourceID="synthetic_fixture",Species=p$Species[i],Type=c("count","count","exact","exact","interval"),Events=c(0,2,NA,NA,NA),Total=c(2,2,NA,NA,NA),Exact=c(NA,NA,.2,.8,NA),Lower=c(NA,NA,NA,NA,.35),Upper=c(NA,NA,NA,NA,.65))))
write_csv_atomic(p,file.path(out,"input","sites.csv"));write_csv_atomic(obs,file.path(out,"input","observations.csv"))
state<-prepare_state(file.path(out,"input"))
V3_DESIGN_K<-c(integration=2L);V3_DESIGNS<-"integration"
folds<-list(integration=list(binary=data.frame(Species=p$Species,Fold=rep(1:2,3)),joint_bb=data.frame(Species=p$Species,Fold=rep(1:2,3))))
ans<-run_cv_v3(state,out,folds,file.path(root,"stan","joint_bb.stan"),iter=600L,warmup=300L,chains=2L,cores=2L,models=c("Null","M1"),diagnostic_gate=FALSE)
stopifnot(nrow(ans$evidence)==216L,nrow(ans$fold_metrics)==32L,nrow(ans$summary)==16L,!anyDuplicated(names(ans$evidence)),all(ans$evidence$RunPurpose=="INTEGRATION_TEST_ONLY"))
# This really left three species out of each training fit.
receipts<-list();last<-NULL
for(r in V3_ROUTES)for(m in c("Null","M1"))for(tw in V3_TRAIN_WEIGHTINGS)for(f in 1:2) {
  b<-readRDS(fit_path_v3(out,r,m,tw,"integration",f));held<-p$Species[rep(1:2,3)==f];tr<-setdiff(p$Species,held)
  stopifnot(!any(b$train_species%in%held),setequal(b$train_species,tr))
  ctl<-modifyList(V3_SAMPLING,list(iter=600L,warmup=300L,chains=2L,cores=2L))
  spec<-fit_spec_v3(state,r,m,tr,tw,file.path(root,"stan","joint_bb.stan"),ctl,V3_SEED+f+match(m,V3_MODELS))
  validate_fitted_bundle_v3(b,spec,require_pass=FALSE)
  bad<-b;bad$request$model_code_hash<-"wrong"
  stopifnot(inherits(tryCatch(validate_fitted_bundle_v3(bad,spec,FALSE),error=identity),"error"))
  bad<-b;bad$fit<-NULL;stopifnot(inherits(tryCatch(validate_fitted_bundle_v3(bad,spec,FALSE),error=identity),"error"))
  bad<-b;bad$diagnostics$Status<-"PASS";if(b$diagnostics$Status!="PASS")stopifnot(inherits(tryCatch(validate_fitted_bundle_v3(bad,spec,TRUE),error=identity),"error"))
  receipts[[length(receipts)+1]]<-cbind(data.frame(Route=r,Model=m,TrainWeighting=tw,Fold=f),b$diagnostics)
  last<-list(b=b,spec=spec)
}
# Genuine Null and M1 batch/individual/reordered projections, including unseen MISSING.
bundles<-list()
for(r in V3_ROUTES)for(m in c("Null","M1"))bundles[[paste(r,m,"species_equal",sep="|")]]<-readRDS(fit_path_v3(out,r,m,"species_equal","integration",1))
new<-p[1:2,];new$Species<-c("new_a","new_b");new$Site196[2]<-"MISSING"
batch<-external_prediction_table(state,bundles,new,models=c("Null","M1"),train_weightings="species_equal",allow_diagnostic_warnings=TRUE)
reverse<-external_prediction_table(state,bundles,new[2:1,],models=c("Null","M1"),train_weightings="species_equal",allow_diagnostic_warnings=TRUE)
key<-function(z)paste(z$Species,z$Route,z$Model)
reverse<-reverse[match(key(batch),key(reverse)),]
stopifnot(isTRUE(all.equal(batch$Point,reverse$Point)),isTRUE(all.equal(batch$PI_lower,reverse$PI_lower)))
for(i in 1:2) {
  single<-external_prediction_table(state,bundles,new[i,,drop=FALSE],models=c("Null","M1"),train_weightings="species_equal",allow_diagnostic_warnings=TRUE)
  z<-batch[match(key(single),key(batch)),];stopifnot(isTRUE(all.equal(single$Point,z$Point)),isTRUE(all.equal(single$PI_lower,z$PI_lower)))
}
stopifnot(all(batch$AnyMissingPredictorSite[batch$Species=="new_b"&batch$Model=="M1"]))
# Typed PPC and score generation from actual fits (interface evidence, not research results).
ppc<-do.call(rbind,lapply(bundles,ppc_summary_for_bundle_v3,state=state));stopifnot(nrow(ppc)>0,all(is.finite(ppc$Observed)))
write_csv_atomic(ppc,file.path(out,"training_ppc_test.csv"));write_csv_atomic(batch,file.path(out,"external_prediction_test.csv"))
write_csv_atomic(do.call(rbind,receipts),file.path(out,"fit_diagnostics.csv"))
write_json_atomic(list(status="PASS_INTERFACE_ONLY",purpose="synthetic_twofold_species_holdout",actual_fits=16,cv_records=nrow(ans$evidence),fold_metric_rows=nrow(ans$fold_metrics),summary_rows=nrow(ans$summary),diagnostic_gate="strict_gate_tested_separately; low_iteration_test_results_not_formal"),file.path(out,"integration_status.json"))
cat("INTEGRATION_PASS: 16 real synthetic fits, both routes/training weights, both evaluations; no formal research results\n")
