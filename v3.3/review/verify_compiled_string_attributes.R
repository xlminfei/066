suppressPackageStartupMessages(library(rstan))
sm<-readRDS('/project/v33/tests/stan/beta_interval_probe_after.rds')
print(attributes(sm@model_code))
