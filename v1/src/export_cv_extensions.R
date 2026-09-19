# Postprocessing only. This file never calls a fitting, update, or sampling method.
# Usage: Rscript export_cv_extensions.R <cv_bundle.rds> <parent_bundle.rds> <new_output_dir>
# Self-check: Rscript export_cv_extensions.R --self-test
EXTENSION_VERSION <- "cv_extensions_20260914_v1"
PREDICTIVE_SEED_BASE <- 20260914L
POINT_RULE <- "posterior_mean_of_species_expected_ratio_m"
needed <- c("rstan","brms","posterior","matrixStats","digest","jsonlite","scoringRules")
missing <- needed[!vapply(needed,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing))stop("Missing postprocessing packages: ",paste(missing,collapse=", "))
versions <- vapply(needed,function(p)as.character(utils::packageVersion(p)),character(1))
assert <- function(ok,message) { if(!isTRUE(ok))stop(message,call.=FALSE) }
lme <- function(x) { assert(length(x)>0L && all(is.finite(x)),"Non-finite/empty log predictive sample");matrixStats::logSumExp(x)-log(length(x)) }
sha <- function(path)digest::digest(file=path,algo="sha256")
as_chain_matrix <- function(x) {
  assert(length(dim(x))==3L,"Expected iteration x chain x variable source array")
  d<-dim(x);ans<-matrix(x,nrow=d[1]*d[2],ncol=d[3],dimnames=list(NULL,dimnames(x)[[3]]))
  # Check first/last draws of every chain and variable against the original array.
  for(ch in seq_len(d[2]))for(it in unique(c(1L,d[1])))
    assert(identical(as.numeric(ans[(ch-1L)*d[1]+it,]),as.numeric(x[it,ch,])),"Chain/iteration flattening mismatch")
  ans
}
stan_array <- function(fit,pars)rstan::extract(fit,pars=pars,permuted=FALSE,inc_warmup=FALSE)
quantile_rows <- function(x,probs,type=7L) {
  z<-apply(x,2L,stats::quantile,probs=probs,names=FALSE,type=type)
  matrix(z,nrow=length(probs),ncol=ncol(x))
}
mc_summary <- function(log_joint) {
  assert(is.matrix(log_joint) && nrow(log_joint)>=4L && ncol(log_joint)>=2L && all(is.finite(log_joint)),"Invalid MCMC log-joint matrix")
  shift<-max(log_joint);scaled<-exp(log_joint-shift);average<-mean(scaled)
  assert(is.finite(average) && average>0,"Zero/non-finite stabilized likelihood mean")
  mcse<-if(length(unique(as.vector(scaled)))==1L)0 else as.numeric(posterior::mcse_mean(scaled))
  log_mcse<-mcse/average
  weight<-as.vector(scaled)/sum(scaled)
  neff_contribution<-1/sum(weight^2)
  chains<-apply(log_joint,2L,lme)
  reasons<-character()
  if(!is.finite(log_mcse))reasons<-c(reasons,"MCSE_NOT_FINITE")
  if(is.finite(log_mcse) && log_mcse>.1)reasons<-c(reasons,"DELTA_LOG_MCSE_GT_0.1")
  if(max(weight)>.1)reasons<-c(reasons,"MAX_CONTRIBUTION_GT_0.1")
  if(neff_contribution<100)reasons<-c(reasons,"EFFECTIVE_CONTRIBUTIONS_LT_100")
  if(diff(range(chains))>.5)reasons<-c(reasons,"CHAIN_LOG_SCORE_RANGE_GT_0.5")
  # These predeclared screens are descriptive review triggers, not calibrated tests.
  data.frame(ReconstructedELPD=lme(as.vector(log_joint)),DrawCount=length(log_joint),
    IterationsPerChain=nrow(log_joint),Chains=ncol(log_joint),LogLikelihoodShift=shift,
    MeanStabilizedLikelihood=average,MCMC_MCSE_StabilizedLikelihood=mcse,
    DeltaMethod_MCSE_LogPredictive=log_mcse,MaxNormalizedContribution=max(weight),
    EffectiveContributionCount=neff_contribution,ChainLogPredictiveMin=min(chains),
    ChainLogPredictiveMax=max(chains),ChainLogPredictiveRange=diff(range(chains)),
    MCReviewStatus=if(length(reasons))"REVIEW_REQUIRED"else"NO_SCREEN_FLAG",
    MCReviewReasons=paste(reasons,collapse=";"),stringsAsFactors=FALSE)
}
simulate_results <- function(m,kind,total=NULL,rho=NULL,shape_a=NULL,shape_b=NULL,count_phi=NULL) {
  n<-length(m)
  assert(all(is.finite(m)) && all(m>=0 & m<=1),"Invalid expected ratio draws")
  if(kind=="count") {
    assert(length(total)==1L && total>=1 && total==floor(total),"Invalid original count denominator")
    probability<-if(is.null(count_phi))m else stats::rbeta(n,m*count_phi,(1-m)*count_phi)
    ans<-stats::rbinom(n,total,probability)/total
  } else if(kind=="exact") {
    assert(length(rho)==n && length(shape_a)==n && length(shape_b)==n,"Exact predictive dimensions differ")
    at_one<-stats::rbinom(n,1,rho*m)
    ans<-ifelse(at_one==1,1,stats::rbeta(n,shape_a,shape_b))
  } else stop("Ordinary posterior predictive simulation is restricted to count/exact")
  assert(all(is.finite(ans)) && all(ans>=0 & ans<=1),"Invalid posterior predictive values")
  ans
}
aggregate_metrics <- function(rows,by_fold=FALSE) {
  selectors<-if(by_fold)sort(unique(rows$Fold))else NA_integer_
  ans<-list()
  for(f in selectors)for(kind in c("count+exact","count","exact")) {
    z<-rows
    if(by_fold)z<-z[z$Fold==f,,drop=FALSE]
    if(kind!="count+exact")z<-z[z$Type==kind,,drop=FALSE]
    if(!nrow(z))next
    ans[[length(ans)+1L]]<-data.frame(Fold=f,Type=kind,NRecords=nrow(z),NSpecies=length(unique(z$Species)),
      MAE=mean(z$AbsoluteError),RMSE=sqrt(mean(z$SquaredError)),CRPS=mean(z$CRPS),
      Coverage50=mean(z$Covered50),Coverage95=mean(z$Covered95),
      MeanPredictiveWidth50=mean(z$PredictiveWidth50),MeanPredictiveWidth95=mean(z$PredictiveWidth95),
      UnseenLevelRecords=sum(!z$LevelSeenInTraining),NonestimableRecords=sum(!z$FixedEffectEstimable),
      Weighting="equal_weight_per_experiment",PointRule=POINT_RULE,
      RecordID=NA_character_,SourceRecordIDs=paste(z$RecordID,collapse="|"),Status="DEFINED",stringsAsFactors=FALSE)
  }
  do.call(rbind,ans)
}
self_test <- function() {
  # Closed-form integration and source-array checks, not a surrogate formal result.
  a<-array(seq_len(24L),c(4L,2L,3L));m<-as_chain_matrix(a)
  assert(identical(as.integer(m[5,]),as.integer(a[1,2,])),"Toy array order")
  constant<-matrix(log(.125),16L,4L);s<-mc_summary(constant)
  assert(abs(s$ReconstructedELPD-log(.125))<1e-14 && s$MCMC_MCSE_StabilizedLikelihood==0 && abs(s$EffectiveContributionCount-64)<1e-10,"Constant-integral oracle")
  concentrating<-matrix(-1000,16L,4L);concentrating[3,2]<-0;s2<-mc_summary(concentrating)
  assert(abs(s2$ReconstructedELPD+log(64))<1e-12 && s2$MaxNormalizedContribution==1 && s2$EffectiveContributionCount==1,"Concentrated-weight oracle")
  y<-.75;sample<-c(0,.5,1)
  oracle<-mean(abs(sample-y))-.5*mean(abs(outer(sample,sample,"-")))
  got<-scoringRules::crps_sample(y=y,dat=matrix(sample,nrow=1),method="edf")
  assert(abs(as.numeric(got)-oracle)<1e-12,"scoringRules EDF CRPS oracle")
  set.seed(8181);n<-60000L
  ep<-simulate_results(rep(.8,n),"exact",rho=rep(.25,n),shape_a=rep(7.5,n),shape_b=rep(2.5,n))
  assert(abs(mean(ep)-.8)<.008 && abs(mean(ep==1)-.2)<.008,"One-inflated prediction moment/mass oracle")
  ct<-simulate_results(rep(.3,n),"count",total=20)
  bb<-simulate_results(rep(.3,n),"count",total=20,count_phi=rep(5,n))
  assert(abs(mean(ct)-.3)<.006 && abs(mean(bb)-.3)<.008 && stats::var(bb)>2*stats::var(ct),"Count predictive oracle")
  assert(all(abs(ct*20-round(ct*20))<1e-12),"Count denominator lattice oracle")
  z<-data.frame(Fold=c(1L,2L),Type=c("count","exact"),Species=c("toy_a","toy_b"),
    AbsoluteError=c(0,1),SquaredError=c(0,1),CRPS=c(0,1),Covered50=c(TRUE,FALSE),Covered95=c(TRUE,FALSE),
    PredictiveWidth50=c(.1,.2),PredictiveWidth95=c(.2,.3),LevelSeenInTraining=c(TRUE,FALSE),
    FixedEffectEstimable=c(TRUE,FALSE),RecordID=c("TOY_1","TOY_2"))
  am<-aggregate_metrics(z)
  assert(abs(am$RMSE[am$Type=="count+exact"]-sqrt(.5))<1e-12,"Pooled RMSE oracle")
  cat(jsonlite::toJSON(list(status="PASS",scope="synthetic_mathematical_self_test_only",version=EXTENSION_VERSION,
    checks=c("chain_array_order","constant_integral","concentrated_integral","EDF_CRPS","one_inflated_moments","binomial_and_beta_binomial","original_denominator_lattice","pooled_RMSE"),packages=as.list(versions)),auto_unbox=TRUE,pretty=TRUE),"\n")
}
args<-commandArgs(trailingOnly=TRUE)
if(identical(args,"--self-test")) { self_test();quit(save="no",status=0L) }
assert(length(args)==3L,"Supply cv bundle, parent bundle, and new output directory; or --self-test")
cv_path<-normalizePath(args[1],mustWork=TRUE);parent_path<-normalizePath(args[2],mustWork=TRUE)
out_dir<-normalizePath(args[3],mustWork=FALSE)
assert(!dir.exists(out_dir) || length(list.files(out_dir,all.files=TRUE,no..=TRUE))==0L,"Output directory must be new or empty")
input_files<-c(CV=cv_path,ParentFit=parent_path);input_hashes<-vapply(input_files,sha,character(1))
cv<-readRDS(cv_path);parent<-readRDS(parent_path)
assert(identical(cv$key,digest::digest(cv$request,algo="sha256")),"CV request identity mismatch")
assert(identical(parent$key,digest::digest(parent$request,algo="sha256")),"Parent request identity mismatch")
assert(identical(cv$parent_key,parent$key) && identical(cv$request$parent_key,parent$key),"CV does not belong to selected parent fit")
assert(cv$status=="PASS" && all(cv$diagnostics$Status=="PASS"),"All CV folds must have PASS sampling diagnostics")
assert(identical(cv$outcome,parent$request$outcome) && identical(cv$model,parent$request$model),"Outcome/model differs from parent")
assert(cv$outcome %in% c("binary","joint"),"Unsupported outcome")
outcome<-cv$outcome;model<-cv$model;fold_count<-length(cv$fold_fits)
assert(fold_count==nrow(cv$diagnostics) && fold_count==nrow(cv$fold_scores),"Incomplete fold diagnostics/scores")
assert(identical(sort(as.integer(cv$fold_scores$Fold)),seq_len(fold_count)),"Nonconsecutive fold IDs")
run_root<-dirname(cv_path)
while(!file.exists(file.path(run_root,"prepared.rds"))) {
  next_root<-dirname(run_root);assert(!identical(next_root,run_root),"Cannot locate this run's prepared.rds");run_root<-next_root
}
prepared<-readRDS(file.path(run_root,"prepared.rds"))
assert(identical(prepared$input_hashes,parent$request$source_hashes),"Parent has different input hashes")
assert(identical(prepared$species$Species,parent$species),"Parent species order changed")
for(nm in names(prepared$input_paths))assert(identical(sha(prepared$input_paths[[nm]]),prepared$input_hashes[[nm]]),paste("Input changed:",nm))
fold_key_check<-digest::digest(list(outcome,cv$request$type,as.integer(fold_count),cv$request$seed,
  cv$request$folds,prepared$input_hashes),algo="sha256")
