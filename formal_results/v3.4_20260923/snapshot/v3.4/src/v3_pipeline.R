#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root,configure=FALSE)
args<-commandArgs(TRUE);val<-function(k,default=NULL){i<-match(k,args);if(is.na(i)||i==length(args))default else args[i+1]}
stage<-val("--stage","preflight")
allowed<-c("preflight","prepare","smoke","fit","cv","predict","external","export","ppc","report","audit","all")
if(!stage%in%allowed)stop("Unknown stage")
if(any(args%in%c("--iter","--warmup","--chains","--cores","--seed","--config","--force")))stop("Set effective sampling/seed in config/analysis.json; smoke has explicit isolated settings")
run_with_status_v3(root,stage,function(){apply_analysis_config(read_config_v3(root));run_stage_v3(root,stage,list(new_data=val("--new-data"),out=val("--out")))})
