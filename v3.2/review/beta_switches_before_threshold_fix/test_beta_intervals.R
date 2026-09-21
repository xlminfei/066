#!/usr/bin/env Rscript
# Only synthetic parameter evaluations. Fixed_param creates an interface object;
# this test never samples a posterior and never reads the research input files.
args <- commandArgs(TRUE)
stage <- if (length(args)) args[1] else "after"
stopifnot(stage %in% c("before", "after"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value=TRUE)[1])
root <- normalizePath(file.path(dirname(script), ".."), mustWork=TRUE)
out <- file.path(root,"review",paste0("beta_",stage))
dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages(library(rstan))
options(mc.cores=1L)
rstan_options(auto_write=TRUE)
source_file <- if(stage=="before") file.path(root,"tests","stan","beta_interval_before.stan") else file.path(root,"stan","joint_bb.stan")
src <- readLines(source_file,warn=FALSE)
endfun <- grep("^data \\{",src)[1]-1L
stopifnot(!is.na(endfun),endfun>2L)
probe <- c(src[seq_len(endfun)],
  "data { int<lower=1,upper=3> mode; real<lower=0,upper=1> lo; real<lower=0,upper=1> hi; }",
  "parameters { vector[3] theta; }",
  "model {",
  "  if (mode == 1) target += log_beta_interval(lo, hi, theta[1], theta[2]);",
  "  else if (mode == 3) target += log_beta_interval(lo, hi, exp(theta[1]), exp(theta[2]));",
  "  else target += record_log_lik(3, 0, 1, 0.5, lo, hi, inv_logit(theta[1]), inv_logit(theta[2]), 0, theta[3]);",
  "}")
probe_file <- file.path(root,"tests","stan",paste0("beta_interval_probe_",stage,".stan"))
writeLines(probe,probe_file)
sm <- stan_model(file=probe_file,model_name=paste0("beta_interval_",stage),verbose=TRUE)
# R pbeta is used only as an independent reference. Narrow intervals are
# integrated directly using a scaled density, avoiding subtraction entirely.
ldiff <- function(x,y) if(is.infinite(y)&&y<0) x else if(y>=x) -Inf else x+log(-expm1(y-x))
ref_interval <- function(lo,hi,a,b) {
  if(lo==0&&hi==1) return(0)
  if(lo==0) return(pbeta(hi,a,b,log.p=TRUE))
  if(hi==1) return(pbeta(lo,a,b,lower.tail=FALSE,log.p=TRUE))
  if(a==1) return(b*log1p(-lo)+log(-expm1(b*(log1p(-hi)-log1p(-lo)))))
  if(b==1) return(a*log(hi)+log(-expm1(a*(log(lo)-log(hi)))))
  if(hi-lo<1e-5*min(lo,1-hi) || min(a,b)<1e-5) {
    mid<-lo+(hi-lo)/2; scale<-dbeta(mid,a,b,log=TRUE)
    q<-integrate(function(t)exp(dbeta(lo+(hi-lo)*t,a,b,log=TRUE)-scale),0,1,
      rel.tol=2e-12,abs.tol=1e-12,subdivisions=2000L,stop.on.error=TRUE)$value
    return(log(hi-lo)+scale+log(q))
  }
  cl<-pbeta(lo,a,b,log.p=TRUE);ch<-pbeta(hi,a,b,log.p=TRUE)
  sl<-pbeta(lo,a,b,lower.tail=FALSE,log.p=TRUE);sh<-pbeta(hi,a,b,lower.tail=FALSE,log.p=TRUE)
  if(ch<=log(.5)) return(ldiff(ch,cl))
  if(sl<=log(.5)) return(ldiff(sl,sh))
  ldiff(ch,cl)
}
ref_record <- function(lo,hi,th) {
  m<-plogis(th[1]);rho<-plogis(th[2]);phi<-exp(th[3]);pm<-rho*m
  mu<-m*(1-rho)/(1-pm);a<-phi*mu;b<-phi*(1-mu)
  li<-ref_interval(lo,hi,a,b)+log1p(-pm)
  if(hi==1) { q<-max(log(pm),li); return(q+log(exp(log(pm)-q)+exp(li-q))) }
  li
}
fd5<-function(f,x,j,positive=FALSE) {
  h<-2e-4*max(abs(x[j]),.05)
  if(positive)h<-min(h,2e-4*x[j])
  eval<-function(s){y<-x;y[j]<-y[j]+s*h;f(y)}
  (eval(-2)-8*eval(-1)+8*eval(1)-eval(2))/(12*h)
}
cases<-data.frame(
 id=c("beta_1_100_upper","beta_200_1_lower","underflow_upper","underflow_lower","near_zero","near_one","narrow_middle","narrow_tail","u_shaped","wide_center","skew_left","skew_right","concentrated_center","full_support","left_boundary","right_boundary","cf_switch_left","cf_switch_right"),
 a=c(1,200,1,2000,.3,12,2.5,2.5,.2,2,1.1,100,800,2,.2,10,5,5),
 b=c(100,1,2000,1,12,.3,7.5,120,.4,3,100,1.1,1000,3,10,.2,7,7),
 lo=c(.4,.6,.4,.6,0,1-1e-8,.45,.85,.001,.01,.4,.01,.43,0,0,.7,6/14-1e-9,6/14+1e-9),
 hi=c(.5,.7,.5,.7,1e-8,1,.45+1e-12,.85+1e-10,.99,.95,.5,.05,.46,1,.3,1,6/14+1e-3,6/14+1e-3+2e-9), stringsAsFactors=FALSE)
