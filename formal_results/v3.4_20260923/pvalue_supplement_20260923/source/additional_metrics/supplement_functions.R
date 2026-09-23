# Supplementary inference from saved OOF predictions; no fitting functions are called.
auc_species_stats <- function(d) {
  stopifnot(all(c("Species","ObservedHigh","PredictedPrHigh") %in% names(d)),all(d$ObservedHigh%in%c(0,1)),all(is.finite(d$PredictedPrHigh)))
  sp<-sort(unique(as.character(d$Species)))
  n<-vapply(sp,function(s)sum(d$Species==s),integer(1))
  hi<-vapply(sp,function(s)sum(d$ObservedHigh[d$Species==s]),numeric(1))
  scores<-vapply(sp,function(s){v<-unique(d$PredictedPrHigh[d$Species==s]);if(length(v)!=1L)stop("Species score not constant within fit/fold");v},numeric(1))
  type<-ifelse(hi==0,"LOW_only",ifelse(hi==n,"HIGH_only","mixed"))
  list(species=sp,n=n,high=hi,low=n-hi,score=scores,type=type)
}
auc_from_cluster_counts <- function(meta, multiplicity, eval_weighting) {
  if(is.null(dim(multiplicity)))multiplicity<-matrix(multiplicity,ncol=1)
  stopifnot(nrow(multiplicity)==length(meta$n),all(multiplicity>=0),all(eval_weighting%in%c("record_equal","species_equal")))
  scale<-if(eval_weighting=="species_equal")1/meta$n else rep(1,length(meta$n))
  pos<-multiplicity*(meta$high*scale);neg<-multiplicity*(meta$low*scale)
  kernel<-outer(meta$score,meta$score,function(a,b)(a>b)+.5*(a==b))
  denominator<-colSums(pos)*colSums(neg)
  if(any(!is.finite(denominator)|denominator<=0))stop("Undefined AUC resample; never drop a fold")
  colSums(pos*(kernel%*%neg))/denominator
}
auc_stratified_counts <- function(meta,B,seed) {
  set.seed(seed);S<-length(meta$n);counts<-matrix(0L,S,B)
  for(group in sort(unique(meta$type))){ix<-which(meta$type==group);counts[ix,]<-rmultinom(B,length(ix),rep(1/length(ix),length(ix)))}
  stopifnot(all(colSums(counts)==S))
  for(group in unique(meta$type)){ix<-which(meta$type==group);stopifnot(all(colSums(counts[ix,,drop=FALSE])==length(ix)))}
  counts
}
error_species_stats <- function(d, prediction_columns) {
  stopifnot(all(d$Type%in%c("count","exact")),all(is.finite(d$ObservedPoint)))
  sp<-sort(unique(as.character(d$Species)));n<-vapply(sp,function(s)sum(d$Species==s),integer(1))
  ae<-se<-matrix(NA_real_,length(sp),length(prediction_columns),dimnames=list(sp,prediction_columns))
  for(j in seq_along(prediction_columns)){
    p<-d[[prediction_columns[j]]];stopifnot(all(is.finite(p)),all(p>=0&p<=1))
    err<-p-d$ObservedPoint
    for(i in seq_along(sp)){ix<-d$Species==sp[i];ae[i,j]<-sum(abs(err[ix]));se[i,j]<-sum(err[ix]^2)}
  }
  list(species=sp,n=n,absolute_error_sum=ae,squared_error_sum=se)
}
error_metrics_from_counts <- function(meta,multiplicity,eval_weighting) {
  if(is.null(dim(multiplicity)))multiplicity<-matrix(multiplicity,ncol=1)
  stopifnot(nrow(multiplicity)==length(meta$n),all(multiplicity>=0),all(colSums(multiplicity)>0))
  if(eval_weighting=="record_equal"){
    denominator<-as.vector(crossprod(meta$n,multiplicity));ae<-crossprod(multiplicity,meta$absolute_error_sum)/denominator;mse<-crossprod(multiplicity,meta$squared_error_sum)/denominator
  }else if(eval_weighting=="species_equal"){
    denominator<-colSums(multiplicity);ae<-crossprod(multiplicity,meta$absolute_error_sum/meta$n)/denominator;mse<-crossprod(multiplicity,meta$squared_error_sum/meta$n)/denominator
  }else stop("Unknown evaluation weighting")
  list(MAE=ae,RMSE=sqrt(mse))
}
normal_bootstrap_test <- function(estimate,reference,draws,structural_chance=FALSE) {
  if(!length(draws)||any(!is.finite(draws)))stop("Nonfinite bootstrap draws")
  difference<-estimate-reference;se<-sd(draws);q<-quantile(draws-reference,c(.025,.975),names=FALSE)
  if(structural_chance){
    stopifnot(abs(difference)<1e-12,max(abs(draws-reference))<1e-12)
    return(list(Difference=0,SE_approx=0,Z_approx=0,P_approx=1,CI95_lower=0,CI95_upper=0,TestStatus="STRUCTURAL_AUC_0_5_NO_DISCRIMINATION"))
  }
  if(!is.finite(se)||se<1e-12)return(list(Difference=difference,SE_approx=se,Z_approx=NA_real_,P_approx=NA_real_,CI95_lower=q[1],CI95_upper=q[2],TestStatus="DEGENERATE_CLUSTER_BOOTSTRAP"))
  z<-difference/se
  list(Difference=difference,SE_approx=se,Z_approx=z,P_approx=2*pnorm(-abs(z)),CI95_lower=q[1],CI95_upper=q[2],TestStatus="CONDITIONAL_OOF_NORMAL_APPROXIMATION")
}
