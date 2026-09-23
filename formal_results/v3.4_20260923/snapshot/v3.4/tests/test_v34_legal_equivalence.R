#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
prior<-new.env(parent=.GlobalEnv);sys.source(file.path(root,"review","baseline_v3_3","R","bootstrap.R"),prior);prior$load_v3_modules(file.path(root,"review","baseline_v3_3"),envir=prior)
source(file.path(root,"tests","fixtures_v32.R"))
out<-file.path(root,"review","legal_equivalence");state<-make_unequal_fixture_v32(out)
oldfold<-prior$make_fold_tables_v3(state);newfold<-make_fold_tables_v3(state)
stopifnot(identical(oldfold,newfold),validate_fold_tables_v3(state,newfold))
for(d in names(newfold))for(r in V3_ROUTES)write_csv_atomic(newfold[[d]][[r]],file.path(out,paste0("unchanged_folds_",d,"_",r,".csv")))
sets<-list(
 saved_v32_real_synthetic_OOF=read.csv(file.path(root,"review","reused_evidence","saved_synthetic_OOF.csv"),stringsAsFactors=FALSE),
 v34_mock_fullgrid_OOF=read.csv(file.path(root,"review","fullgrid_synthetic","results","cv_record_predictions.csv"),stringsAsFactors=FALSE))
results<-list()
for(label in names(sets)){
 ev<-sets[[label]]
 for(design in unique(ev$Design))for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS){
  all<-subset(ev,Design==design&Route==route&Model==model&TrainWeighting==tw)
  for(fold in c(NA,sort(unique(all$Fold))))for(ew in V3_EVAL_WEIGHTINGS){
   e<-if(is.na(fold))all else all[all$Fold==fold,,drop=FALSE]
   before<-prior$evaluate_evidence(e,ew,route);after<-evaluate_evidence(e,ew,route)
   stopifnot(identical(before,after))
   results[[length(results)+1L]]<-data.frame(Source=label,Design=design,Route=route,Model=model,TrainWeighting=tw,Fold=fold,EvalWeighting=ew,Records=nrow(e),ExactIdentical=TRUE)
  }
 }
}
r<-do.call(rbind,results);write_csv_atomic(r,file.path(out,"scoring_equivalence_receipts.csv"))
write_json_atomic(list(status="PASS",default_fold_tables_identical=TRUE,metric_groups_compared=nrow(r),saved_synthetic_rows=nrow(sets[[1]]),mock_rows=nrow(sets[[2]]),all_metrics_exactly_identical=all(r$ExactIdentical),new_fits=0,real_data_fits=0),file.path(out,"status.json"))
cat("V34_LEGAL_INPUT_EQUIVALENCE_PASS: unchanged default folds and every metric field; no new fits\n")
