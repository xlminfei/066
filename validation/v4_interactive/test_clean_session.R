# Execute the actual annotated entry expression-by-expression in a clean R session.
# One native saved fit tests the cache path. Bulk fitting is explicitly a stand-in.
args <- commandArgs(TRUE)
.test_repo <- normalizePath(args[1], mustWork=TRUE)
.test_formal <- normalizePath(args[2], mustWork=TRUE)
.test_out <- normalizePath(args[3], mustWork=FALSE)
dir.create(.test_out,recursive=TRUE,showWarnings=FALSE)
.test_route <- if (length(args) >= 4L) args[4L] else "binary"
stopifnot(.test_route %in% c("binary","joint_bb"))
.test_log <- list()
.test_assert <- function(name,pass) {
  .test_log[[length(.test_log)+1L]] <<- data.frame(Check=name,Pass=isTRUE(pass))
  write.csv(do.call(rbind,.test_log),file.path(.test_out,"checks.csv"),row.names=FALSE)
  if(!isTRUE(pass))stop(name)
}
.test_fails <- function(code) inherits(try(force(code),silent=TRUE),"try-error")
.test_code <- file.path(.test_repo,"v4","interactive_analysis.R")
.test_expressions <- parse(.test_code,keep.source=TRUE)
.test_comments <- list()
for(.file in c("interactive_analysis.R","interactive_support.R")) {
  .path <- file.path(.test_repo,"v4",.file)
  .lines <- readLines(.path,warn=FALSE,encoding="UTF-8")
  .parsed <- parse(.path,keep.source=TRUE)
  .tokens <- getParseData(.parsed)
  .rows <- which(nzchar(trimws(.lines)) & !grepl("^\\s*#",.lines))
  .comment_rows <- .tokens$line1[.tokens$token=="COMMENT" & grepl("[\u4e00-\u9fff]",.tokens$text,perl=TRUE)]
  .test_assert(paste("Every executable line has a Chinese comment",.file),all(.rows%in%.comment_rows))
  .test_comments[[length(.test_comments)+1L]]<-data.frame(File=.file,CodeLines=length(.rows),AnnotatedLines=sum(.rows%in%.comment_rows))
}
write.csv(do.call(rbind,.test_comments),file.path(.test_out,"comment_coverage.csv"),row.names=FALSE)
.test_assert("Interactive files do not use commandArgs",!any(grepl("commandArgs\\(",readLines(.test_code,warn=FALSE))))
.test_reference <- file.path(.test_repo,"validation/v4/orchestration")
.test_bulk_calls <- 0L
.test_reuse_checks <- 0L
.test_cache_preloaded <- FALSE
.test_native_source <- file.path(.test_formal,"runs/fits",paste0(.test_route,"__M1__record_equal__fivefold_f1"),"fit.rds")
.test_events <- character()
.test_install_guards <- function() {
  .real_fit_from_spec <<- fit_from_spec
  fit_from_spec <<- function(spec,path) {
    if(!file.exists(path))stop("TEST_POLICY: new MCMC is forbidden in this validation")
    .real_fit_from_spec(spec,path)
  }
  fit_stage <<- function(root,state,output_dir,fit_function=fit_from_spec) {
    .test_bulk_calls <<- .test_bulk_calls+1L
    selected<-task_plan(state);selected<-selected[selected$FitID==example_task$FitID,]
    .test_assert("Example uses one of the same 128 planned identities",nrow(selected)==1L&&identical(selected$Seed,example_task$Seed))
    .fresh_spec<-fit_spec(state,route,model,train_species,file.path(root,"stan/joint_bb.stan"),seed=selected$Seed)
    .test_assert("Example and automatic task have identical model identity",identical(.fresh_spec$key,spec$key))
    .test_assert("Example and automatic task have identical cache path",identical(example_fit_path,file.path(output_dir,"fits",paste0(selected$FitID,".rds"))))
    .reused<-fit_from_spec(.fresh_spec,example_fit_path)
    .test_reuse_checks <<- .test_reuse_checks+1L
    .test_assert("Same cached native posterior reused",identical(.reused$key,bundle$key))
    .fits<-file.path(.test_reference,"fits")
    dir.create(file.path(output_dir,"fits"),recursive=TRUE,showWarnings=FALSE)
    for(.f in list.files(.fits,full.names=TRUE)) {
      .target<-file.path(output_dir,"fits",basename(.f))
      if(.target!=example_fit_path)stopifnot(file.copy(.f,.target,overwrite=FALSE))
    }
    for(.n in stage_files("fit"))stopifnot(file.copy(file.path(.test_reference,.n),file.path(output_dir,.n),overwrite=TRUE))
    .d<-read.csv(file.path(output_dir,"fit_diagnostics.csv"),stringsAsFactors=FALSE)
    .i<-match(selected$FitID,.d$FitID)
    .d$FitKey[.i]<-.reused$key
    for(.n in names(.reused$diagnostics)) .d[.i,.n]<-.reused$diagnostics[[.n]]
    write_csv_atomic(.d,file.path(output_dir,"fit_diagnostics.csv"))
    .fm<-read.csv(file.path(output_dir,"fit_manifest.csv"),stringsAsFactors=FALSE)
    .j<-match(selected$FitID,.fm$FitID)
    .fm$Bytes[.j]<-file.info(example_fit_path)$size
    .fm$SHA256[.j]<-sha256_file(example_fit_path)
    .fm$FitKey[.j]<-.reused$key
    write_csv_atomic(.fm,file.path(output_dir,"fit_manifest.csv"))
    .e<-read.csv(file.path(output_dir,"cv_record_predictions.csv"),stringsAsFactors=FALSE)
    .pick<-.e$Route==route&.e$Model==model&.e$Design==design&.e$Fold==fold_id
    .e$FitKey[.pick]<-.reused$key
    write_csv_atomic(.e,file.path(output_dir,"cv_record_predictions.csv"))
    check_cv_evidence(state,.e)
    stage_receipt("fit",state,output_dir)
    cat("TEST_BULK_STAND_IN: 127 stand-in files + 1 saved native cache; no MCMC\n")
    .e
  }
}
.test_install_native_cache <- function() {
  .b<-readRDS(.test_native_source)
  .test_assert("Saved model training data values agree",isTRUE(all.equal(.b$data,spec$data,tolerance=0)))
  .test_assert("Saved model blueprint agrees",identical(.b$blueprint,spec$blueprint))
  .test_assert("Saved model Stan code agrees",identical(.b$code,spec$code))
  .b$request<-spec$request;.b$key<-spec$key;.b$version<-VERSION
  .b$data<-spec$data;.b$payload_hash<-fit_payload_hash(.b$fit)
  validate_fit_cache(.b,spec)
  save_rds_atomic(.b,example_fit_path)
  .test_assert("Native replay fixture validates under v4 metadata",file.exists(example_fit_path))
  .test_cache_preloaded <<- TRUE
}
for(.i in seq_along(.test_expressions)) {
  .expr<-.test_expressions[[.i]]
  .assignment<-is.call(.expr)&&identical(.expr[[1]],as.name("<-"))
  .lhs<-if(.assignment&&is.symbol(.expr[[2]]))as.character(.expr[[2]]) else ""
  if(.lhs=="project_dir") .expr[[3]]<-file.path(.test_repo,"v4")
  if(.lhs=="route") .expr[[3]]<-.test_route
  if(.lhs=="output_dir"&&is.call(.expr[[3]])&&identical(.expr[[3]][[1]],as.name("file.path")))
    .expr[[3]]<-file.path(.test_out,"clean_session")
  eval(.expr,envir=.GlobalEnv)
  if(.lhs=="loaded_analysis_id") .test_install_guards()
  if(.lhs=="example_fit_path") .test_install_native_cache()
  .test_events<-c(.test_events,paste(.i,if(nzchar(.lhs)).lhs else as.character(.expr[[1]])))
}
.test_assert("Full annotated entry evaluated from a clean session",length(.test_events)==length(.test_expressions))
.test_assert("Exactly one native example was preloaded",.test_cache_preloaded)
.test_assert("Exactly one bulk dispatch and one native-cache reuse check",.test_bulk_calls==1L&&.test_reuse_checks==1L)
.final<-jsonlite::read_json(file.path(output_dir,"status.json"),simplifyVector=TRUE)
.test_assert("Final completion is gated by actual output checks",.final$status%in%c("COMPLETE","COMPLETE_WITH_REVIEW_FLAGS"))
.test_assert("No output sink remains open",sink.number(type="output")==0L)
.test_assert("Example has a saved single-fold diagnostic and prediction",all(file.exists(file.path(output_dir,c("interactive_example_diagnostics.csv","interactive_example_predictions.csv")))))
.old_example<-read.csv(file.path(.test_reference,"cv_record_predictions.csv"),stringsAsFactors=FALSE)
.old_example<-.old_example[.old_example$Route==route&.old_example$Model==model&.old_example$Design==design&.old_example$Fold==fold_id,]
.old_example<-.old_example[match(example_predictions$RecordID,.old_example$RecordID),]
.example_fields<-if(route=="binary")c("PredictedPrHigh","LogPredictiveDensityRaw") else c("PredictedPoint","LogPredictiveDensityRaw","PredictedPI_lower","PredictedPI_upper")
.example_error<-max(abs(as.matrix(example_predictions[.example_fields])-as.matrix(.old_example[.example_fields])))
.test_assert("Native example predictions reconcile",is.finite(.example_error)&&.example_error<1e-12)
.reference_tests<-read.csv(file.path(.test_repo,"validation/v4/metrics_final/hypothesis_tests.csv"),stringsAsFactors=FALSE)
.tests<-results$hypothesis_tests
.keys<-c("Route","Metric","Design","Model","TrainWeighting","EvalWeighting")
.reference_tests<-.reference_tests[match(metric_key(.tests,.keys),metric_key(.reference_tests,.keys)),]
.fields<-c("Estimate","Difference","SE_approx","CI95_lower","CI95_upper","P_approx","P_BH3")
.inference_error<-max(abs(as.matrix(.tests[.fields])-as.matrix(.reference_tests[.fields])),na.rm=TRUE)
.test_assert("Interactive results preserve all 30 tests and BH3",nrow(.tests)==30L&&.inference_error<1e-12)
write.csv(data.frame(Expression=seq_along(.test_events),Executed=.test_events),file.path(.test_out,"executed_expressions.csv"),row.names=FALSE)
write_json_atomic(list(status="PASS",purpose="clean_R_expression_replay_native_cache_and_bulk_stand_ins",
  example_route=.test_route,command_line_has_file_arg=any(grepl("^--file=",commandArgs(FALSE))),expressions=length(.test_expressions),checks=length(.test_log),new_mcmc_fits=0,old_native_fit_replayed=1,
  bulk_stand_in_files=127,bulk_dispatch_calls=.test_bulk_calls,native_reuse_checks=.test_reuse_checks,
  maximum_example_prediction_error=.example_error,maximum_test_numeric_error=.inference_error,
  expected_formal_task_count=128L,final_status=.final$status,analysis_id=analysis_identity(root)),
  file.path(.test_out,"test_status.json"))
cat("INTERACTIVE_CLEAN_SESSION_PASS; no new MCMC\n")