if(stage=="before") cases<-cases[1:2,]
if(stage=="after") {
  g<-expand.grid(a=c(.05,.2,1,5,50,200,1000),b=c(.05,.2,1,5,50,200,1000),interval=1:5)
  gg<-data.frame(id=paste0("grid_",seq_len(nrow(g))),a=g$a,b=g$b,lo=c(.001,.05,.4,.7,.95)[g$interval],hi=c(.01,.15,.5,.9,.999)[g$interval])
  tiny<-data.frame(id=c("tiny_u_shape","tiny_left_shape","tiny_right_shape"),a=c(1e-8,1e-7,.2),b=c(1e-8,.2,1e-7),lo=c(.1,.3,.4),hi=c(.9,.4,.5))
  cases<-rbind(cases,gg,tiny)
}
write.csv(cases,file.path(out,"parameter_cases.csv"),row.names=FALSE)
make_fit<-function(mode,lo,hi) suppressWarnings(sampling(sm,data=list(mode=mode,lo=lo,hi=hi),iter=1L,warmup=0L,chains=1L,algorithm="Fixed_param",init=list(list(theta=c(2,3,0))),refresh=0L,seed=743L))
values<-list();gradients<-list()
for(i in seq_len(nrow(cases))) {
  z<-cases[i,];fit<-make_fit(1,z$lo,z$hi);th<-c(z$a,z$b,0)
  val<-tryCatch(log_prob(fit,th,adjust_transform=FALSE),error=function(e)NA_real_)
  gr<-tryCatch(grad_log_prob(fit,th,adjust_transform=FALSE),error=function(e)rep(NA_real_,3))
  ref<-ref_interval(z$lo,z$hi,z$a,z$b)
  values[[i]]<-data.frame(Case=z$id,Mode="a_b",Stan=val,Reference=ref,AbsError=abs(val-ref))
  for(j in 1:2) {
    f<-function(v)ref_interval(z$lo,z$hi,v[1],v[2]);num<-fd5(f,th,j,positive=TRUE)
    gradients[[length(gradients)+1L]]<-data.frame(Case=z$id,Mode="a_b",Parameter=c("a","b")[j],Stan=gr[j],Reference=num,AbsError=abs(gr[j]-num),ScaledError=abs(gr[j]-num)/max(1,abs(num)))
  }
}
if(stage=="after") {
  for(i in seq_len(18L)) {
    z<-cases[i,];fit<-make_fit(3,z$lo,z$hi);th<-c(log(z$a),log(z$b),0)
    val<-log_prob(fit,th,adjust_transform=FALSE);gr<-grad_log_prob(fit,th,adjust_transform=FALSE)
    ref<-ref_interval(z$lo,z$hi,z$a,z$b)
    values[[length(values)+1L]]<-data.frame(Case=z$id,Mode="log_a_log_b",Stan=val,Reference=ref,AbsError=abs(val-ref))
    for(j in 1:2) {
      num<-fd5(function(v)ref_interval(z$lo,z$hi,exp(v[1]),exp(v[2])),th,j)
      gradients[[length(gradients)+1L]]<-data.frame(Case=z$id,Mode="log_a_log_b",Parameter=c("log_a","log_b")[j],Stan=gr[j],Reference=num,AbsError=abs(gr[j]-num),ScaledError=abs(gr[j]-num)/max(1,abs(num)))
    }
  }
  rc<-data.frame(id=c("actual_chain_left_tail","actual_chain_right_tail","actual_chain_endpoint","actual_chain_narrow","actual_chain_u_shape"),m=c(.72,.08,.999,.4,.3),rho=c(.25,.1,.7,.2,.6),phi=c(280,120,120,30,.8),lo=c(.6,.4,.99,.35,.001),hi=c(.7,.5,1,.35+1e-10,.999))
  write.csv(rc,file.path(out,"record_parameter_cases.csv"),row.names=FALSE)
  for(i in seq_len(nrow(rc))) {
    z<-rc[i,];fit<-make_fit(2,z$lo,z$hi);th<-c(qlogis(z$m),qlogis(z$rho),log(z$phi))
    val<-log_prob(fit,th,adjust_transform=FALSE);gr<-grad_log_prob(fit,th,adjust_transform=FALSE);ref<-ref_record(z$lo,z$hi,th)
    values[[length(values)+1L]]<-data.frame(Case=z$id,Mode="record_chain",Stan=val,Reference=ref,AbsError=abs(val-ref))
    for(j in 1:3) {
      num<-fd5(function(v)ref_record(z$lo,z$hi,v),th,j)
      gradients[[length(gradients)+1L]]<-data.frame(Case=z$id,Mode="record_chain",Parameter=c("logit_m","logit_rho","log_phi_ratio")[j],Stan=gr[j],Reference=num,AbsError=abs(gr[j]-num),ScaledError=abs(gr[j]-num)/max(1,abs(num)))
    }
  }
}
v<-do.call(rbind,values);g<-do.call(rbind,gradients)
write.csv(v,file.path(out,"value_comparison.csv"),row.names=FALSE)
write.csv(g,file.path(out,"gradient_comparison.csv"),row.names=FALSE)
value_pass<-all(is.finite(v$Stan))&&all(v$AbsError<3e-7)
gradient_pass<-all(is.finite(g$Stan))&&all(g$ScaledError<3e-6)
status<-list(stage=stage,status=if(value_pass&&gradient_pass)"PASS" else "FAIL_REPRODUCED",purpose="synthetic_parameter_evaluation_only_no_posterior_sampling",value_count=nrow(v),gradient_count=nrow(g),value_pass=value_pass,gradient_pass=gradient_pass,max_value_abs_error=max(v$AbsError),max_gradient_scaled_error=max(g$ScaledError),rstan_version=as.character(packageVersion("rstan")),R_version=R.version.string,production_source=source_file,created_utc=format(Sys.time(),tz="UTC",usetz=TRUE))
jsonlite::write_json(status,file.path(out,"status.json"),pretty=TRUE,auto_unbox=TRUE,na="string")
print(v);print(g);print(status)
if(stage=="before")stopifnot(!value_pass) else stopifnot(value_pass,gradient_pass)
cat(if(stage=="before")"BETA_BEFORE_FAILURE_REPRODUCED\n" else "BETA_AFTER_NUMERICAL_AND_AUTODIFF_PASS\n")
