source("/project/work/ratio_analysis_20260914/scripts/common.R",local=.GlobalEnv)
args<-commandArgs(trailingOnly=TRUE)
stopifnot(length(args)>=3L)
job_outcome<-args[[1L]];job_model<-args[[2L]];job_design<-args[[3L]]
job_attempt<-if(length(args)>=4L)as.integer(args[[4L]])else 1L
stopifnot(job_outcome%in%c("binary","joint"),job_design%in%c("species","phylo_distance"),job_attempt%in%1:3)
job_id<-paste("cv",job_outcome,job_model,job_design,paste0("attempt",job_attempt),sep="__")
job_dir<-file.path(analysis_root,"runs","job_receipts",job_id)
dir.create(job_dir,recursive=TRUE,showWarnings=FALSE)
started_at<-format(Sys.time(),tz="UTC",usetz=TRUE)
atomic_json(list(status="RUNNING",job=job_id,pid=Sys.getpid(),started_at=started_at),file.path(job_dir,"status.json"))
tryCatch({
  initialize_manual()
  parent_receipt<-NULL
  for(attempt in 1:3) {
    parent_dir<-file.path(analysis_root,"runs","job_receipts",paste(job_outcome,job_model,"primary",paste0("attempt",attempt),sep="__"))
    parent_status<-file.path(parent_dir,"status.json")
    if(file.exists(parent_status) && jsonlite::read_json(parent_status)$status=="PASS")parent_receipt<-parent_dir
  }
  if(is.null(parent_receipt))stop("No passing current primary fit.")
  chosen_index<-utils::read.csv(file.path(parent_receipt,"fit_index.csv"),stringsAsFactors=FALSE)
  run_block("05_诊断与模型比较.md","05_LOAD",overrides=list(OUTCOME=job_outcome,VARIANT="primary",fit_index=chosen_index))
  diagnostics<-utils::read.csv(file.path(parent_receipt,"results",paste0("diagnostics_",OUTCOME,"_primary.csv")),stringsAsFactors=FALSE)
  parent_sampling<-bundles[[job_model]]$request$sampling
  iter_now<-as.integer(max(4000,parent_sampling$iter)*2^(job_attempt-1L))
  warmup_now<-as.integer(iter_now/2L)
  adapt_now<-max(parent_sampling$adapt_delta,c(.99,.999,.9995)[job_attempt])
  depth_now<-as.integer(max(parent_sampling$max_treedepth,if(job_attempt>1L)15L else 12L))
  run_block("06_留出验证.md","06_FOLDS",overrides=list(CV_TYPE=job_design,
    CV_ITER=iter_now,CV_WARMUP=warmup_now,CV_ADAPT_DELTA=adapt_now,CV_MAX_TREEDEPTH=depth_now))
  run_block("06_留出验证.md","06_SELECT",overrides=list(CV_MODEL=job_model))
  if(OUTCOME=="binary")run_block("06_留出验证.md","06_BINARY_CV")
  else {
    run_block("03_联合比率模型.md","03_STAN_MODEL")
    joint_compiled_code_hash<-digest::digest(joint_model_code,algo="sha256",serialize=FALSE)
    stopifnot(identical(readLines(file.path(analysis_root,"environment","joint_compiled.sha256")),joint_compiled_code_hash))
    joint_compiled<-readRDS(file.path(analysis_root,"environment","joint_compiled.rds"))
    run_block("06_留出验证.md","06_NATIVE_CV")
  }
  run_block("06_留出验证.md","06_SCORE",overrides=list(ci_file=file.path(job_dir,"cv_index.csv")))
  utils::write.csv(cv_bundle$fold_scores,file.path(job_dir,"fold_scores.csv"),row.names=FALSE)
  utils::write.csv(cv_bundle$diagnostics,file.path(job_dir,"fold_diagnostics.csv"),row.names=FALSE)
  stopifnot(nrow(cv_bundle$predictions)==nrow(cv_bundle$source),
    length(cv_bundle$fold_fits)==5L,all(is.finite(cv_bundle$fold_scores$ELPD)))
  atomic_json(list(status=cv_bundle$status,job=job_id,outcome=OUTCOME,model=CV_MODEL,
    cv_type=CV_TYPE,attempt=job_attempt,key=cv_bundle$key,parent_key=cv_bundle$parent_key,
    cv_dir=CV_DIR,cv_file=cv_file,fold_key=fold_key,sampling=cv_bundle$request$sampling,
    started_at=started_at,finished_at=format(Sys.time(),tz="UTC",usetz=TRUE),
    diagnostics=cv_bundle$diagnostics),file.path(job_dir,"status.json"))
  cat("FORMAL_CV_JOB_FINISHED",job_id,cv_bundle$status,"\n")
},error=function(e) {
  atomic_json(list(status="ERROR",job=job_id,message=conditionMessage(e),started_at=started_at,
    finished_at=format(Sys.time(),tz="UTC",usetz=TRUE)),file.path(job_dir,"status.json"))
  stop(e)
})
