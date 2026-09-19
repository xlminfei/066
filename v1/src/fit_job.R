source("/project/work/ratio_analysis_20260914/scripts/common.R",local=.GlobalEnv)
args<-commandArgs(trailingOnly=TRUE)
stopifnot(length(args)>=3L)
job_outcome<-args[[1L]];job_model<-args[[2L]];job_variant<-args[[3L]]
job_attempt<-if(length(args)>=4L)as.integer(args[[4L]])else 1L
stopifnot(job_outcome%in%c("binary","joint"),job_attempt>=1L,job_attempt<=3L)
job_id<-paste(job_outcome,job_model,job_variant,paste0("attempt",job_attempt),sep="__")
job_dir<-file.path(analysis_root,"runs","job_receipts",job_id)
dir.create(file.path(job_dir,"results"),recursive=TRUE,showWarnings=FALSE)
started_at<-format(Sys.time(),tz="UTC",usetz=TRUE)
atomic_json(list(status="RUNNING",job=job_id,pid=Sys.getpid(),started_at=started_at),file.path(job_dir,"status.json"))
tryCatch({
  initialize_manual()
  MODEL_NAME<-job_model;OUTCOME<-job_outcome;VARIANT<-job_variant
  if(job_variant!="primary") {
    block<-switch(job_variant,b_sd_025="04_STRONG_PRIOR",b_sd_100="04_WEAK_PRIOR",
      rho_beta22="04_ENDPOINT_PRIOR",beta_binomial="04_COUNT_DISPERSION",stop("Unknown variant"))
    run_block("04_模型检查与敏感性.md",block,overrides=list(MODEL_NAME=job_model))
  }
  if(job_attempt==2L) {ITER<-8000L;WARMUP<-4000L;ADAPT_DELTA<-.999;MAX_TREEDEPTH<-15L}
  if(job_attempt==3L) {ITER<-16000L;WARMUP<-8000L;ADAPT_DELTA<-.9995;MAX_TREEDEPTH<-15L}
  stopifnot(MODEL_NAME%in%prepared$model_grid$Model)
  if(OUTCOME=="binary") {
    run_block("02_独立分类模型.md","02_PREPARE")
    run_block("02_独立分类模型.md","02_FIT_SAVE",
              overrides=list(index_file=file.path(job_dir,"fit_index.csv")))
  } else {
    run_block("03_联合比率模型.md","03_STAN_MODEL")
    joint_code_hash<-digest::digest(joint_model_code,algo="sha256",serialize=FALSE)
    stopifnot(identical(readLines(file.path(analysis_root,"environment","joint_compiled.sha256")),joint_code_hash))
    joint_compiled<-readRDS(file.path(analysis_root,"environment","joint_compiled.rds"))
    run_block("03_联合比率模型.md","03_PREPARE")
    run_block("03_联合比率模型.md","03_FIT_SAVE",
              overrides=list(index_file=file.path(job_dir,"fit_index.csv")))
  }
  # Use the manual's diagnostics unmodified, with a job-specific output directory.
  actual_run_dir<-RUN_DIR
  RUN_DIR<-job_dir
  bundles<-setNames(list(bundle),MODEL_NAME)
  run_block("05_诊断与模型比较.md","05_DIAGNOSTICS")
  RUN_DIR<-actual_run_dir
  status<-if(all(diagnostics$Status=="PASS"))"PASS"else"NEEDS_REVIEW"
  atomic_json(list(status=status,job=job_id,outcome=OUTCOME,model=MODEL_NAME,variant=VARIANT,
    attempt=job_attempt,key=bundle$key,relative_file=relative_file,started_at=started_at,
    finished_at=format(Sys.time(),tz="UTC",usetz=TRUE),sampling=bundle$request$sampling,
    diagnostics=diagnostics),file.path(job_dir,"status.json"))
  cat("FORMAL_FIT_JOB_FINISHED",job_id,status,"\n")
},error=function(e) {
  atomic_json(list(status="ERROR",job=job_id,message=conditionMessage(e),
    started_at=started_at,finished_at=format(Sys.time(),tz="UTC",usetz=TRUE)),file.path(job_dir,"status.json"))
  stop(e)
})
