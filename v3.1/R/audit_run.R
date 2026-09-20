audit_plan_v3_impl <- function(state,root,run_dir,review_dir) {
  folds<-make_fold_tables_v3(state);expected<-task_plan_v3(state,folds)
  plan<-read.csv(file.path(run_dir,"run_plan.csv"),stringsAsFactors=FALSE)
  if(!identical(names(plan),names(expected))||!isTRUE(all.equal(plan,expected,check.attributes=FALSE)))stop("Run plan differs from canonical full grid/current inputs/config")
  receipts<-list();issues<-character()
  for(i in seq_len(nrow(plan))) {
    row<-plan[i,];p<-fit_path_v3(root,row$Route,row$Model,row$TrainWeighting,row$Design,if(is.na(row$Fold))NULL else row$Fold)
    result<-tryCatch({
      b<-readRDS(p);active<-if(row$Route=="binary")state$binary_species else state$joint_species
      tr<-if(row$Design=="full")active else setdiff(active,folds[[row$Design]][[row$Route]]$Species[folds[[row$Design]][[row$Route]]$Fold==row$Fold])
      spec<-fit_spec_v3(state,row$Route,row$Model,tr,row$TrainWeighting,file.path(root,"stan","joint_bb.stan"),seed=row$Seed)
      d<-validate_fitted_bundle_v3(b,spec,require_pass=TRUE)
      list(ok=TRUE,key=b$key,reason="identity_data_code_recomputed_diagnostics_pass")
    },error=function(e)list(ok=FALSE,key=NA_character_,reason=conditionMessage(e)))
    receipts[[i]]<-cbind(row,data.frame(Pass=result$ok,FitKey=result$key,Reason=result$reason))
    if(!result$ok)issues<-c(issues,paste(row$FitID,result$reason))
  }
  rec<-do.call(rbind,receipts);write_csv_atomic(rec,file.path(review_dir,"fit_audit.csv"))
  if(!length(issues)) {
    tryCatch({
      verify_derived_outputs_v3(root,state)
      for(s in c("cv","predict","ppc"))verify_stage_receipt_v3(root,state,s)
      ev<-read.csv(file.path(root,"results","cv_record_predictions.csv"),stringsAsFactors=FALSE)
      validate_cv_evidence_v3(state,ev,folds)
      if(any(ev$RunPurpose!="formal"))stop("Test evidence cannot be audited as formal results")
      for(i in seq_len(nrow(rec)))if(rec$Design[i]!="full") {
        r<-rec[i,];e<-subset(ev,Design==r$Design&Fold==r$Fold&Route==r$Route&Model==r$Model&TrainWeighting==r$TrainWeighting)
        if(any(e$FitKey!=r$FitKey))stop("Evidence FitKey mismatch")
      }
      fm<-read.csv(file.path(root,"results","cv_fold_metrics.csv"));if(nrow(fm)!=480L||anyDuplicated(fm[,c("Design","Route","Model","TrainWeighting","EvalWeighting","Fold")]))stop("Invalid fold metric grid")
      for(i in seq_len(nrow(fm))) {
        r<-fm[i,];e<-subset(ev,Design==r$Design&Fold==r$Fold&Route==r$Route&Model==r$Model&TrainWeighting==r$TrainWeighting)
        score<-evaluate_evidence(e,r$EvalWeighting,r$Route)
        for(n in intersect(names(score),names(fm)))if(!isTRUE(all.equal(score[[n]],r[[n]],tolerance=1e-10,check.attributes=FALSE)))stop("Fold score mismatch: ",n)
      }
      summary<-summarize_cv_metrics_v3(ev,fm);stored<-read.csv(file.path(root,"results","cv_metrics_summary.csv"))
      if(nrow(summary)!=64L||!isTRUE(all.equal(stored,summary,tolerance=1e-10,check.attributes=FALSE)))stop("CV summary mismatch")
      pred<-read.csv(file.path(root,"results","full_panel_predictions.csv"));validate_prediction_table_v3(pred)
      grid<-expand.grid(Species=state$sites$Species,Route=V3_ROUTES,Model=V3_MODELS,TrainWeighting=V3_TRAIN_WEIGHTINGS,stringsAsFactors=FALSE)
      key<-function(x)do.call(paste,c(x[,names(grid)],sep="|"))
      if(nrow(pred)!=nrow(grid)||!setequal(key(pred),key(grid)))stop("Full panel grid mismatch")
      required<-c("model_vs_null.csv","training_method_comparisons.csv","calibration_bins.csv","roc_coordinates.csv","training_ppc_summary.csv")
      for(f in required)if(!file.exists(file.path(root,"results",f)))stop("Missing output: ",f)
      if(!file.exists(file.path(root,"reports","REPORT_v3_1.md")))stop("Missing full result report")
    },error=function(e)issues<<-c(issues,conditionMessage(e)))
  }
  status<-if(length(issues))"FAILED" else "PASS"
  write_json_atomic(list(status=status,version=V3_VERSION,expected_tasks=nrow(expected),fits_checked=nrow(rec),fits_passed=sum(rec$Pass),issues=issues),file.path(review_dir,"audit_v3.json"))
  if(length(issues))stop("Formal audit failed: ",paste(head(issues,5),collapse="; "))
  invisible(TRUE)
}

audit_plan_v3 <- function(state,root,run_dir,review_dir) {
  p<-file.path(review_dir,"audit_v3.json");write_json_atomic(list(status="RUNNING",version=V3_VERSION),p)
  tryCatch(audit_plan_v3_impl(state,root,run_dir,review_dir),error=function(e){write_json_atomic(list(status="FAILED",version=V3_VERSION,reason=conditionMessage(e)),p);stop(e)})
}
