#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
dirs<-c(file.path(root,"review","integration"),file.path(root,"review","weighted_posterior"))
files<-unlist(lapply(dirs,function(d)list.files(file.path(d,"runs"),"fit\\.rds$",recursive=TRUE,full.names=TRUE)))
if(length(files)!=18L)stop("Run the sixteen-fit integration and two weighted-posterior tests first")
snapshots<-list();inventory<-list()
for(p in files) {
  b<-readRDS(p);key<-substring(p,nchar(root)+2)
  snapshots[[key]]<-list(purpose="synthetic_validation_only_not_a_production_model",route=b$route,model=b$model,train_weighting=b$train_weighting,
    request=b$request,diagnostics=b$diagnostics,blueprint=b$blueprint,data=b$data,posterior=extract_parameters_v3(b),
    log_lik=if(b$route=="joint_bb")rstan::extract(b$fit,pars="log_lik",permuted=TRUE)$log_lik else NULL)
  inventory[[key]]<-data.frame(Path=key,Bytes=file.info(p)$size,SHA256=sha256_file(p),FitKey=b$key,FitPayloadHash=b$fit_payload_hash,
    Included="numerical snapshot in Git; original native fit also included under working-v3 in the complete Release archive")
}
save_rds_atomic(snapshots,file.path(root,"review","validation_snapshots.rds"))
write_csv_atomic(do.call(rbind,inventory),file.path(root,"review","compiled_fit_inventory.csv"))
cat("VALIDATION_SNAPSHOT_PASS",length(files),"synthetic fits; numerical snapshot omits native payload; full originals are separately archived\n")
