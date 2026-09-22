#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
out<-file.path(root,"review","integration");state<-prepare_state(file.path(out,"input"))
bundles<-list()
for(r in V3_ROUTES)for(m in c("Null","M1"))bundles[[paste(r,m,"species_equal",sep="|")]]<-readRDS(fit_path_v3(out,r,m,"species_equal","integration",1))
new<-state$sites[1:2,];new$Species<-c("unseen_a","unseen_b");new$Site196[2]<-"MISSING"
x<-external_prediction_table(state,bundles,new,models=c("Null","M1"),train_weightings="species_equal",allow_diagnostic_warnings=TRUE)
validate_prediction_table_v3(x)
for(r in V3_ROUTES){z<-x[x$Model=="Null"&x$Route==r,];stopifnot(diff(z$Point)==0,diff(z$CrI_lower)==0);if(r=="joint_bb")stopifnot(diff(z$PI_lower)==0)}
cat("EXTERNAL_PASS: real Null/M1 posterior, missing category, batch invariance; integration data only\n")
