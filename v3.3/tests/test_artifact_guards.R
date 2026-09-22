#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
assert_error<-function(expr,label){x<-tryCatch({force(expr);FALSE},error=function(e)TRUE);if(!x)stop("Expected rejection: ",label);cat("PASS:",label,"\n")}
out<-file.path(root,"review/integration");state<-prepare_state(file.path(out,"input"))
b<-readRDS(fit_path_v3(out,"binary","Null","record_equal","integration",1));other<-readRDS(fit_path_v3(out,"binary","Null","record_equal","integration",2))
spec<-fit_spec_v3(state,"binary","Null",b$train_species,"record_equal",NULL,b$request$sampling,b$request$seed)
validate_fitted_bundle_v3(b,spec,FALSE)
bad<-b;bad$fit<-other$fit;assert_error(validate_fitted_bundle_v3(bad,spec,FALSE),"swapped actual fit object refused")
bad<-b;bad$key<-"wrong";assert_error(validate_fitted_bundle_v3(bad,spec,FALSE),"wrong cache key refused")
p<-tempfile();writeLines("not an RDS",p);stopifnot(!cache_is_valid(p,b$request,b$route,b$model,b$train_weighting))
cat("PASS: corrupt RDS refused\n")
bad<-b;bad$diagnostics$Status<-"PASS";if(b$diagnostics$Status!="PASS")assert_error(validate_fitted_bundle_v3(bad,spec,TRUE),"forged PASS diagnostic is recomputed and refused")
# On-disk fit-payload fingerprint must survive RDS roundtrip.
p<-tempfile();saveRDS(b,p);again<-readRDS(p);stopifnot(identical(fit_payload_hash_v3(again$fit),b$fit_payload_hash))
cat("PASS: payload fingerprint survives RDS roundtrip\n")
# Actual entry point, copied project in a temporary directory, invalid config.
tmp<-tempfile("v31_failure_");dir.create(tmp)
for(dir in c("R","src","config","input","stan"))file.copy(file.path(root,dir),tmp,recursive=TRUE)
write_json_atomic(list(status="COMPLETE"),file.path(tmp,"review","final_v3_status.json"))
cfg<-read_config_v3(tmp);cfg$sampling$warmup<-cfg$sampling$iter;write_json_atomic(cfg,file.path(tmp,"config","analysis.json"))
status<-suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),c(file.path(tmp,"src","v3_pipeline.R"),"--stage","all"),stdout=FALSE,stderr=FALSE))
stopifnot(status!=0,jsonlite::read_json(file.path(tmp,"review","final_v3_status.json"))$status=="FAILED")
cat("PASS: invalid configuration overwrites stale COMPLETE with FAILED\n")
# Bad canonical plan must replace old audit PASS with FAILED.
real_state<-load_state_v3(root);plan<-task_plan_v3(real_state,make_fold_tables_v3(real_state));plan[2,]<-plan[1,];plan$FitID[2]<-"unique_but_wrong"
write_csv_atomic(plan,file.path(tmp,"runs","run_plan.csv"));write_json_atomic(list(status="PASS"),file.path(tmp,"review","audit_v3.json"))
assert_error(audit_plan_v3(real_state,tmp,file.path(tmp,"runs"),file.path(tmp,"review")),"same-length wrong task grid refused")
stopifnot(jsonlite::read_json(file.path(tmp,"review","audit_v3.json"))$status=="FAILED")
cat("PASS: invalid plan cannot retain stale audit PASS\n")
# Current output receipt rejects a stale or modified file.
write_json_atomic(read_config_v3(root),file.path(tmp,"config","analysis.json"))
write_csv_atomic(data.frame(x=1),file.path(tmp,"results","test.csv"))
write_stage_receipt_v3(tmp,real_state,"fixture","results/test.csv")
verify_stage_receipt_v3(tmp,real_state,"fixture")
write_csv_atomic(data.frame(x=2),file.path(tmp,"results","test.csv"))
assert_error(verify_stage_receipt_v3(tmp,real_state,"fixture"),"changed output cannot reuse receipt")
cat("ARTIFACT_GUARD_PASS\n")