assert(identical(fold_key_check,cv$request$fold_key),"CV fold allocation identity mismatch")
receipt_root<-file.path(dirname(run_root),"job_receipts")
receipt_paths<-list.files(receipt_root,pattern="^status[.]json$",recursive=TRUE,full.names=TRUE)
receipt_objects<-lapply(receipt_paths,function(p)tryCatch(jsonlite::read_json(p,simplifyVector=TRUE),error=function(e)NULL))
matching_receipt<-function(key) {
  ok<-vapply(receipt_objects,function(z)!is.null(z) && identical(z$status,"PASS") && identical(z$key,key),logical(1))
  assert(any(ok),paste("No PASS job receipt for",key));receipt_paths[which(ok)[length(which(ok))]]
}
cv_receipt<-matching_receipt(cv$key);parent_receipt<-matching_receipt(parent$key)
parent_index<-utils::read.csv(file.path(dirname(parent_receipt),"fit_index.csv"),stringsAsFactors=FALSE)
pi<-parent_index[parent_index$Key==parent$key,,drop=FALSE]
assert(nrow(pi)>=1L && all(pi$FileSHA256==input_hashes[["ParentFit"]]),"Parent fit file hash does not match passing job index")
ci<-utils::read.csv(file.path(dirname(cv_receipt),"cv_index.csv"),stringsAsFactors=FALSE)
assert(any(ci$Key==cv$key & ci$ParentKey==parent$key & ci$Status=="PASS" & ci$File==basename(cv_path)),"CV receipt index does not identify this bundle")
source<-if(outcome=="joint")parent$request$source_rows else parent$request$training
assert(identical(source,cv$source),"CV response rows differ from parent")
source_id<-if(outcome=="joint")source$RecordID else source$BinaryID
expected_rows<-if(outcome=="joint")which(!source$NoRatioInformation) else seq_len(nrow(source))
all_held<-as.integer(unlist(cv$heldout_rows,use.names=FALSE))
assert(!anyDuplicated(all_held) && setequal(all_held,expected_rows),"Holdouts do not cover every informative source row exactly once")
assert(!anyDuplicated(cv$predictions$RecordID) && setequal(cv$predictions$RecordID,source_id[expected_rows]),"Saved OOF predictions missing or duplicated")
meta<-data.frame(Outcome=outcome,Model=model,Variant=parent$request$variant,CVType=cv$request$type,
  FoldKey=cv$request$fold_key,FitKey=parent$key,CVKey=cv$key,ExtensionVersion=EXTENSION_VERSION,stringsAsFactors=FALSE)
