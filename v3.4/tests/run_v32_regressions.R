#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
scripts<-c("run_tests.R","test_v32_metrics.R","test_quantitative_diagnostics.R","run_audit_deterministic.R","test_binary_template_key.R","test_input_support_counts.R","parse_all.R")
rows<-list()
for(script in scripts) {
  cat("REGRESSION_START",script,"\n");flush.console()
  output<-suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),c(shQuote(file.path(root,"tests",script)),"--root",shQuote(root)),stdout=TRUE,stderr=TRUE))
  status<-attr(output,"status");if(is.null(status))status<-0L
  writeLines(output,file.path(root,"review",paste0("final_",sub("\\.R$","",script),".log")))
  rows[[length(rows)+1L]]<-data.frame(Script=script,ExitStatus=status,Pass=status==0L)
  write_csv_atomic(do.call(rbind,rows),file.path(root,"review","regression_runner.csv"))
  cat(paste(output,collapse="\n"),"\n")
  if(status!=0L)stop("Regression failed: ",script)
}
cat("V32_REGRESSION_RUNNER_PASS: separate processes; no real-data fit or scoring\n")
