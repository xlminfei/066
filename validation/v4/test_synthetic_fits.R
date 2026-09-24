# Real fits on explicitly synthetic responses only; no research-data fitting.
args<-commandArgs(TRUE);root<-args[1];out<-args[2]
source(file.path(root,"R/load.R"));load_v4(root)
dir.create(out,recursive=TRUE,showWarnings=FALSE)
species<-sprintf("SYNTHETIC_%02d",1:12)
sites<-data.frame(Species=species,Site3=rep(c("C","A"),6),Site20=rep(c("K","E"),6),
  Site117=rep(c("K","S"),6),Site151="C",Site196=rep(c("C","Q"),6),Site315=rep(c("K","T"),6))
obs<-do.call(rbind,lapply(seq_along(species),function(i) {
  id<-paste0(species[i],"_",1:4)
  data.frame(RecordID=id,ExperimentID=id,Species=species[i],
    Type=c("count","count","exact","interval"),Events=c(0,10,NA,NA),Total=c(10,10,NA,NA),
    Exact=c(NA,NA,if(i%%3==0)1 else if(i%%2==0).25 else .8,NA),
    Lower=c(NA,NA,NA,.4),Upper=c(NA,NA,NA,if(i%%2==0).5 else 1),SourceID=id)
}))
folds<-setNames(lapply(names(DESIGNS),function(d)setNames(lapply(ROUTES,function(r)
  data.frame(Species=species,Fold=rep(seq_len(DESIGNS[[d]]),length.out=length(species)))),ROUTES)),names(DESIGNS))
state<-prepare_from_tables(obs,sites,folds);state$input_hashes<-c(synthetic=sha256_object(list(obs,sites)))
write.csv(obs,file.path(out,"synthetic_observations.csv"),row.names=FALSE)
write.csv(sites,file.path(out,"synthetic_sites.csv"),row.names=FALSE)
ctl<-modifyList(SAMPLING,list(iter=2000L,warmup=1000L))
diags<-list();scored<-list()
for(route in ROUTES) {
  train<-species[1:8];held<-which(state$observations$Species%in%species[9:12] &
    if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
  spec<-fit_spec(state,route,"M1",train,file.path(root,"stan/joint_bb.stan"),sampling=ctl,seed=20260924L)
  path<-file.path(out,paste0("synthetic_",route,"_M1.rds"))
  bundle<-fit_from_spec(spec,path)
  validate_fit_cache(bundle,spec)
  if(!identical(bundle$diagnostics$Status,"PASS"))stop("Synthetic fit diagnostics did not pass: ",route)
  score<-if(route=="binary")binary_record_scores(bundle,state,held) else joint_record_scores(bundle,state,held)
  score$Route<-route;score$Model<-"M1";score$TrainWeighting<-TRAIN_WEIGHTING;score$RunPurpose<-"SYNTHETIC_INTERFACE_TEST"
  stopifnot(nrow(score)==length(held),all(is.finite(score$LogPredictiveDensityRaw)))
  value<-evaluate_evidence(score);stopifnot(all(is.finite(value$MeanLogScore)))
  panel<-panel_prediction(bundle,state);stopifnot(nrow(panel)==12)
  write.csv(panel,file.path(out,paste0("synthetic_panel_",route,".csv")),row.names=FALSE)
  write.csv(ppc_summary_for_bundle(bundle,state),file.path(out,paste0("synthetic_ppc_",route,".csv")),row.names=FALSE)
  reused<-capture.output(second<-fit_from_spec(spec,path))
  stopifnot(any(grepl("CACHE_VALID",reused)),identical(second$key,bundle$key))
  bad<-spec;bad$request$seed<-bad$request$seed+1L;bad$key<-sha256_object(bad$request)
  stopifnot(inherits(try(fit_from_spec(bad,path),silent=TRUE),"try-error"))
  diags[[length(diags)+1L]]<-cbind(Route=route,Purpose="SYNTHETIC_INTERFACE_TEST",bundle$diagnostics)
  scored[[length(scored)+1L]]<-score
  write.csv(do.call(rbind,diags),file.path(out,"synthetic_diagnostics.csv"),row.names=FALSE)
}
write.csv(do.call(rbind,scored),file.path(out,"synthetic_scores.csv"),row.names=FALSE)
write_json_atomic(list(status="PASS",purpose="SYNTHETIC_INTERFACE_TEST_ONLY",new_synthetic_fits=2L,
  real_research_fits=0L,sampling=ctl,diagnostic_thresholds_changed=FALSE,
  cached_reuse_checked=TRUE,stale_cache_rejected=TRUE,records_per_fit=48L,held_out_records=list(binary=14L,joint_bb=16L)),
  file.path(out,"synthetic_status.json"))
cat("V4_SYNTHETIC_FITS_PASS: two real MCMC fits on synthetic data; zero research fits\n")
