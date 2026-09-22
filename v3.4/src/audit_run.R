#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root,configure=FALSE)

run_with_status_v3(root,"audit",function(){apply_analysis_config(read_config_v3(root));audit_plan_v3(load_state_v3(root),root,file.path(root,"runs"),file.path(root,"review"))})
