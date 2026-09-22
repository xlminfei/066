#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
e<-data.frame(Design="fixture",Fold=c(1,1,2,2),Route="joint_bb",Model="M2",TrainWeighting="record_equal",RecordID=paste0("r",1:4),Species=c("A","A","B","C"),Type=c("count","exact","count","interval"),ObservedPoint=c(.1,.4,.7,NA),PredictedPoint=c(.4,.6,.6,.5),LogPredictiveDensityRaw=-1,PredictedPI_lower=0,PredictedPI_upper=1,PIWidth=1,IntervalCovered=c(TRUE,TRUE,TRUE,NA),FitKey="SYNTHETIC_FIXTURE",RunPurpose="INTEGRATION_TEST_ONLY")
error<-tryCatch({
  d<-quantitative_diagnostics_v32(e)
  stopifnot(nrow(d$plot_source)==6L,nrow(d$summary)==2L,all(d$plot_source$Type!="interval"),all(d$summary$PointRecords==3L),all(d$summary$PointSpeciesUsed==2L))
  r<-d$summary[d$summary$EvalWeighting=="record_equal",];s<-d$summary[d$summary$EvalWeighting=="species_equal",]
  stopifnot(abs(r$Bias-2/15)<1e-12,abs(s$Bias-.075)<1e-12)
  for(ew in V3_EVAL_WEIGHTINGS){z<-d$plot_source[d$plot_source$EvalWeighting==ew,];stopifnot(abs(weighted_mean(z$SignedError,z$EvaluationWeight)-d$summary$Bias[d$summary$EvalWeighting==ew])<1e-12)}
  d2<-quantitative_diagnostics_v32(e[4:1,]);key<-function(z)paste(z$RecordID,z$EvalWeighting)
  z<-d2$plot_source[match(key(d$plot_source),key(d2$plot_source)),];stopifnot(isTRUE(all.equal(z$SignedError,d$plot_source$SignedError)),isTRUE(all.equal(z$EvaluationWeight,d$plot_source$EvaluationWeight)))
  TRUE
},error=function(err){cat("EXPECTED_OR_ACTUAL_FAILURE:",conditionMessage(err),"\n");FALSE})
if(!error)stop("quantitative diagnostic regression not satisfied")
out<-file.path(root,"review","quantitative_plot_fixture")
write_quantitative_diagnostics_v32(e,file.path(out,"results"),file.path(out,"figures"),test_only=TRUE)
stopifnot(file.info(file.path(out,"figures","quantitative_predicted_observed.pdf"))$size>1000L)
write_json_atomic(list(status="PASS_SYNTHETIC_PLOT",source_rows=6,records=3,species=2,interval_excluded=TRUE,bias_record_equal=2/15,bias_species_equal=.075,sign="predicted_minus_observed",input_shuffle_invariant=TRUE),file.path(out,"test_status.json"))
cat("QUANTITATIVE_PLOT_PASS: signed bias, point-set weights, interval exclusion, shuffled keys, PDF generated\n")