decorate<-function(x)cbind(meta[rep(1L,nrow(x)),,drop=FALSE],x)
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
mc_rows<-list();segments<-list();predictive_rows<-list();interval_rows<-list();metric_rows<-list();draw_exports<-list();order_checks<-list()
for(k in seq_len(fold_count)) {
  ff<-cv$fold_fits[[k]];held<-as.integer(cv$heldout_rows[[k]]);z<-source[held,,drop=FALSE]
  held_species<-as.character(z$Species)
  expected_species<-cv$request$folds$Species[cv$request$folds$Fold==k]
  assert(setequal(unique(held_species),expected_species),"Held-out species do not match declared fold")
  pred_pos<-match(source_id[held],cv$predictions$RecordID)
  pred<-cv$predictions[pred_pos,,drop=FALSE]
  assert(all(pred$Fold==k) && identical(as.character(pred$Species),held_species),"OOF source order mismatch")
  si<-match(held_species,parent$species)
  max_mean_reconstruction_error<-0;max_likelihood_reconstruction_error<-0
  if(outcome=="binary") {
    assert(!any(as.character(ff$data$Species) %in% held_species),"Held-out species present in binary training rows")
    if(parent$request$spec$Phylo)assert(identical(levels(ff$data$Species),parent$species) &&
      isTRUE(all.equal(ff$data2$A,parent$request$A,tolerance=0)),"Binary fold's phylogenetic state differs")
    da<-brms::as_draws_array(ff);dm<-as_chain_matrix(as.array(da));iterations<-dim(da)[1];chains<-dim(da)[2]
    raw_b<-as_chain_matrix(stan_array(ff$fit,"b"));b_names<-c("b_Intercept",if(nrow(parent$blueprint$columns))paste0("b_",parent$blueprint$columns$Column)else character())
    assert(identical(dim(raw_b),dim(dm[,b_names,drop=FALSE])) && max(abs(raw_b-dm[,b_names,drop=FALSE]))<1e-12,"brms b draws and native iteration/chain arrays disagree")
    nd<-parent$training_data[held,,drop=FALSE]
    assert(identical(as.character(nd$Species),held_species),"Binary newdata order differs")
    lm<-brms::log_lik(ff,newdata=nd,re_formula=NULL,allow_new_levels=FALSE,cores=1L)
    prob_nd<-nd;prob_nd$Trials<-1L
    md<-brms::posterior_epred(ff,newdata=prob_nd,re_formula=NULL,allow_new_levels=FALSE)
    eta<-matrix(dm[,"b_Intercept"],nrow(dm),length(held))
    if(ncol(parent$blueprint$X))eta<-eta+dm[,b_names[-1],drop=FALSE]%*%t(parent$blueprint$X[si,,drop=FALSE])
    if(parent$request$spec$Phylo)eta<-eta+dm[,paste0("r_Species[",held_species,",Intercept]"),drop=FALSE]
    reconstructed_mean<-stats::plogis(eta)
    max_mean_reconstruction_error<-max(abs(md-reconstructed_mean))
    assert(max_mean_reconstruction_error<1e-10,"Binary probability does not reconstruct from source draws")
    independent_ll<-matrix(NA_real_,nrow(lm),ncol(lm))
    for(j in seq_along(held)) {
      if(parent$request$family=="binomial")independent_ll[,j]<-stats::dbinom(z$HighCount[j],z$Trials[j],md[,j],log=TRUE)
      else {
        phi<-dm[,"phi"];a<-md[,j]*phi;b<-(1-md[,j])*phi
        independent_ll[,j]<-lchoose(z$Trials[j],z$HighCount[j])+lbeta(z$HighCount[j]+a,z$Trials[j]-z$HighCount[j]+b)-lbeta(a,b)
      }
    }
    max_likelihood_reconstruction_error<-max(abs(lm-independent_ll))
    assert(max_likelihood_reconstruction_error<1e-8,"Binary log_lik does not match original counts and source draws")
  } else {
    la<-stan_array(ff,"log_lik");iterations<-dim(la)[1];chains<-dim(la)[2]
    assert(dim(la)[3]==nrow(source),"Joint log_lik source dimension differs")
    lm<-as_chain_matrix(la[,,held,drop=FALSE])
    ma<-stan_array(ff,"m");assert(dim(ma)[3]==length(parent$species),"Joint m species dimension differs")
    md<-as_chain_matrix(ma[,,si,drop=FALSE])
    d<-parent$request$data;d$train[held]<-0L
    assert(!any(source$Species[d$train==1L] %in% held_species),"Joint held-out species retains training likelihood")
    cache_path<-file.path(dirname(cv_path),paste0(model,"_",substr(cv$key,1,16),"_fold",k,".rds"))
    assert(file.exists(cache_path),"Missing joint fold data-identity cache")
    cache<-readRDS(cache_path)
    assert(identical(cache$data_key,digest::digest(d,algo="sha256")) && identical(cache$fit@sim,ff@sim),"Joint fold input identity or source sample cache differs")
    pars<-c("alpha","rho","log_phi_ratio")
    if(d$K>0)pars<-c(pars,"beta")
    if(d$use_phylo==1L)pars<-c(pars,"z_phylo","sd_phylo")
    if(d$use_beta_binomial==1L)pars<-c(pars,"log_phi_count")
    pd<-as_chain_matrix(stan_array(ff,pars));rho<-pd[,"rho"]
    eta<-matrix(pd[,"alpha"],nrow(pd),length(held))
    if(d$K>0)eta<-eta+pd[,paste0("beta[",seq_len(d$K),"]"),drop=FALSE]%*%t(parent$blueprint$X[si,,drop=FALSE])
    if(d$use_phylo==1L)eta<-eta+sweep(pd[,paste0("z_phylo[",seq_len(d$S),"]"),drop=FALSE]%*%t(d$L_A[si,,drop=FALSE]),1L,pd[,"sd_phylo[1]"],"*")
    max_mean_reconstruction_error<-max(abs(md-stats::plogis(eta)))
    assert(max_mean_reconstruction_error<1e-10,"Joint m does not reconstruct from source chain draws")
    sa<-as_chain_matrix(stan_array(ff,"shape_a")[,,si,drop=FALSE]);sb<-as_chain_matrix(stan_array(ff,"shape_b")[,,si,drop=FALSE])
    assert(identical(dim(sa),dim(md)) && identical(dim(sb),dim(md)),"Joint Beta shapes not aligned to held species")
    theoretical_mean<-rho*md+(1-rho*md)*sa/(sa+sb)
    assert(max(abs(theoretical_mean-md))<1e-10,"One-inflated shapes do not share the expected ratio m")
  }
  assert(nrow(lm)==iterations*chains && ncol(lm)==length(held) && all(is.finite(lm)),"Likelihood draw order/values invalid")
  assert(nrow(md)==iterations*chains && ncol(md)==length(held) && all(is.finite(md)),"Mean draw order/values invalid")
  mquant<-quantile_rows(md,c(.025,.5,.975))
  median_error<-max(abs(mquant[2,]-pred$PosteriorMedian))
  bound_error<-max(abs(mquant[c(1,3),]-rbind(pred$MeanLower95,pred$MeanUpper95)))
  assert(median_error<1e-10 && bound_error<1e-10,"Exported source mean draws differ from original OOF summaries")
  log_joint<-matrix(rowSums(lm),nrow=iterations,ncol=chains)
  original_score<-cv$fold_scores$ELPD[match(k,cv$fold_scores$Fold)]
  mmc<-mc_summary(log_joint);score_error<-mmc$ReconstructedELPD-original_score
  assert(is.finite(original_score) && abs(score_error)<1e-7,"Reconstructed whole-fold joint ELPD differs from original CV score")
  record_ids<-if(outcome=="joint")z$RecordID else parent$request$source_map$RecordID[parent$request$source_map$Species %in% held_species & !is.na(parent$request$source_map$High)]
  fold_meta<-data.frame(Fold=k,RecordID=NA_character_,SourceRecordIDs=paste(record_ids,collapse="|"),
    SpeciesCount=length(unique(held_species)),LikelihoodRows=length(held),ExperimentRecords=length(record_ids),
    ELPD=original_score,ELPDReconstructionDifference=score_error,SamplingStatus="PASS",stringsAsFactors=FALSE)
  mc_rows[[k]]<-cbind(fold_meta,mmc)
  split<-floor(iterations/2L)
  for(ch in 0:chains)for(segment in c("full","first_half","second_half")) {
    ii<-switch(segment,full=seq_len(iterations),first_half=seq_len(split),second_half=seq.int(split+1L,iterations))
    cc<-if(ch==0L)seq_len(chains)else ch
    vals<-as.vector(log_joint[ii,cc,drop=FALSE])
    segments[[length(segments)+1L]]<-data.frame(Fold=k,Chain=ch,Segment=segment,RecordID=NA_character_,
      SourceRecordIDs=paste(record_ids,collapse="|"),DrawCount=length(vals),LogPredictive=lme(vals),
      DifferenceFromAllDraws=lme(vals)-mmc$ReconstructedELPD,stringsAsFactors=FALSE)
  }
  order_checks[[k]]<-data.frame(Fold=k,NativeIterationChainMapping="PASS",HeldoutSourceOrder="PASS",
    MeanReconstructionMaxAbsError=max_mean_reconstruction_error,OriginalMeanMedianMaxAbsError=median_error,
    OriginalMeanIntervalMaxAbsError=bound_error,BinaryLikelihoodReconstructionMaxAbsError=max_likelihood_reconstruction_error,
    OriginalWholeFoldELPDAbsError=abs(score_error),stringsAsFactors=FALSE)
  draw_exports[[k]]<-list(Fold=k,FitKey=parent$key,CVKey=cv$key,RecordID=source_id[held],Species=held_species,
    DrawIteration=rep(seq_len(iterations),times=chains),DrawChain=rep(seq_len(chains),each=iterations),
    LogJointByIterationChain=log_joint,ExpectedRatioOrProbabilityDraws=md)
  if(outcome=="joint") {
    seed<-as.integer(PREDICTIVE_SEED_BASE+k);set.seed(seed)
    point_local<-which(z$Type %in% c("count","exact"));interval_local<-which(z$Type=="interval")
    yp<-matrix(NA_real_,nrow(md),length(point_local),dimnames=list(NULL,z$RecordID[point_local]))
    for(jj in seq_along(point_local)) {
      j<-point_local[jj]
      phi<-if(parent$request$count_family=="beta_binomial")exp(pd[,"log_phi_count[1]"])else NULL
      yp[,jj]<-simulate_results(md[,j],z$Type[j],total=z$Total[j],rho=rho,shape_a=sa[,j],shape_b=sb[,j],count_phi=phi)
    }
    if(length(point_local)) {
      zz<-z[point_local,,drop=FALSE];pp<-pred[point_local,,drop=FALSE]
      pyq<-quantile_rows(yp,c(.025,.25,.5,.75,.975),type=1L)
      point_mean<-colMeans(md[,point_local,drop=FALSE]);point_median<-mquant[2,point_local]
      observed<-ifelse(zz$Type=="count",zz$Events/zz$Total,zz$Exact)
      ps<-data.frame(Fold=k,RecordID=zz$RecordID,ExperimentID=zz$ExperimentID,SourceID=zz$SourceID,Species=zz$Species,
        Type=zz$Type,Events=zz$Events,Total=zz$Total,Exact=zz$Exact,Lower=zz$Lower,Upper=zz$Upper,
        OOFMeanPosteriorMean=point_mean,OOFMeanMedian=point_median,OOFMeanLower95=mquant[1,point_local],OOFMeanUpper95=mquant[3,point_local],
        PredictiveMean=colMeans(yp),PredictiveMedian=pyq[3,],PredictiveLower50=pyq[2,],PredictiveUpper50=pyq[4,],
        PredictiveLower95=pyq[1,],PredictiveUpper95=pyq[5,],DrawCount=nrow(yp),Seed=seed,
        LevelSeenInTraining=pp$LevelSeenInTraining,FixedEffectEstimable=pp$FixedEffectEstimable,
        PredictiveIntervalDefinition="equal_tailed_empirical_quantiles_type1_of_future_result",Status="DEFINED",stringsAsFactors=FALSE)
      crps<-as.numeric(scoringRules::crps_sample(y=observed,dat=t(yp),method="edf"))
      assert(length(crps)==length(observed) && all(is.finite(crps)) && all(crps>=-1e-12),"Invalid scoringRules CRPS")
      mr<-data.frame(Fold=k,RecordID=zz$RecordID,ExperimentID=zz$ExperimentID,SourceID=zz$SourceID,Species=zz$Species,Type=zz$Type,
        ObservedRatio=observed,PointPrediction=point_mean,PointPredictionMedian=point_median,PointRule=POINT_RULE,
        AbsoluteError=abs(point_mean-observed),SquaredError=(point_mean-observed)^2,CRPS=crps,
        Covered50=observed>=pyq[2,] & observed<=pyq[4,],Covered95=observed>=pyq[1,] & observed<=pyq[5,],
        PredictiveWidth50=pyq[4,]-pyq[2,],PredictiveWidth95=pyq[5,]-pyq[1,],
        LevelSeenInTraining=pp$LevelSeenInTraining,FixedEffectEstimable=pp$FixedEffectEstimable,
        DrawCount=nrow(yp),Seed=seed,Status="DEFINED",stringsAsFactors=FALSE)
      predictive_rows[[length(predictive_rows)+1L]]<-ps;metric_rows[[length(metric_rows)+1L]]<-mr
    }
    if(length(interval_local)) {
      ip<-exp(lm[,interval_local,drop=FALSE])
      assert(all(is.finite(ip)) && all(ip>=0 & ip<=1+1e-12),"Invalid held-out interval event probabilities")
      iz<-z[interval_local,,drop=FALSE];ipp<-pred[interval_local,,drop=FALSE]
      for(jj in seq_along(interval_local)) {
        j<-interval_local[jj];lo<-z$Lower[j];hi<-z$Upper[j];w<-rho*md[,j]
        beta_prob<-if(lo==0)stats::pbeta(hi,sa[,j],sb[,j]) else if(hi==1)stats::pbeta(lo,sa[,j],sb[,j],lower.tail=FALSE) else
          ifelse(lo>=sa[,j]/(sa[,j]+sb[,j]),stats::pbeta(lo,sa[,j],sb[,j],lower.tail=FALSE)-stats::pbeta(hi,sa[,j],sb[,j],lower.tail=FALSE),
            stats::pbeta(hi,sa[,j],sb[,j])-stats::pbeta(lo,sa[,j],sb[,j]))
        independently_computed<-(1-w)*beta_prob+if(hi==1)w else 0
        assert(max(abs(ip[,jj]-independently_computed))<1e-9,"Native interval likelihood disagrees with Beta+endpoint event probability")
      }
      ipq<-quantile_rows(ip,c(.025,.5,.975))
      interval_rows[[length(interval_rows)+1L]]<-data.frame(Fold=k,RecordID=iz$RecordID,ExperimentID=iz$ExperimentID,SourceID=iz$SourceID,
        Species=iz$Species,Type="interval",Lower=iz$Lower,Upper=iz$Upper,
        OOFMeanPosteriorMean=colMeans(md[,interval_local,drop=FALSE]),OOFMeanMedian=mquant[2,interval_local],
        OOFMeanLower95=mquant[1,interval_local],OOFMeanUpper95=mquant[3,interval_local],
        PredictiveEventProbability=colMeans(ip),EventProbabilityPosteriorMedian=ipq[2,],
        EventProbabilityLower95=ipq[1,],EventProbabilityUpper95=ipq[3,],DrawCount=nrow(ip),
        LevelSeenInTraining=ipp$LevelSeenInTraining,FixedEffectEstimable=ipp$FixedEffectEstimable,
        Status="EVENT_PROBABILITY_ONLY_NO_POINT_SCORE",stringsAsFactors=FALSE)
      draw_exports[[k]]$IntervalRecordID<-iz$RecordID;draw_exports[[k]]$IntervalEventProbabilityDraws<-ip
    }
    draw_exports[[k]]$PredictiveRecordID<-z$RecordID[point_local]
    draw_exports[[k]]$PredictiveDraws<-yp;draw_exports[[k]]$PredictiveSeed<-seed
  }
  cat("POSTPROCESS_FOLD_FINISHED",outcome,model,cv$request$type,k,"\n")
}
write_csv<-function(x,name)utils::write.csv(decorate(x),file.path(out_dir,name),row.names=FALSE,na="")
mc_table<-do.call(rbind,mc_rows)
write_csv(mc_table,"cv_fold_scores_mc.csv")
write_csv(do.call(rbind,segments),"cv_mc_chain_segments.csv")
write_csv(do.call(rbind,order_checks),"source_draw_order_checks.csv")
if(outcome=="joint") {
  points<-do.call(rbind,predictive_rows);metrics<-do.call(rbind,metric_rows)
  expected_point_ids<-source$RecordID[expected_rows][source$Type[expected_rows] %in% c("count","exact")]
  assert(!anyDuplicated(points$RecordID) && setequal(points$RecordID,expected_point_ids),"Point predictions do not exactly cover all held-out count/exact rows")
  assert(!anyDuplicated(metrics$RecordID) && setequal(metrics$RecordID,expected_point_ids),"Point metrics missing difficult rows")
  points<-points[match(expected_point_ids,points$RecordID),,drop=FALSE]
  metrics<-metrics[match(expected_point_ids,metrics$RecordID),,drop=FALSE]
  write_csv(points,"oof_predictive_summary.csv")
  write_csv(metrics,"quantitative_metrics_by_record.csv")
  write_csv(aggregate_metrics(metrics,by_fold=TRUE),"quantitative_metrics_by_fold.csv")
  write_csv(aggregate_metrics(metrics),"quantitative_metrics_summary.csv")
  if(length(interval_rows)) {
    intervals<-do.call(rbind,interval_rows);expected_interval_ids<-source$RecordID[expected_rows][source$Type[expected_rows]=="interval"]
    assert(!anyDuplicated(intervals$RecordID) && setequal(intervals$RecordID,expected_interval_ids),"Interval probabilities do not cover all informative intervals")
    write_csv(intervals[match(expected_interval_ids,intervals$RecordID),,drop=FALSE],"oof_interval_probability.csv")
  }
}
saveRDS(list(metadata=meta,PointRule=POINT_RULE,PredictiveIntervalQuantileType=1L,ExpectedIntervalQuantileType=7L,
  FoldDraws=draw_exports,CrossFoldDrawWarning="Different folds have distinct posteriors; do not combine same draw indices into joint cross-fold inference"),
  file.path(out_dir,"oof_prediction_and_score_draws.rds"),compress="gzip")
