#!/usr/bin/env Rscript
# Bounded branch-switch check. Reuses an existing compiled Stan model; no MCMC.
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value=TRUE)[1])
root <- normalizePath(file.path(dirname(script), ".."),mustWork=TRUE)
out <- file.path(root,"review","beta_switches")
dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages(library(rstan))
prod<-readLines(file.path(root,"stan","joint_bb.stan"),warn=FALSE)
probe<-readLines(file.path(root,"tests","stan","beta_interval_probe_after.stan"),warn=FALSE)
endfun<-grep("^data \\{",prod)[1]-1L
stopifnot(identical(prod[seq_len(endfun)],probe[seq_len(endfun)]))
sm<-readRDS(file.path(root,"tests","stan","beta_interval_probe_after.rds"))
stopifnot(methods::is(sm,"stanmodel"))
ref<-function(lo,hi,a,b) {
  # Independent adaptive R integration of the original Beta density.
  shift<-max(dbeta(c(lo,(lo+hi)/2,hi),a,b,log=TRUE))
  ans<-integrate(function(t)exp(dbeta(lo+(hi-lo)*t,a,b,log=TRUE)-shift),0,1,
    abs.tol=1e-12,rel.tol=1e-12,subdivisions=2000L,stop.on.error=TRUE)$value
  log(hi-lo)+shift+log(ans)
}
fd<-function(lo,hi,a,b,j) {
  z<-c(a,b);h<-2e-4*z[j]
  at<-function(k){p<-z;p[j]<-p[j]+k*h;ref(lo,hi,p[1],p[2])}
  (at(-2)-8*at(-1)+8*at(1)-at(2))/(12*h)
}
tail_gap<-function(lo,hi,a,b) {
  if((lo+hi)/2 <= (a+1)/(a+b+2))
    pbeta(hi,a,b,log.p=TRUE)-pbeta(lo,a,b,log.p=TRUE)
  else pbeta(lo,a,b,lower.tail=FALSE,log.p=TRUE)-pbeta(hi,a,b,lower.tail=FALSE,log.p=TRUE)
}
cases<-list()
add<-function(group,delta,side,a,b,lo,hi,branch,threshold) {
 cases[[length(cases)+1L]]<<-data.frame(Group=group,RelativeOffset=delta,Side=side,a=a,b=b,lo=lo,hi=hi,ExpectedBranch=branch,Threshold=threshold)
}
for(pair in list(c(2.5,7.5),c(1,1)))for(delta in c(.01,.0001,.000001))for(side in c(-1,1)) {
 lo<-.3;hi<-lo+3e-6*(1+side*delta)
 add(paste0("width_a",pair[1],"_b",pair[2]),delta,side,pair[1],pair[2],lo,hi,if(side<0)"quadrature" else "tail_difference","relative_width_1e-5")
}
roots<-list()
for(ratio in c(1,2)) {
 lo<-.2;hi<-.8
 objective<-function(loga)log(tail_gap(lo,hi,exp(loga),ratio*exp(loga))/1e-7)
 loga<-uniroot(objective,c(log(1e-10),log(1e-5)),tol=1e-11)$root
 a0<-exp(loga)
 roots[[length(roots)+1L]]<-data.frame(b_over_a=ratio,a_at_switch=a0,b_at_switch=ratio*a0,ReferenceTailLogDifference=tail_gap(lo,hi,a0,ratio*a0))
 # 1e-4 relative separation is larger than CDF rounding uncertainty here.
 for(delta in c(.01,.0001))for(side in c(-1,1)) {
   a<-a0*(1+side*delta);b<-ratio*a
   add(paste0("tail_b_over_a_",ratio),delta,side,a,b,lo,hi,if(side<0)"quadrature" else "tail_difference","tail_log_gap_1e-7")
 }
}
cases<-do.call(rbind,cases)
cases$WidthTrigger<-(cases$hi-cases$lo)/(pmin(cases$lo,1-cases$hi))
cases$ReferenceTailLogDifference<-mapply(tail_gap,cases$lo,cases$hi,cases$a,cases$b)
stopifnot(all(cases$ReferenceTailLogDifference[cases$Threshold=="tail_log_gap_1e-7"&cases$Side<0]<1e-7),all(cases$ReferenceTailLogDifference[cases$Threshold=="tail_log_gap_1e-7"&cases$Side>0]>1e-7))
write.csv(cases,file.path(out,"cases.csv"),row.names=FALSE)
write.csv(do.call(rbind,roots),file.path(out,"tail_switch_reference_roots.csv"),row.names=FALSE)
rows<-list()
for(i in seq_len(nrow(cases))) {
 z<-cases[i,]
 fit<-suppressWarnings(sampling(sm,data=list(mode=1L,lo=z$lo,hi=z$hi),iter=1L,warmup=0L,chains=1L,algorithm="Fixed_param",init=list(list(theta=c(2,3,0))),refresh=0L,seed=731L))
 stan<-log_prob(fit,c(z$a,z$b,0),adjust_transform=FALSE)
 grad<-grad_log_prob(fit,c(z$a,z$b,0),adjust_transform=FALSE)
 actual<-ref(z$lo,z$hi,z$a,z$b);ga<-fd(z$lo,z$hi,z$a,z$b,1L);gb<-fd(z$lo,z$hi,z$a,z$b,2L)
 rows[[i]]<-cbind(z,data.frame(Stan=stan,Reference=actual,ValueAbsError=abs(stan-actual),Stan_da=grad[1],Ref_da=ga,GradientScaledError_a=abs(grad[1]-ga)/max(1,abs(ga)),Stan_db=grad[2],Ref_db=gb,GradientScaledError_b=abs(grad[2]-gb)/max(1,abs(gb))))
}
z<-do.call(rbind,rows)
write.csv(z,file.path(out,"value_and_gradient_comparison.csv"),row.names=FALSE)
pairs<-list()
for(key in unique(paste(z$Group,z$RelativeOffset,sep="|"))) {
 p<-z[paste(z$Group,z$RelativeOffset,sep="|")==key,];p<-p[order(p$Side),]
 stopifnot(nrow(p)==2L)
 valerr<-(p$Stan[2]-p$Stan[1])-(p$Reference[2]-p$Reference[1])
 aerr<-(p$Stan_da[2]-p$Stan_da[1])-(p$Ref_da[2]-p$Ref_da[1])
 berr<-(p$Stan_db[2]-p$Stan_db[1])-(p$Ref_db[2]-p$Ref_db[1])
 pairs[[length(pairs)+1L]]<-data.frame(Group=p$Group[1],RelativeOffset=p$RelativeOffset[1],StanValueChange=diff(p$Stan),ReferenceValueChange=diff(p$Reference),ValueChangeResidual=valerr,StanGradientChange_a=diff(p$Stan_da),ReferenceGradientChange_a=diff(p$Ref_da),GradientChangeScaledResidual_a=abs(aerr)/max(1,abs(p$Ref_da)),StanGradientChange_b=diff(p$Stan_db),ReferenceGradientChange_b=diff(p$Ref_db),GradientChangeScaledResidual_b=abs(berr)/max(1,abs(p$Ref_db)))
}
p<-do.call(rbind,pairs)
write.csv(p,file.path(out,"cross_switch_changes.csv"),row.names=FALSE)
value_pass<-all(is.finite(z$Stan))&&all(z$ValueAbsError<3e-7)
gradient_pass<-all(is.finite(z$Stan_da))&&all(is.finite(z$Stan_db))&&all(z$GradientScaledError_a<3e-6)&&all(z$GradientScaledError_b<3e-6)
change_pass<-all(abs(p$ValueChangeResidual)<6e-7)&&all(p$GradientChangeScaledResidual_a<6e-6)&&all(p$GradientChangeScaledResidual_b<6e-6)
status<-list(status=if(value_pass&&gradient_pass&&change_pass)"PASS" else "FAIL",purpose="synthetic_branch_switch_evaluation_only_reused_compiled_model_no_MCMC",value_count=nrow(z),gradient_count=2*nrow(z),cross_switch_pairs=nrow(p),value_pass=value_pass,gradient_pass=gradient_pass,change_pass=change_pass,max_value_abs_error=max(z$ValueAbsError),max_gradient_scaled_error=max(z$GradientScaledError_a,z$GradientScaledError_b),max_value_change_residual=max(abs(p$ValueChangeResidual)),max_gradient_change_scaled_residual=max(p$GradientChangeScaledResidual_a,p$GradientChangeScaledResidual_b),production_sha256=digest::digest(file=file.path(root,"stan","joint_bb.stan"),algo="sha256"),probe_rds_sha256=digest::digest(file=file.path(root,"tests","stan","beta_interval_probe_after.rds"),algo="sha256"),created_utc=format(Sys.time(),tz="UTC",usetz=TRUE),limitation="Numerical two-sided agreement at listed finite offsets, not proof of exact floating-point continuity or arbitrary double-precision inputs. Lentz denominator-clamp activation not tested.")
jsonlite::write_json(status,file.path(out,"status.json"),pretty=TRUE,auto_unbox=TRUE,na="string")
print(z);print(p);print(status)
stopifnot(value_pass,gradient_pass,change_pass)
cat("BETA_SWITCH_TWO_SIDED_NUMERICAL_AND_GRADIENT_PASS\n")
