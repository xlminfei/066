args <- commandArgs(TRUE)
root <- args[1]; out <- args[2]
source(file.path(root,"R","bootstrap.R")); load_v3_modules(root)
state <- load_state_v3(root)
verify_derived_outputs_v3(root,state)
for(stage in c("cv","predict","ppc")) verify_stage_receipt_v3(root,state,stage)
plan <- read.csv(file.path(root,"runs","run_plan.csv"),stringsAsFactors=FALSE)
rows <- vector("list",nrow(plan))
for(i in seq_len(nrow(plan))) {
  z<-plan[i,,drop=FALSE]
  path<-fit_path_v3(root,z$Route,z$Model,z$TrainWeighting,z$Design,if(is.na(z$Fold))NULL else z$Fold)
  b<-readRDS(path)
  stopifnot(b$key == read.csv(file.path(root,"review","fit_audit.csv"),stringsAsFactors=FALSE)$FitKey[i])
  rows[[i]]<-cbind(z[,c("FitID","Route","Model","TrainWeighting","Design","Fold")],b$diagnostics,
    data.frame(StoredFitKey=b$key,StoredChains=b$request$sampling$chains,StoredIter=b$request$sampling$iter,StoredWarmup=b$request$sampling$warmup))
  rm(b)
  if(i%%32L==0L) {cat("SAVED_DIAGNOSTICS_READ",i,"/",nrow(plan),"\n");flush.console();gc(FALSE)}
}
diag<-do.call(rbind,rows)
write.csv(diag,file.path(out,"all_256_saved_diagnostics.csv"),row.names=FALSE,na="")
stopifnot(nrow(diag)==256L,all(diag$Status=="PASS"),all(diag$StoredChains==4),all(diag$StoredIter==4000),all(diag$StoredWarmup==2000))
jsonlite::write_json(list(status="PASS",check="source_input_contract_and_derived_stage_hashes_and_read_saved_fit_diagnostics",fits=256,
  fits_passed=sum(diag$Status=="PASS"),max_rhat=max(diag$MaxRhat),min_bulk_ess=min(diag$MinBulkESS),min_tail_ess=min(diag$MinTailESS),
  divergences=sum(diag$Divergences),treedepth_hits=sum(diag$TreeDepthHits),min_ebfmi=min(diag$MinEBFMI),
  new_fits=0,new_mcmc=0,diagnostic_method="read saved diagnostic tables; main final audit already recomputed them for all fits"),
  file.path(out,"fresh_receipt_and_diagnostic_check.json"),auto_unbox=TRUE,pretty=TRUE)
cat("POSTRUN_RECEIPTS_AND_SAVED_DIAGNOSTICS_PASS; no refits or MCMC\n")