assert(identical(vapply(input_files,sha,character(1)),input_hashes),"Source bundles changed during postprocessing")
script_flag<-grep("^--file=",commandArgs(),value=TRUE)
script_path<-if(length(script_flag))sub("^--file=","",script_flag[1])else NA_character_
manifest<-list(status="PASS",scope="postprocessing_identity_and_numerical_checks_only",version=EXTENSION_VERSION,
  Outcome=outcome,Model=model,CVType=cv$request$type,FitKey=parent$key,CVKey=cv$key,FoldKey=cv$request$fold_key,
  InputFiles=as.list(input_files),InputSHA256=as.list(input_hashes),CVReceipt=cv_receipt,ParentReceipt=parent_receipt,
  Packages=as.list(versions),R=R.version.string,ScriptSHA256=if(!is.na(script_path))sha(script_path)else NA_character_,
  PointRule=POINT_RULE,CRPSRule="scoringRules::crps_sample(method=edf) on actual posterior predictive result draws",
  QuantileTypePredictive=1L,QuantileTypeExpected=7L,PointMetricWeighting="equal_weight_per_experiment",
  AggregateRecordID="blank; SourceRecordIDs enumerates constituent experimental RecordIDs",
  EffectiveContributionCountDefinition="1/sum(normalized likelihood contribution^2); not parameter ESS; ignores serial correlation",
  LogPredictiveMCSEDefinition="posterior::mcse_mean of stabilized likelihood, divided by its mean (delta method; unreliable when relative error is large)",
  MCReviewScreens=list(LogMCSEAbove=.1,MaximumContributionAbove=.1,EffectiveContributionsBelow=100,ChainScoreRangeAbove=.5),
  MCReviewScreenInterpretation="descriptive flags, not calibrated significance thresholds or certification of accurate ranking",
  FoldCount=fold_count,MCFlaggedFolds=as.integer(mc_table$Fold[mc_table$MCReviewStatus!="NO_SCREEN_FLAG"]),
  PointRows=if(outcome=="joint")nrow(metrics)else 0L,IntervalRows=if(outcome=="joint")sum(source$Type[expected_rows]=="interval")else 0L,
  FinishedAt=format(Sys.time(),tz="UTC",usetz=TRUE))
jsonlite::write_json(manifest,file.path(out_dir,"postprocessing_manifest.json"),auto_unbox=TRUE,pretty=TRUE,na="null")
cat("CV_EXTENSIONS_FINISHED",outcome,model,cv$request$type,out_dir,"\n")
