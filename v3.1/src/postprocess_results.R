#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)

state<-load_state_v3(root);ev<-read.csv(file.path(root,"results","cv_record_predictions.csv"));validate_cv_evidence_v3(state,ev,make_fold_tables_v3(state));postprocess_v3(root,ev)
