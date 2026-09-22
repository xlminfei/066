#!/usr/bin/env Rscript
# Compare actual production Stan, current R audit, and independent100-digit values.
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
options(warn=1)
suppressPackageStartupMessages(library(rstan))
out<-file.path(root,"review","audit_beta_three_way")
z<-read.csv(file.path(out,"high_precision_reference.csv"),stringsAsFactors=FALSE)
stopifnot(nrow(z)==312L,all(z$PrecisionDigits==100L),!anyDuplicated(z$id))
production<-readLines(file.path(root,"stan","joint_bb.stan"),warn=FALSE)
probe<-readLines(file.path(root,"tests","stan","beta_interval_probe_after.stan"),warn=FALSE)
end<-grep("^data \{",production)[1]-1L
stopifnot(identical(production[seq_len(end)],probe[seq_len(end)]))
sm<-readRDS(file.path(root,"tests","stan","beta_interval_probe_after.rds"))
stopifnot(methods::is(sm,"stanmodel"),identical(trimws(paste(probe,collapse="\n")),trimws(sm@model_code)))
old<-new.env(parent=globalenv());sys.source(file.path(root,"review","prediction_audit_v3_2_before.R"),old)
cache<-new.env();rows<-list();branch_rows<-list()
for(i in seq_len(nrow(z))) {
 c<-z[i,];key<-paste(sprintf("%.17g",c$lo),sprintf("%.17g",c$hi),sep="|")
 if(!exists(key,cache,inherits=FALSE)) {
  fit<-suppressWarnings(sampling(sm,data=list(mode=1L,lo=c$lo,hi=c$hi),iter=1L,warmup=0L,chains=1L,algorithm="Fixed_param",init=list(list(theta=c(2,3,0))),refresh=0L,seed=733L))
  assign(key,fit,cache)
 }
 stan<-log_prob(get(key,cache),c(c$a,c$b,0),adjust_transform=FALSE)
 audit<-audit_log_beta_interval_v3(c$lo,c$hi,c$a,c$b)
 before<-old$audit_log_beta_interval_v3(c$lo,c$hi,c$a,c$b)
 ref<-c$ReferenceLogP;bound<-1e-10*max(1,abs(ref))
 rows[[i]]<-data.frame(Case=c$id,Group=c$Group,a=c$a,b=c$b,lo=c$lo,hi=c$hi,Reference=ref,Stan=stan,Audit=audit,OldAudit=before,
  StanAbsError=abs(stan-ref),AuditAbsError=abs(audit-ref),OldAuditAbsError=abs(before-ref),StanAuditAbsDifference=abs(stan-audit),Allowed=bound,
  StanPass=is.finite(stan)&&abs(stan-ref)<=bound,AuditPass=is.finite(audit)&&abs(audit-ref)<=bound,PairPass=is.finite(audit)&&abs(stan-audit)<=bound)
 if(i%%50L==0L){cat("THREE_WAY",i,"/",nrow(z),"\n");flush.console()}
}
r<-do.call(rbind,rows);write_csv_atomic(r,file.path(out,"three_way_values.csv"))
# Explicit table-audit test: the old finite result wrongly rejects a correct value.
review<-r[r$Case=="review_counterexample",]
expected<-data.frame(Key="counterexample",LogProbability=review$Reference)
actual<-data.frame(Key="counterexample",LogProbability=review$Audit)
prior<-data.frame(Key="counterexample",LogProbability=review$OldAudit)
stopifnot(inherits(tryCatch(audit_compare_table_v3(prior,expected,"Key"),error=identity),"error"))
audit_compare_table_v3(actual,expected,"Key")
# Vector/permutation behavior and independent upper-endpoint mixture.
order<-c(3,1,4,2);aa<-c(1e-8,2,1e-7,200);bb<-c(1e-8,3,.2,1)
p<-audit_log_beta_interval_v3(.4,.5,aa,bb)
stopifnot(identical(p[order],audit_log_beta_interval_v3(.4,.5,aa[order],bb[order])))
stopifnot(all(audit_log_beta_interval_v3(0,1,aa,bb)==0))
rc<-read.csv(file.path(root,"review","inherited_beta_cases","record_parameter_cases.csv"))
mix<-list()
for(i in seq_len(nrow(rc))) {
 c<-rc[i,];fit<-suppressWarnings(sampling(sm,data=list(mode=2L,lo=c$lo,hi=c$hi),iter=1L,warmup=0L,chains=1L,algorithm="Fixed_param",init=list(list(theta=c(2,3,0))),refresh=0L,seed=734L))
 theta<-c(qlogis(c$m),qlogis(c$rho),log(c$phi));stan<-log_prob(fit,theta,adjust_transform=FALSE)
 observation<-data.frame(Type="interval",Lower=c$lo,Upper=c$hi)
 audit<-raw_joint_loglik_audit_v3(observation,c$m,c$rho,0,log(c$phi))
 mix[[i]]<-data.frame(Case=c$id,Stan=stan,Audit=audit,AbsDifference=abs(stan-audit),Allowed=1e-10*max(1,abs(stan)))
}
mix<-do.call(rbind,mix);write_csv_atomic(mix,file.path(out,"raw_record_audit_comparison.csv"))
pass<-all(r$StanPass&r$AuditPass&r$PairPass)&&all(is.finite(mix$Audit)&mix$AbsDifference<=mix$Allowed)
status<-list(status=if(pass)"PASS" else "FAIL",interval_cases=nrow(r),mixture_record_cases=nrow(mix),old_audit_failures=sum(!is.finite(r$OldAudit)|r$OldAuditAbsError>r$Allowed),max_audit_abs_error=max(r$AuditAbsError),max_audit_scaled_error=max(r$AuditAbsError/pmax(1,abs(r$Reference))),max_stan_scaled_error=max(r$StanAbsError/pmax(1,abs(r$Reference))),max_pair_scaled_difference=max(r$StanAuditAbsDifference/pmax(1,abs(r$Reference))),max_mixture_difference=max(mix$AbsDifference),reference="mpmath1.3.0_100_decimal_digits_independent_incomplete_beta_and_closed_forms",production_stan_sha256=sha256_file(file.path(root,"stan","joint_bb.stan")),audit_source_sha256=sha256_file(file.path(root,"R","prediction_audit.R")),probe_rds_sha256=sha256_file(file.path(root,"tests","stan","beta_interval_probe_after.rds")),tolerance="1e-10*max(1,abs(reference_log_probability))",posterior_sampling=FALSE,formal_research_fits=0)
write_json_atomic(status,file.path(out,"status.json"));print(status);stopifnot(pass)
cat("AUDIT_BETA_THREE_WAY_PASS; reused_source_verified_Stan_model; fixed_parameter_evaluation_only\n")
