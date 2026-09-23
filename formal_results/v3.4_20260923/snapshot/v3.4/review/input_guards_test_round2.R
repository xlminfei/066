#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
stage<-commandArgs(TRUE)[1];if(is.na(stage)||stage=="--root")stage<-"after";stopifnot(stage%in%c("before","after"))
baseline<-new.env(parent=.GlobalEnv);sys.source(file.path(root,"review","baseline_v3_3","R","bootstrap.R"),baseline)
baseline$load_v3_modules(file.path(root,"review","baseline_v3_3"),envir=baseline)
impl<-if(stage=="before")baseline else .GlobalEnv
out<-file.path(root,"review",paste0("input_guards_",stage));dir.create(out,recursive=TRUE,showWarnings=FALSE)
state<-list(binary_species=paste0("S",1:12),joint_species=paste0("S",1:12))
make_folds<-function(k)data.frame(Species=state$joint_species,Fold=rep(seq_len(k),length.out=12L),stringsAsFactors=FALSE)
folds<-list(fivefold=list(binary=make_folds(5),joint_bb=make_folds(5)),tenfold=list(binary=make_folds(10),joint_bb=make_folds(10)))
write_csv_atomic(folds$fivefold$binary,file.path(out,"valid_fivefold.csv"));write_csv_atomic(folds$tenfold$joint_bb,file.path(out,"valid_tenfold.csv"))
results<-list()
record<-function(id,kind,expected_error,fn){
 value<-tryCatch(fn(),error=identity);rejected<-inherits(value,"error")
 results[[length(results)+1L]]<<-data.frame(Test=id,Kind=kind,ExpectedError=expected_error,Rejected=rejected,Pass=identical(rejected,expected_error),Message=if(rejected)conditionMessage(value) else "accepted",stringsAsFactors=FALSE)
}
check_fold<-function(id,f,expected_error=TRUE)record(id,"fold_contract",expected_error,function()impl$validate_fold_tables_v3(state,f))
check_fold("valid_complete_designs",folds,FALSE)
check_fold("valid_reordered_designs",folds[2:1],FALSE)
q<-folds;for(d in names(q))for(r in names(q[[d]]))q[[d]][[r]]<-q[[d]][[r]][12:1,];check_fold("valid_shuffled_species_rows",q,FALSE)
q<-folds;for(d in names(q))for(r in names(q[[d]]))q[[d]][[r]]$Fold<-as.numeric(q[[d]][[r]]$Fold);check_fold("valid_double_integer_fold_ids",q,FALSE)
q<-folds;for(d in names(q))for(r in names(q[[d]]))q[[d]][[r]]$Species<-factor(q[[d]][[r]]$Species);check_fold("valid_factor_species_labels",q,FALSE)
check_fold("missing_tenfold",folds["fivefold"]);check_fold("missing_fivefold",folds["tenfold"])
check_fold("unnamed_designs",unname(folds));check_fold("empty_designs",list())
q<-folds;names(q)[2]<-"unknown";check_fold("unknown_design",q)
q<-folds;names(q)[2]<-"";check_fold("empty_design_name",q)
q<-folds;names(q)[2]<-NA_character_;check_fold("NA_design_name",q)
q<-c(folds,folds["fivefold"]);check_fold("duplicate_design_name",q)
for(d in V3_DESIGNS)for(r in V3_ROUTES){
 q<-folds;q[[d]][[r]]$Fold[1]<-NA_real_;check_fold(paste("NA_fold",d,r,sep="_"),q)
 q<-folds;q[[d]][[r]]$Fold[1]<-NaN;check_fold(paste("NaN_fold",d,r,sep="_"),q)
}
for(value in c(-Inf,Inf,0,-1,1.5,11)){
 q<-folds;q$fivefold$binary$Fold[1]<-value;check_fold(paste0("invalid_fold_",value),q)
}
q<-folds;q$fivefold$binary$Fold<-as.character(q$fivefold$binary$Fold);check_fold("character_fold_rejected",q)
q<-folds;q$fivefold$binary$Fold<-factor(q$fivefold$binary$Fold);check_fold("factor_fold_rejected",q)
q<-folds;q$fivefold$binary$Fold<-NULL;check_fold("missing_fold_column",q)
q<-folds;q$fivefold$binary<-as.list(q$fivefold$binary);check_fold("non_dataframe_table",q)
q<-folds;q$fivefold$binary$Fold[q$fivefold$binary$Fold==5]<-4L;check_fold("missing_fold_id",q)
q<-folds;q$fivefold$binary<-rbind(q$fivefold$binary,q$fivefold$binary[1,]);check_fold("duplicate_species_same_fold",q)
q<-folds;extra<-q$fivefold$binary[1,];extra$Fold<-2L;q$fivefold$binary<-rbind(q$fivefold$binary,extra);check_fold("duplicate_species_conflicting_fold",q)
q<-folds;q$fivefold$binary$Species[1]<-NA_character_;check_fold("NA_species",q)
q<-folds;q$fivefold$binary$Species[1]<-" ";check_fold("empty_species",q)
q<-folds;q$fivefold$binary<-q$fivefold$binary[-1,];check_fold("missing_species",q)
q<-folds;q$fivefold$binary$Species[1]<-"UNKNOWN";check_fold("unknown_species",q)
q<-folds;q$fivefold$joint_bb<-NULL;check_fold("missing_route",q)
q<-folds;q$fivefold<-c(q$fivefold,q$fivefold["binary"]);check_fold("duplicate_route_name",q)
q<-folds;q$fivefold$binary<-cbind(q$fivefold$binary,Fold=q$fivefold$binary$Fold);check_fold("duplicate_column_name",q)
record("configured_twofold_test_design","fold_contract",FALSE,function(){
 old_d<-impl$V3_DESIGNS;old_k<-impl$V3_DESIGN_K
 on.exit({impl$V3_DESIGNS<-old_d;impl$V3_DESIGN_K<-old_k})
 impl$V3_DESIGNS<-"integration";impl$V3_DESIGN_K<-c(integration=2L)
 impl$validate_fold_tables_v3(state,list(integration=list(binary=make_folds(2),joint_bb=make_folds(2))))
})
e<-data.frame(RecordID=paste0("r",1:4),Route="joint_bb",Species=c("A","A","B","C"),Type=c("count","exact","count","interval"),ObservedPoint=c(0,1,.4,NA),PredictedPoint=c(0,1,.3,.5),LogPredictiveDensityRaw=c(-1,-2,-3,-4),PredictedPI_lower=0,PredictedPI_upper=1,PIWidth=1,IntervalCovered=c(TRUE,TRUE,TRUE,NA))
write_csv_atomic(e,file.path(out,"valid_joint_evidence.csv"))
for(w in V3_EVAL_WEIGHTINGS){
 record(paste0("valid_joint_",w),"joint_range",FALSE,function()impl$evaluate_evidence(e,w,"joint_bb"))
 for(type in c("count","exact","interval"))for(value in c(-.2,1.2,-.Machine$double.eps,1+.Machine$double.eps,NA,NaN,Inf,-Inf)){
  q<-e;idx<-which(q$Type==type)[1];q$PredictedPoint[idx]<-value
  record(paste("prediction",w,type,value,sep="_"),"joint_range",TRUE,function()impl$evaluate_evidence(q,w,"joint_bb"))
 }
 for(type in c("count","exact"))for(value in c(-.2,1.2,-.Machine$double.eps,1+.Machine$double.eps,NA,NaN,Inf,-Inf)){
  q<-e;idx<-which(q$Type==type)[1];q$ObservedPoint[idx]<-value
  q$IntervalCovered[idx]<-if(is.na(value))NA else value>=0&&value<=1
  record(paste("observation",w,type,value,sep="_"),"joint_range",TRUE,function()impl$evaluate_evidence(q,w,"joint_bb"))
 }
 for(type in c("count","exact","interval"))for(value in c(0,1)){
  q<-e;idx<-which(q$Type==type)[1];q$PredictedPoint[idx]<-value
  record(paste("valid_prediction_boundary",w,type,value,sep="_"),"joint_range",FALSE,function()impl$evaluate_evidence(q,w,"joint_bb"))
 }
 for(type in c("count","exact"))for(value in c(0,1)){
  q<-e;idx<-which(q$Type==type)[1];q$ObservedPoint[idx]<-value;q$IntervalCovered[idx]<-TRUE
  record(paste("valid_observation_boundary",w,type,value,sep="_"),"joint_range",FALSE,function()impl$evaluate_evidence(q,w,"joint_bb"))
 }
 q<-e[4,,drop=FALSE]
 record(paste0("valid_interval_only_",w),"joint_range",FALSE,function(){s<-impl$evaluate_evidence(q,w,"joint_bb");stopifnot(is.na(s$MAE),is.na(s$Bias),s$PointRecords==0);TRUE})
}
q<-e;q$ObservedPoint[4]<-99
record("interval_observed_field_is_not_scored","joint_range",FALSE,function(){stopifnot(identical(impl$evaluate_evidence(q,"species_equal","joint_bb"),impl$evaluate_evidence(e,"species_equal","joint_bb")));TRUE})
fit_calls<-0L;sentinel<-function(...){fit_calls<<-fit_calls+1L;stop("SAMPLER_SENTINEL_CALLED")}
blocked_root<-file.path(out,"must_not_create_cv_output")
err<-tryCatch(impl$run_cv_v3(state,blocked_root,folds["fivefold"],NULL,fit_function=sentinel),error=identity)
results[[length(results)+1L]]<-data.frame(Test="incomplete_design_stops_before_fit_or_output",Kind="entrypoint_guard",ExpectedError=TRUE,Rejected=inherits(err,"error"),Pass=inherits(err,"error")&&fit_calls==0L&&!dir.exists(blocked_root),Message=paste(if(inherits(err,"error"))conditionMessage(err) else "accepted","fit_calls",fit_calls))
res<-do.call(rbind,results);write_csv_atomic(res,file.path(out,"assertions.csv"))
status<-list(stage=stage,status=if(all(res$Pass))"PASS" else "FAIL_REPRODUCED",checks=nrow(res),passed=sum(res$Pass),failed=sum(!res$Pass),sampler_callback_calls=fit_calls,actual_samplers_started=0L,real_data_fits=0L)
write_json_atomic(status,file.path(out,"status.json"));print(status)
if(stage=="before"){
 key<-c("missing_tenfold","NA_fold_fivefold_binary","prediction_record_equal_count_1.2","observation_record_equal_exact_1.2")
 stopifnot(all(!res$Pass[match(key,res$Test)]),all(!res$Rejected[match(key,res$Test)]));cat("V33_INPUT_GAPS_REPRODUCED; no sampler executed\n")
}else{if(!all(res$Pass)){print(res[!res$Pass,]);stop("Input guard regression failed")};cat("V34_INPUT_GUARDS_PASS\n")}
