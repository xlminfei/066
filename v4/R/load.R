# Shared loading and CLI routing. No model is run when this file is sourced.
load_v4 <- function(root,envir=.GlobalEnv) {
  root<-normalizePath(root,mustWork=TRUE)
  for(p in c("digest","jsonlite"))if(!requireNamespace(p,quietly=TRUE))stop("Missing package ",p)
  source(file.path(root,"settings.R"),local=envir)
  for(n in c("checks","data_encoding","model_functions","metric_functions","plot_functions"))
    source(file.path(root,"R",paste0(n,".R")),local=envir)
  for(n in c("01_prepare.R","02_fit.R","03_evaluate.R","04_plot.R"))source(file.path(root,n),local=envir)
  invisible(root)
}
load_prepared <- function(root,out) {
  check_settings();check_input_hashes(root)
  path<-file.path(out,"prepared.rds");if(!file.exists(path))stop("Run 01_prepare.R first")
  state<-readRDS(path)
  if(!identical(state$analysis_id,analysis_identity(root)))stop("Code/settings changed; use a fresh output and run prepare")
  if(!identical(state$input_hashes,INPUT_SHA256))stop("Prepared input identity mismatch")
  fresh<-read_frozen_state(root)
  for(n in names(fresh))if(!identical(state[[n]],fresh[[n]]))stop("Prepared state differs from frozen inputs: ",n)
  state
}
check_complete_outputs <- function(state,out) {
  plan<-task_plan(state);read<-function(n)read.csv(file.path(out,n),stringsAsFactors=FALSE)
  d<-read("fit_diagnostics.csv")
  check_grid(d,plan,"FitID",c("Route","Model","Design","Fold","Seed","TrainWeighting","FitKey","Status",
      "MaxRhat","MinBulkESS","MinTailESS","Divergences","TreeDepthHits","MinEBFMI"))
  d<-d[match(plan$FitID,d$FitID),]
  for(n in c("Route","Model","Design","Fold","Seed","TrainWeighting"))
    if(!isTRUE(all.equal(d[[n]],plan[[n]],check.attributes=FALSE)))stop("Diagnostic task mismatch")
  if(any(d$Status!="PASS"))stop("Failed diagnostic in completed run")
  fmanifest<-read("fit_manifest.csv")
  check_grid(fmanifest,plan,"FitID",c("Path","Bytes","SHA256","FitKey"))
  fmanifest<-fmanifest[match(plan$FitID,fmanifest$FitID),]
  if(!identical(fmanifest$Path,file.path("fits",paste0(plan$FitID,".rds")))||
     !identical(fmanifest$FitKey,d$FitKey))stop("Fit inventory identity mismatch")
  for(i in seq_len(nrow(fmanifest))) {
    f<-file.path(out,fmanifest$Path[i])
    if(!file.exists(f)||file.info(f)$size!=fmanifest$Bytes[i]||
       sha256_file(f)!=fmanifest$SHA256[i])stop("Missing or changed fit file: ",f)
  }
  e<-read("cv_record_predictions.csv");check_cv_evidence(state,e)
  m<-read("cv_metrics_summary.csv");f<-read("cv_fold_metrics.csv")
  h<-read("hypothesis_tests.csv");p<-read("full_panel_predictions.csv")
  expected<-expand.grid(Design=names(DESIGNS),Route=ROUTES,Model=MODELS,
    TrainWeighting=TRAIN_WEIGHTING,EvalWeighting=EVAL_WEIGHTING,stringsAsFactors=FALSE)
  keys<-c("Design","Route","Model","TrainWeighting","EvalWeighting")
  check_grid(m,expected,keys,c("AUC","ELPD","MeanLogScore","MAE","RMSE","Bias"))
  ef<-plan[plan$Design!="full",c("Design","Route","Model","TrainWeighting","Fold")];ef$EvalWeighting<-EVAL_WEIGHTING
  check_grid(f,ef,c(keys,"Fold"),c("AUC","ELPD","MeanLogScore","MAE","RMSE","Bias"))
  expected_h<-do.call(rbind,lapply(ROUTES,function(r)expand.grid(Route=r,
    Metric=if(r=="binary")c("AUC","MeanLogScore") else c("MeanLogScore","MAE","RMSE"),
    Design=names(DESIGNS),TrainWeighting=TRAIN_WEIGHTING,EvalWeighting=EVAL_WEIGHTING,
    Model=c("M1","M2","M3"),stringsAsFactors=FALSE)))
  check_grid(h,expected_h,c(keys,"Metric"),c("Estimate","Difference","SE_approx","CI95_lower","CI95_upper","P_approx","P_BH3"))
  recalculated<-adjust_hypothesis_families(h)
  if(!isTRUE(all.equal(recalculated$P_BH3,h$P_BH3,tolerance=1e-12)))stop("BH3 values changed")
  ep<-expand.grid(Species=state$sites$Species,Route=ROUTES,Model=MODELS,
                 TrainWeighting=TRAIN_WEIGHTING,stringsAsFactors=FALSE)
  check_grid(p,ep,c("Species","Route","Model","TrainWeighting"))
  validate_prediction_table(p)
  for(stage in c("fit","evaluate","plot"))check_stage_receipt(stage,state,out)
  invisible(TRUE)
}
run_stage_cli <- function(stage) {
  script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
  root<-dirname(normalizePath(script,mustWork=TRUE));args<-commandArgs(TRUE)
  if(length(args)&&(!identical(length(args),2L)||args[1]!="--output"))stop("Usage: Rscript <entry>.R [--output DIRECTORY]")
  out<-if(length(args))args[2] else file.path(root,"output")
  dir.create(out,recursive=TRUE,showWarnings=FALSE);out<-normalizePath(out,mustWork=TRUE)
  load_v4(root);state<-NULL
  update<-function(status,message=NULL)write_json_atomic(list(version=VERSION,stage=stage,status=status,
      at=format(Sys.time(),tz="UTC",usetz=TRUE),message=message),file.path(out,"status.json"))
  update("RUNNING")
  tryCatch({
    state<-if(stage%in%c("all","prepare"))prepare_stage(root,out) else load_prepared(root,out)
    if(stage%in%c("fit","all"))fit_stage(root,state,out)
    if(stage%in%c("evaluate","all")) {
      check_stage_receipt("fit",state,out)
      evaluate_stage(state,read.csv(file.path(out,"cv_record_predictions.csv"),stringsAsFactors=FALSE),out)
      evaluation_files<-c("cv_fold_metrics.csv","cv_metrics_summary.csv","hypothesis_tests.csv",
        "roc_coordinates.csv","calibration_bins.csv","quantitative_plot_source.csv","quantitative_bias_summary.csv",
        "auc_fold_species_support.csv","bootstrap_draws.rds","bootstrap_multiplicities.rds")
      stage_receipt("evaluate",state,out,evaluation_files)
    }
    if(stage%in%c("plot","all")) {
      check_stage_receipt("fit",state,out);check_stage_receipt("evaluate",state,out)
      plot_stage(state,out);check_complete_outputs(state,out)
      flags<-read.csv(file.path(out,"training_ppc_summary.csv"))
      update(if(any(flags$Status=="REVIEW_REQUIRED"))"COMPLETE_WITH_REVIEW_FLAGS" else "COMPLETE")
    } else update(paste0(toupper(stage),"_COMPLETE"))
    invisible(TRUE)
  },error=function(e){update("FAILED",conditionMessage(e));stop(e)})
}
