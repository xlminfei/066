script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"));root<-resolve_v3_root();load_v3_modules(root)
for(dir in c("unequal_integration","fullgrid_synthetic")) {
 out<-file.path(root,"review",dir)
 e<-read.csv(file.path(out,"results","cv_record_predictions.csv"),stringsAsFactors=FALSE)
 write_quantitative_diagnostics_v32(e,file.path(out,"results"),file.path(out,"figures"),test_only=TRUE)
 z<-e[e$Route=="joint_bb"&e$Type%in%c("count","exact"),]
 r<-aggregate(PredictedPoint~Design+Model+TrainWeighting,z,function(x)c(min=min(x),max=max(x),unique=length(unique(x))))
 write.csv(r,file.path(out,"figures","prediction_ranges_for_visual_review.csv"),row.names=FALSE)
}
cat("SYNTHETIC_PLOTS_REGENERATED; source predictions unchanged; square axes; no MCMC
")
