#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"));root<-resolve_v3_root();load_v3_modules(root)
receipts<-list()
for(d in c("unequal_integration","fullgrid_synthetic")) {
 out<-file.path(root,"review",d,"results")
 e<-read.csv(file.path(out,"cv_record_predictions.csv"),stringsAsFactors=FALSE)
 b<-read.csv(file.path(out,"quantitative_bias_summary.csv"),stringsAsFactors=FALSE)
 p<-read.csv(file.path(out,"quantitative_plot_source.csv"),stringsAsFactors=FALSE)
 r<-verify_quantitative_outputs_v32(e,b,p);r$Fixture<-d;receipts[[d]]<-r
 cv<-read.csv(file.path(out,"cv_metrics_summary.csv"),stringsAsFactors=FALSE)
 cv<-cv[cv$Route=="joint_bb",,drop=FALSE]
 keys<-c("Design","Route","Model","TrainWeighting","EvalWeighting")
 fields<-c(keys,"Bias","PointSpeciesUsed","PISpeciesUsed","LogScoreSpeciesUsed")
 audit_compare_table_v3(b[,fields],cv[,fields],keys,paste(d,"bias_matches_main_CV"))
}
write_csv_atomic(do.call(rbind,receipts),file.path(root,"review","quantitative_artifact_receipts.csv"))
cat("QUANTITATIVE_ARTIFACT_AUDIT_PASS: both synthetic runs; bias/source values and main-CV consistency
")
