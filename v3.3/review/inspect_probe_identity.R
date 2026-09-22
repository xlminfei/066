suppressPackageStartupMessages(library(rstan))
root<-'/project/v33';sm<-readRDS(file.path(root,'tests/stan/beta_interval_probe_after.rds'))
expected<-readLines(file.path(root,'tests/stan/beta_interval_probe_after.stan'))
writeLines(sm@model_code,file.path(root,'review/probe_compiled_model_code.stan'))
actual<-strsplit(sm@model_code,'\n',fixed=TRUE)[[1]]
print(list(expected_lines=length(expected),actual_lines=length(actual),rds_hash=digest::digest(file=file.path(root,'tests/stan/beta_interval_probe_after.rds'),algo='sha256')))
print(head(expected,3));print(head(actual,5));print(tail(expected,5));print(tail(actual,8))
