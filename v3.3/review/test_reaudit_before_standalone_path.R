#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root);options(warn=1)
base<-normalizePath(file.path(root,"..","v3.2"),mustWork=TRUE)
prior<-new.env(parent=.GlobalEnv);sys.source(file.path(base,"R","bootstrap.R"),prior)
prior$load_v3_modules(base,envir=prior)
stopifnot(identical(V3_PRIORS,prior$V3_PRIORS),identical(V3_SAMPLING,prior$V3_SAMPLING),V3_SEED==prior$V3_SEED,
 identical(sha256_file(file.path(root,"stan","joint_bb.stan")),sha256_file(file.path(base,"stan","joint_bb.stan"))))
source<-file.path(root,"review","reused_v3_2","unequal_integration")
out<-file.path(root,"review","saved_fit_reaudit");dir.create(out,recursive=TRUE,showWarnings=FALSE)
state<-prior$prepare_state(file.path(source,"input"))
evidence<-read.csv(file.path(source,"results","cv_record_predictions.csv"),stringsAsFactors=FALSE)
panel<-read.csv(file.path(source,"synthetic_panel_projection.csv"),stringsAsFactors=FALSE)
folds<-data.frame(Species=state$sites$Species,Fold=rep(1:2,each=6))
receipts<-list();identities<-list();tamper_count<-0L
for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS)for(fold in 1:2) {
 p<-prior$fit_path_v3(source,route,model,tw,"integration",fold)
 source_hash<-sha256_file(p);b<-readRDS(p)
 held<-folds$Species[folds$Fold==fold];tr<-setdiff(if(route=="binary")state$binary_species else state$joint_species,held)
 ctl<-modifyList(prior$V3_SAMPLING,list(chains=2L,cores=2L,iter=600L,warmup=300L))
 if(route=="joint_bb")ctl<-modifyList(ctl,list(iter=300L,warmup=150L,adapt_delta=.9,max_treedepth=8L))
 spec<-prior$fit_spec_v3(state,route,model,tr,tw,file.path(base,"stan","joint_bb.stan"),ctl,V3_SEED+fold+match(model,V3_MODELS))
 d<-prior$validate_fitted_bundle_v3(b,spec,require_pass=FALSE)
 stopifnot(b$version==prior$V3_VERSION,d$Status=="FAILED_DIAGNOSTICS")
 # Old failed/test fits cannot become accepted formal v3.3 cache entries.
 stopifnot(inherits(tryCatch(validate_bundle_for_use(b,require_pass=TRUE),error=identity),"error"))
 stopifnot(inherits(tryCatch(prior$validate_fitted_bundle_v3(b,spec,require_pass=TRUE),error=identity),"error"))
 rows<-which(state$observations$Species%in%held & if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
 saved<-subset(evidence,Route==route&Model==model&TrainWeighting==tw&Fold==fold)
 ctx<-data.frame(Design="integration",Fold=fold,Route=route,Model=model,TrainWeighting=tw,RunPurpose="INTEGRATION_TEST_ONLY")
 receipts[[length(receipts)+1L]]<-audit_cv_bundle_predictions_v3(b,state,rows,saved,ctx)
 bad<-saved;bad$LogPredictiveDensityRaw[1]<-bad$LogPredictiveDensityRaw[1]+.01
 stopifnot(inherits(tryCatch(audit_cv_bundle_predictions_v3(b,state,rows,bad,ctx),error=identity),"error"));tamper_count<-tamper_count+1L
 if(fold==1L){z<-subset(panel,Route==route&Model==model&TrainWeighting==tw);receipts[[length(receipts)+1L]]<-audit_full_bundle_predictions_v3(b,state,z,ctx)}
 identities[[length(identities)+1L]]<-cbind(data.frame(Route=route,Model=model,TrainWeighting=tw,Fold=fold,SourceVersion=b$version,AuditVersion=V3_VERSION,FitKey=b$key,SourceRDS_SHA256=source_hash,SourceIdentityVerified=TRUE,NewVersionCacheRejected=TRUE,FormalDiagnosticGateRejected=TRUE),d)
 stopifnot(identical(source_hash,sha256_file(p)))
 cat("REAUDIT",route,model,tw,fold,"PASS\n");flush.console()
}
r<-do.call(rbind,receipts);r$SourceVersion<-prior$V3_VERSION;r$AuditVersion<-V3_VERSION
write_csv_atomic(r,file.path(out,"posterior_recompute_receipts.csv"));write_csv_atomic(do.call(rbind,identities),file.path(out,"source_fit_identity_and_diagnostics.csv"))
q<-verify_quantitative_outputs_v32(evidence,read.csv(file.path(source,"results","quantitative_bias_summary.csv")),read.csv(file.path(source,"results","quantitative_plot_source.csv")))
write_csv_atomic(q,file.path(out,"quantitative_recompute_receipts.csv"))
write_json_atomic(list(status="PASS_REAUDIT_OF_SOURCE_VERIFIED_V32_SYNTHETIC_FITS",fits_reopened=32,source_version=prior$V3_VERSION,audit_version=V3_VERSION,OOFRows=sum(r$RowsChecked[r$Check=="posterior_to_OOF"]),PanelRows=sum(r$RowsChecked[r$Check=="posterior_to_full_panel"]),max_absolute_difference=max(r$MaximumAbsoluteDifference),forged_logscore_rejections=tamper_count,formal_cache_and_diagnostic_rejections=32,source_diagnostics="FAILED_DIAGNOSTICS:32_unchanged",new_fits=0,real_data_fits=0),file.path(out,"status.json"))
cat("SAVED_V32_FITS_REAUDITED_WITH_V33_PASS; no refit, no identity relabel, no research data\n")
