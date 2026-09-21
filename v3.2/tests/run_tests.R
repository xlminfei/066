#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
for(f in c("test_contracts.R","test_release_regressions.R","test_scientific_contracts.R")) {
 cat("TEST_FILE",f,"\n")
 source(file.path(root,"tests",f),local=new.env(parent=.GlobalEnv))
}
cat("ALL INHERITED DETERMINISTIC TESTS PASSED (CURRENT V3.2 CODE)\n")
