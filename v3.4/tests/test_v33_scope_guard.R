#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
base<-file.path(root,"review","baseline_v3_2")
retained<-c("applicability.R","bootstrap.R","cache_io.R","comparison.R","cross_validation.R","data_encoding.R","fitting.R","metrics.R","plotting.R","ppc.R","prediction.R","provenance.R","quantitative_diagnostics.R","weights.R","workflow.R")
checks<-vapply(retained,function(f)identical(sha256_file(file.path(root,"R",f)),sha256_file(file.path(base,"R",f))),logical(1))
checks<-c(checks,Stan=identical(sha256_file(file.path(root,"stan","joint_bb.stan")),sha256_file(file.path(base,"stan","joint_bb.stan"))))
new<-jsonlite::read_json(file.path(root,"config","analysis.json"),simplifyVector=TRUE);old<-jsonlite::read_json(file.path(base,"config","analysis.json"),simplifyVector=TRUE)
new$version<-old$version;checks<-c(checks,ConfigOnlyVersionChanged=identical(new,old))
# Compare two frozen copies of real input bytes, without generating predictions/scores.
checks<-c(checks,ObservationsUnchanged=identical(sha256_file(file.path(root,"input","observations.csv")),"3c886f7f2c11012463296b350a931543542b4e1c0d128ad3c408fda9ae824d79"),SitesUnchanged=identical(sha256_file(file.path(root,"input","sites.csv")),"0a99692b060f13d1faaa870d06ea7dca9a4f16bc289636bcc88f5d105ebdacb5"))
write_csv_atomic(data.frame(Item=names(checks),Unchanged=unname(checks)),file.path(root,"review","scope_preservation_checks.csv"))
stopifnot(all(checks));cat("V33_SCOPE_GUARD_PASS:15 core R modules, Stan, complete config except version and both original inputs unchanged\n")
