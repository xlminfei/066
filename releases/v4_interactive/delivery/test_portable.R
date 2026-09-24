args<-commandArgs(TRUE);p_root<-args[1];p_out<-args[2]
dir.create(p_out,recursive=TRUE,showWarnings=FALSE)
p_expressions<-parse(file.path(p_root,"interactive_analysis.R"),keep.source=TRUE)
p_count<-0L
for(p_e in p_expressions) {
  p_lhs<-if(is.call(p_e)&&identical(p_e[[1]],as.name("<-"))&&is.symbol(p_e[[2]]))as.character(p_e[[2]]) else ""
  if(p_lhs=="bundle")break
  if(p_lhs=="project_dir")p_e[[3]]<-p_root
  if(p_lhs=="output_dir"&&is.call(p_e[[3]])&&identical(p_e[[3]][[1]],as.name("file.path")))p_e[[3]]<-p_out
  eval(p_e,envir=.GlobalEnv);p_count<-p_count+1L
}
check_interactive_example(root,output_dir,example_task,spec)
stopifnot(!dir.exists(file.path(output_dir,"fits")),nrow(run_plan)==128L,identical(spec$request$seed,example_task$Seed))
write_json_atomic(list(status="PASS",purpose="isolated_code_zip_pre_fit_expression_run",expressions=p_count,
  supplied_file_argument=any(grepl("^--file=",commandArgs(FALSE))),fit_calls=0L,
  analysis_id=analysis_identity(root),code_dependencies="only extracted v4 package; no old repository or native fit mount"),
  file.path(p_out,"portable_status.json"))
cat("PORTABLE_INTERACTIVE_PRE_FIT_PASS; no MCMC\n")
