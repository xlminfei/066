#!/usr/bin/env Rscript
# Synthetic parameters only; run before/after against the actual R audit helper.
argv<-commandArgs(TRUE);stage<-if(length(argv))argv[1] else "after";stopifnot(stage%in%c("before","after"))
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
if(stage=="before")source(file.path(root,"review","prediction_audit_v3_2_before.R"))
out<-file.path(root,"review",paste0("audit_beta_",stage));dir.create(out,recursive=TRUE,showWarnings=FALSE)
# The known fixed reference was evaluated independently at high precision;
# scaled adaptive integration below supplies an independent R cross-check.
ref_integral<-function(lo,hi,a,b) {
  mid<-lo+(hi-lo)/2
  scale<-dbeta(mid,a,b,log=TRUE)
  q<-integrate(function(t)exp(dbeta(lo+(hi-lo)*t,a,b,log=TRUE)-scale),0,1,subdivisions=4000L,rel.tol=2e-13,abs.tol=0,stop.on.error=TRUE)
  log(hi-lo)+scale+log(q$value)
}
cases<-data.frame(id=c("review_counterexample","tiny_wide","tiny_left","tiny_right","moderate","narrow_uniform","narrow_beta"),
 a=c(1e-8,1e-8,1e-7,.2,2.5,1,2.5),b=c(1e-8,1e-8,.2,1e-7,7.5,1,7.5),
 lo=c(.4,.1,.3,.4,.2,.45,.45),hi=c(.5,.9,.4,.5,.6,.45+1e-12,.45+1e-12))
actual<-mapply(audit_log_beta_interval_v3,cases$lo,cases$hi,cases$a,cases$b)
reference<-mapply(ref_integral,cases$lo,cases$hi,cases$a,cases$b)
stopifnot(abs(reference[1]-(-20.016548394229577))<1e-12)
z<-cbind(cases,Actual=actual,Reference=reference,AbsError=abs(actual-reference),Allowed=1e-10*pmax(1,abs(reference)))
z$Pass<-is.finite(z$Actual)&z$AbsError<=z$Allowed
write.csv(z,file.path(out,"regression_cases.csv"),row.names=FALSE)
# Mixed vector validates that fallback indices and the selected-tail swap align.
vector_actual<-audit_log_beta_interval_v3(.4,.5,c(1e-8,2,1e-7,200),c(1e-8,3,.2,1))
vector_reference<-mapply(function(a,b)ref_integral(.4,.5,a,b),c(1e-8,2,1e-7,200),c(1e-8,3,.2,1))
vector_pass<-all(abs(vector_actual-vector_reference)<=1e-10*pmax(1,abs(vector_reference)))
status<-list(stage=stage,status=if(all(z$Pass)&&vector_pass)"PASS" else "FAIL_REPRODUCED",cases=nrow(z),failures=sum(!z$Pass),vector_pass=vector_pass,max_abs_error=max(z$AbsError),formal_research_fits=0,posterior_sampling=FALSE)
write_json_atomic(status,file.path(out,"status.json"));print(z);print(status)
if(stage=="before")stopifnot(!z$Pass[1]) else stopifnot(all(z$Pass),vector_pass)
cat(if(stage=="before")"R_AUDIT_FAILURE_REPRODUCED
" else "R_AUDIT_REGRESSION_PASS
")
