#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
base<-read.csv(file.path(root,"review","inherited_beta_cases","parameter_cases.csv"))
base$Group<-"inherited_266"
switch<-read.csv(file.path(root,"review","inherited_beta_cases","switch_cases.csv"))
switch<-data.frame(id=paste0("inherited_switch_",seq_len(nrow(switch))),a=switch$a,b=switch$b,lo=switch$lo,hi=switch$hi,Group="inherited_switch_24")
extra<-data.frame(id=c("review_counterexample","tiny_shape_1e12","tiny_shape_1e6","tiny_shape_asymmetric"),a=c(1e-8,1e-12,1e-6,1e-9),b=c(1e-8,1e-12,2e-6,3e-8),lo=c(.4,.4,.2,.3),hi=c(.5,.5,.8,.6),Group="new_counterexamples")
cases<-rbind(base,switch,extra)
gap<-function(a,b,lo,hi) {ch<-pbeta(hi,a,b,log.p=TRUE);cl<-pbeta(lo,a,b,log.p=TRUE);sl<-pbeta(lo,a,b,lower.tail=FALSE,log.p=TRUE);sh<-pbeta(hi,a,b,lower.tail=FALSE,log.p=TRUE);if(ch<=sl)ch-cl else sl-sh}
for(ratio in c(1,2)) {
 a0<-exp(uniroot(function(x)log(gap(exp(x),ratio*exp(x),.2,.8)/1e-4),c(log(1e-6),log(1e-3)),tol=1e-12)$root)
 for(delta in c(.01,.0001,.000001))for(side in c(-1,1))cases<-rbind(cases,data.frame(id=paste("audit_gap",ratio,delta,side,sep="_"),a=a0*(1+side*delta),b=ratio*a0*(1+side*delta),lo=.2,hi=.8,Group="audit_gap_switch"))
}
for(delta in c(.01,.0001,.000001))for(side in c(-1,1))cases<-rbind(cases,data.frame(id=paste("audit_shape",delta,side,sep="_"),a=1e-5*(1+side*delta),b=.2,lo=.3,hi=.4,Group="audit_shape_switch"))
# Save round-trip-safe decimal values; serialize the actual IEEE doubles checked.
cols<-c("id","a","b","lo","hi","Group")
encoded<-cases[,cols];for(n in c("a","b","lo","hi"))encoded[[n]]<-sprintf("%.17g",cases[[n]])
out<-file.path(root,"review","audit_beta_three_way");dir.create(out,recursive=TRUE,showWarnings=FALSE)
write.csv(encoded,file.path(out,"cases.csv"),row.names=FALSE)
cat("AUDIT_BETA_CASES",nrow(cases),"
")
