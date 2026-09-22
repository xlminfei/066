#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
state<-load_state_v3(root)
stopifnot(nrow(state$sites)==365L,nrow(state$observations)==153L,length(state$binary_species)==50L,length(state$joint_species)==51L)
folds<-make_fold_tables_v3(state);validate_fold_tables_v3(state,folds)
plan<-task_plan_v3(state,folds);stopifnot(nrow(plan)==256L,!anyNA(plan$WeightHash),!anyDuplicated(plan$FitID))
cat("PREPARED_PASS: 365/153/50/51; 256 identified tasks\n")
