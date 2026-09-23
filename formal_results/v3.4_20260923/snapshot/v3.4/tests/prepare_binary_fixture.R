#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
options(warn=1)
source(file.path(root,"tests","fixtures_v32.R"))
out<-file.path(root,"review","unequal_integration");state<-make_unequal_fixture_v32(out)
f<-data.frame(Species=state$sites$Species,Fold=rep(1:2,each=6L))
for(m in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS)for(fold in 1:2) {
  tr<-setdiff(state$binary_species,f$Species[f$Fold==fold])
  fit_bundle_v3(state,"binary",m,tr,tw,out,"integration",fold,file.path(root,"stan","joint_bb.stan"),iter=600L,warmup=300L,chains=2L,cores=2L,seed=V3_SEED+fold+match(m,V3_MODELS))
}
cat("SYNTHETIC_BINARY_SUBSET_READY: 16 fits; diagnostic status retained; no research fits\n")
