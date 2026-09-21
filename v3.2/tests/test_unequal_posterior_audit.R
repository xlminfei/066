#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
options(warn=1)
out<-file.path(root,"review","unequal_integration")
state<-prepare_state(file.path(out,"input"))
evidence<-read.csv(file.path(out,"results","cv_record_predictions.csv"),stringsAsFactors=FALSE)
allfolds<-data.frame(Species=state$sites$Species,Fold=rep(1:2,each=6L))
receipts<-list();panel_bundles<-list()
for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS)for(fold in 1:2) {
 b<-readRDS(fit_path_v3(out,route,model,tw,"integration",fold))
 held<-allfolds$Species[allfolds$Fold==fold]
 held_rows<-which(state$observations$Species%in%held & if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
 saved<-evidence[evidence$Route==route&evidence$Model==model&evidence$TrainWeighting==tw&evidence$Fold==fold,,drop=FALSE]
 context<-data.frame(Design="integration",Fold=fold,Route=route,Model=model,TrainWeighting=tw,RunPurpose="INTEGRATION_TEST_ONLY")
 receipts[[length(receipts)+1L]]<-audit_cv_bundle_predictions_v3(b,state,held_rows,saved,context)
 changed<-saved
 if(route=="binary")changed$PredictedPrHigh[1]<-min(1,changed$PredictedPrHigh[1]+.005) else changed$PredictedPoint[1]<-min(1,changed$PredictedPoint[1]+.005)
 stopifnot(inherits(tryCatch(audit_cv_bundle_predictions_v3(b,state,held_rows,changed,context),error=identity),"error"))
 changed<-saved;changed$LogPredictiveDensityRaw[1]<-changed$LogPredictiveDensityRaw[1]+.01
 # Even if the metric summary is recomputed from the forged raw evidence it must fail posterior audit.
 metrics_from_forgery<-evaluate_evidence(changed,"record_equal",route)
 stopifnot(is.finite(metrics_from_forgery$MeanLogScore),inherits(tryCatch(audit_cv_bundle_predictions_v3(b,state,held_rows,changed,context),error=identity),"error"))
 if(fold==1L)panel_bundles[[paste(route,model,tw,sep="|")]]<-b
}
# Exercise the entire panel projection code with real synthetic CV posteriors.
# These are not newly performed full-data fits and are marked accordingly.
projected<-external_prediction_table(state,panel_bundles,state$sites,allow_diagnostic_warnings=TRUE)
projected$TestOnly<-TRUE
write_csv_atomic(projected,file.path(out,"synthetic_panel_projection.csv"))
for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS) {
 b<-panel_bundles[[paste(route,model,tw,sep="|")]]
 saved<-projected[projected$Route==route&projected$Model==model&projected$TrainWeighting==tw,,drop=FALSE]
 ctx<-data.frame(Design="synthetic_panel_projection_from_CV",Fold=1L,Route=route,Model=model,TrainWeighting=tw,RunPurpose="INTEGRATION_TEST_ONLY")
 receipts[[length(receipts)+1L]]<-audit_full_bundle_predictions_v3(b,state,saved,ctx)
 changed<-saved;changed$Point[1]<-changed$Point[1]+.001
 stopifnot(inherits(tryCatch(audit_full_bundle_predictions_v3(b,state,changed,ctx),error=identity),"error"))
}
r<-do.call(rbind,receipts)
stopifnot(all(r$Status=="PASS"),all(c("count","exact","interval")%in%r$RecordType[r$Route=="joint_bb"]))
write_csv_atomic(r,file.path(out,"posterior_recompute_receipts.csv"))
write_json_atomic(list(status="PASS_REAL_SYNTHETIC_POSTERIOR_AUDIT",fits_reopened=32,full_panel_projection_strata=16,raw_rows_recomputed=sum(r$RowsChecked[r$Check=="posterior_to_OOF"]),panel_rows_recomputed=sum(r$RowsChecked[r$Check=="posterior_to_full_panel"]),max_absolute_error=max(r$MaximumAbsoluteDifference),tampered_prediction_cases=48,tampered_logscore_cases=32,source="fitted_posteriors_plus_current_synthetic_inputs; independent_R_raw_likelihood",formal_research_fits=0),file.path(out,"posterior_audit_status.json"))
cat("UNEQUAL_POSTERIOR_AUDIT_PASS: raw OOF/full panel values reproduced from real synthetic fitted posteriors; forged rows rejected\n")
