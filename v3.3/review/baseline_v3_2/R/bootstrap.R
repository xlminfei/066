resolve_v3_root <- function(args=commandArgs(TRUE),script=NULL) {
  i<-match("--root",args)
  candidate<-if(!is.na(i)&&i<length(args))args[i+1] else Sys.getenv("V3_ROOT","")
  if(!nzchar(candidate)) {
    if(is.null(script))script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
    if(length(script)!=1||is.na(script))stop("Specify --root or V3_ROOT")
    candidate<-dirname(dirname(script))
  }
  candidate<-normalizePath(candidate,winslash="/",mustWork=TRUE)
  if(!file.exists(file.path(candidate,"R","config.R")))stop("Invalid version root: ",candidate)
  candidate
}
load_v3_modules <- function(root,envir=.GlobalEnv,configure=TRUE) {
  for(f in c("config","data_encoding","weights","metrics","applicability","cache_io","fitting","prediction","prediction_audit","cross_validation","comparison","plotting","quantitative_diagnostics","ppc","provenance","reporting","audit_run","workflow"))source(file.path(root,"R",paste0(f,".R")),local=envir)
  if(configure)get("apply_analysis_config",envir)(jsonlite::read_json(file.path(root,"config","analysis.json"),simplifyVector=TRUE))
  invisible(root)
}
