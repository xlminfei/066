# Stage 2: fit 8 full models and 120 held-out models; save diagnostics immediately.
panel_prediction <- function(bundle,state) {
  m<-binary_prediction_draws(bundle,state)
  pi<-if(bundle$route=="joint_bb")joint_predictive_draws(bundle,state) else NULL
  view<-state;view$blueprints[[blueprint_key(bundle$route,bundle$model)]]<-bundle$blueprint
  status<-assess_applicability(view,bundle$model,bundle$route,bundle$train_species)
  z<-cbind(data.frame(Species=state$sites$Species,Route=bundle$route,Model=bundle$model,
    TrainWeighting=TRAIN_WEIGHTING),summarize_prediction_draws(m,pi),
    status[,setdiff(names(status),c("Species","Route","Model")),drop=FALSE])
  z$PredictionTarget<-if(bundle$route=="binary")"Pr_HIGH" else "mean_ratio_and_future_exact_report_PI"
  validate_prediction_table(z);z
}
fit_stage <- function(root,state,output_dir,fit_function=fit_from_spec) {
  for(p in c("brms","rstan","posterior"))if(!requireNamespace(p,quietly=TRUE))stop("Missing package: ",p)
  plan<-task_plan(state);diagnostics<-list();inventory<-list();evidence<-list();panel<-list();ppc<-list()
  for(i in seq_len(nrow(plan))) {
    task<-plan[i,];route<-task$Route;model<-task$Model;design<-task$Design
    active<-if(route=="binary")state$binary_species else state$joint_species
    held<-if(design=="full")character() else {
      f<-state$fold_tables[[design]][[route]];f$Species[f$Fold==task$Fold]
    }
    train<-setdiff(active,held)
    if(length(intersect(train,held)))stop("Species leaked across train/test")
    spec<-fit_spec(state,route,model,train,file.path(root,"stan/joint_bb.stan"),seed=task$Seed)
    fit_file<-file.path("fits",paste0(task$FitID,".rds"))
    bundle<-fit_function(spec,file.path(output_dir,fit_file))
    inventory[[length(inventory)+1L]]<-data.frame(FitID=task$FitID,Path=fit_file,
      Bytes=file.info(file.path(output_dir,fit_file))$size,SHA256=sha256_file(file.path(output_dir,fit_file)),FitKey=bundle$key)
    write_csv_atomic(do.call(rbind,inventory),file.path(output_dir,"fit_manifest.csv"))
    d<-cbind(task,FitKey=bundle$key,bundle$diagnostics)
    diagnostics[[length(diagnostics)+1L]]<-d
    write_csv_atomic(do.call(rbind,diagnostics),file.path(output_dir,"fit_diagnostics.csv"))
    if(!identical(as.character(bundle$diagnostics$Status),"PASS"))stop("Sampling diagnostics failed: ",task$FitID)
    if(design=="full") {
      panel[[length(panel)+1L]]<-panel_prediction(bundle,state)
      ppc[[length(ppc)+1L]]<-ppc_summary_for_bundle(bundle,state)
      write_csv_atomic(do.call(rbind,panel),file.path(output_dir,"full_panel_predictions.csv"))
      write_csv_atomic(do.call(rbind,ppc),file.path(output_dir,"training_ppc_summary.csv"))
    } else {
      held_rows<-which(state$observations$Species%in%held &
        if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
      scored<-if(route=="binary")binary_record_scores(bundle,state,held_rows) else joint_record_scores(bundle,state,held_rows)
      view<-state;view$blueprints[[blueprint_key(route,model)]]<-bundle$blueprint
      flags<-assess_applicability(view,model,route,train)
      flags<-flags[,setdiff(names(flags),c("Model","Route","HasResponseData")),drop=FALSE]
      scored<-merge(scored,flags,by="Species",all.x=TRUE,sort=FALSE)
      scored$Design<-design;scored$Fold<-task$Fold;scored$Route<-route;scored$Model<-model
      scored$TrainWeighting<-TRAIN_WEIGHTING;scored$FitKey<-bundle$key;scored$RunPurpose<-"formal"
      evidence[[length(evidence)+1L]]<-scored
      write_csv_atomic(do.call(rbind,evidence),file.path(output_dir,"cv_record_predictions.csv"))
    }
    cat("TASK_COMPLETE",i,"/",nrow(plan),task$FitID,"\n");flush.console()
    rm(bundle);invisible(gc(FALSE))
  }
  e<-do.call(rbind,evidence);check_cv_evidence(state,e)
  pr<-do.call(rbind,panel);validate_prediction_table(pr)
  if(nrow(pr)!=length(ROUTES)*length(MODELS)*nrow(state$sites))stop("Incomplete panel predictions")
  if(nrow(do.call(rbind,diagnostics))!=nrow(plan))stop("Incomplete fit diagnostics")
  stage_receipt("fit",state,output_dir)
  invisible(e)
}
if(sys.nframe()==0L) {
  script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
  source(file.path(dirname(normalizePath(script)),"R/load.R"));run_stage_cli("fit")
}
