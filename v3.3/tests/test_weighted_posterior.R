#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
out<-file.path(root,"review","weighted_posterior");dir.create(file.path(out,"input"),recursive=TRUE,showWarnings=FALSE)
p<-data.frame(Species=c("many_low","few_high"),Site3="C",Site20="K",Site117="K",Site151="C",Site196="C",Site315="K")
obs<-data.frame(RecordID=paste0("weighted",1:22),ExperimentID=paste0("experiment",1:22),Species=c(rep("many_low",20),rep("few_high",2)),Type="count",Events=c(rep(0,20),rep(1,2)),Total=1,Exact=NA,Lower=NA,Upper=NA,SourceID="synthetic_weighting_test")
write_csv_atomic(p,file.path(out,"input","sites.csv"));write_csv_atomic(obs,file.path(out,"input","observations.csv"));s<-prepare_state(file.path(out,"input"))
# Reuse the already compiled, same-code binary Null program, never its data/posterior.
template<-readRDS(file.path(root,"review/integration/runs/fits/binary__Null__record_equal__integration_f1/fit.rds"))
assign(".v31_binary_templates",new.env(),.GlobalEnv);assign(sha256_object(template$code),template$fit,get(".v31_binary_templates",.GlobalEnv))
rows<-list()
for(tw in V3_TRAIN_WEIGHTINGS) {
  b<-fit_bundle_v3(s,"binary","Null",s$binary_species,tw,out,stan_path=file.path(root,"stan","joint_bb.stan"),iter=3000,warmup=1000,chains=4,cores=4,seed=20260925)
  w<-build_train_weights(s$observations[,"Species",drop=FALSE],tw)$weight;y<-s$observations$High
  logtarget<-function(a)dnorm(a,0,V3_PRIORS$intercept,log=TRUE)+sum(w*y)*(-log1p(exp(-a)))+sum(w*(1-y))*(-log1p(exp(a)))
  peak<-optimize(function(a)-logtarget(a),c(-15,15))$minimum
  norm<-integrate(function(a)exp(vapply(a,logtarget,numeric(1))-logtarget(peak)),-20,20,rel.tol=1e-10)$value
  expected<-integrate(function(a)plogis(a)*exp(vapply(a,logtarget,numeric(1))-logtarget(peak)),-20,20,rel.tol=1e-10)$value/norm
  posterior_mean<-mean(binary_prediction_draws(b,s,"many_low"))
  stopifnot(abs(expected-posterior_mean)<.025,b$diagnostics$Status=="PASS")
  spec<-fit_spec_v3(s,"binary","Null",s$binary_species,tw,NULL,modifyList(V3_SAMPLING,list(iter=3000,warmup=1000,chains=4,cores=4)),20260925)
  validate_fitted_bundle_v3(b,spec,TRUE)
  rows[[tw]]<-cbind(data.frame(TrainWeighting=tw,QuadratureMean=expected,StanPosteriorMean=posterior_mean,AbsoluteError=abs(expected-posterior_mean)),b$diagnostics)
}
ans<-do.call(rbind,rows);stopifnot(diff(ans$StanPosteriorMean)>.25)
write_csv_atomic(ans,file.path(out,"quadrature_comparison.csv"))
cat("WEIGHTED_POSTERIOR_PASS: real brms fits agree with independent scalar quadrature\n")
