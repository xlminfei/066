#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
out<-file.path(root,"review","integration");state<-prepare_state(file.path(out,"input"))
log_interval_R<-function(lo,hi,a,b) {
  if(lo==0&&hi==1)return(0)
  if(hi<=.5)safe_log_diff_exp(pbeta(hi,a,b,log.p=TRUE),pbeta(lo,a,b,log.p=TRUE)) else safe_log_diff_exp(pbeta(lo,a,b,lower.tail=FALSE,log.p=TRUE),pbeta(hi,a,b,lower.tail=FALSE,log.p=TRUE))
}
log_likelihood_R<-function(o,m,rho,pc,pr) {
  if(o$Type=="count")return(lchoose(o$Total,o$Events)+lbeta(o$Events+pc*m,o$Total-o$Events+pc*(1-m))-lbeta(pc*m,pc*(1-m)))
  atom<-rho*m;mu<-m*(1-rho)/(1-atom);a<-pr*mu;b<-pr*(1-mu)
  if(o$Type=="exact")return(if(o$Exact==1)log(atom) else log1p(-atom)+dbeta(o$Exact,a,b,log=TRUE))
  if(o$Lower==0&&o$Upper==1)return(0)
  if(o$Upper==1)return(log(atom+(1-atom)*pbeta(o$Lower,a,b,lower.tail=FALSE)))
  log1p(-atom)+log_interval_R(o$Lower,o$Upper,a,b)
}
b<-readRDS(fit_path_v3(out,"joint_bb","M1","species_equal","integration",1))
p<-extract_parameters_v3(b);m<-joint_expected_draws(b,state,state$observations$Species)
ll<-rstan::extract(b$fit,pars="log_lik",permuted=TRUE)$log_lik
err<-numeric()
for(d in 1:20)for(i in seq_len(nrow(state$observations)))err<-c(err,abs(ll[d,i]-log_likelihood_R(state$observations[i,],m[d,i],p$rho[d],exp(p$log_phi_count[d]),exp(p$log_phi_ratio[d]))))
stopifnot(max(err)<1e-7)
write_json_atomic(list(status="PASS",comparisons=length(err),max_absolute_error=max(err)),file.path(out,"stan_r_likelihood_agreement.json"))
cat("STAN_R_LIKELIHOOD_PASS",length(err),"values; max error",max(err),"\n")
