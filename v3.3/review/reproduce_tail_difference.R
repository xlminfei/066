options(digits=17)
source('/project/v3.3/review/prediction_audit_v3_2_before.R')
a<-b<-1e-8;lo<-.4;hi<-.5
q<-integrate(function(t) exp(dbeta(lo+(hi-lo)*t,a,b,log=TRUE)-dbeta((lo+hi)/2,a,b,log=TRUE)),0,1,rel.tol=2e-13,abs.tol=0)$value
ref<-log(hi-lo)+dbeta((lo+hi)/2,a,b,log=TRUE)+log(q)
old<-audit_log_beta_interval_v3(lo,hi,a,b)
r<-list(a=a,b=b,lo=lo,hi=hi,old_audit=old,independent_integral=ref,absolute_error=abs(old-ref),tolerance=1e-10*max(1,abs(ref)),old_finite=is.finite(old),geometrically_narrow=(hi-lo)<1e-5*min(lo,1-hi),old_pass=abs(old-ref)<=1e-10*max(1,abs(ref)))
print(r)
jsonlite::write_json(r,'/project/v3.3/review/tail_difference_before.json',auto_unbox=TRUE,pretty=TRUE,digits=17)
stopifnot(r$old_finite,!r$geometrically_narrow,!r$old_pass)
cat('FINITE_INACCURATE_R_AUDIT_REPRODUCED_IN_LOCKED_R_ENVIRONMENT
')
