# Stage 4: compact publication plots; tables retain all model identities.
plot_cv_metrics <- function(metrics,path) {
  pdf(path,width=10,height=7);on.exit(dev.off(),add=TRUE)
  cols<-setNames(hcl.colors(4,"Dark 3"),MODELS)
  for(d in names(DESIGNS))for(r in ROUTES) {
    z<-metrics[metrics$Design==d&metrics$Route==r,];z<-z[match(MODELS,z$Model),]
    fields<-if(r=="binary")c("AUC","ELPD","Brier") else c("ELPD","MAE","RMSE","Bias","PICoverage","MeanPIWidth")
    par(mfrow=c(2,3),mar=c(4,4,3,1),oma=c(2,0,2,0))
    for(metric in fields) {
      y<-z[[metric]];limits<-range(c(y,if(metric=="Bias")0 else NULL),finite=TRUE)
      pad<-max(diff(limits)*.15,.01);limits<-limits+c(-pad,pad)
      plot(seq_along(MODELS),y,xaxt="n",pch=19,col=cols,ylim=limits,xlab="",ylab=metric,main=metric)
      axis(1,seq_along(MODELS),MODELS);text(seq_along(MODELS),y,formatC(y,digits=3,format="f"),pos=3,cex=.8)
      if(metric=="AUC")abline(h=.5,lty=2,col="grey60")
      if(metric=="Bias")abline(h=0,lty=2,col="grey60")
    }
    if(length(fields)<6)for(i in seq_len(6-length(fields)))plot.new()
    mtext(paste(d,r,"record-equal training / species-equal evaluation"),side=3,outer=TRUE,line=.3)
    mtext("OOF point estimates; each CV design run once. Error metrics are in proportion units.",side=1,outer=TRUE,line=.3,cex=.8)
  }
}
plot_hypothesis_tests <- function(tests,path) {
  pdf(path,width=12,height=8);on.exit(dev.off(),add=TRUE)
  groups<-unique(tests[,c("Route","Metric")])
  for(d in names(DESIGNS)) {
    par(mfrow=c(2,3),mar=c(5,4,3,1),oma=c(4,0,2,0))
    for(i in seq_len(nrow(groups))) {
      z<-tests[tests$Design==d&tests$Route==groups$Route[i]&tests$Metric==groups$Metric[i],]
      z<-z[match(c("M1","M2","M3"),z$Model),];yy<-3:1
      limits<-range(c(0,z$Difference,z$CI95_lower,z$CI95_upper),finite=TRUE)
      pad<-max(diff(limits)*.1,.001);limits<-limits+c(-pad,pad)
      plot(limits,c(.5,3.5),type="n",xlim=limits,ylim=c(.5,3.5),yaxt="n",ylab="",xlab="Difference from reference",
           main=paste(groups$Route[i],groups$Metric[i]))
      axis(2,yy,z$Model,las=2);abline(v=0,lty=2,col="grey60")
      segments(z$CI95_lower,yy,z$CI95_upper,yy,col="#225E91",lwd=2)
      points(z$Difference,yy,pch=19,col="#225E91")
      for(j in seq_len(nrow(z)))text(limits[2],yy[j]-.22,
        sprintf("P=%s; BH3=%s",format(z$P_approx[j],digits=3),format(z$P_BH3[j],digits=3)),adj=1,cex=.65)
    }
    plot.new();text(.5,.65,"References: AUC 0.5; other metrics Null",cex=.85)
    text(.5,.45,"MeanLogScore: positive favors the model\nMAE/RMSE: negative favors the model",cex=.85)
    mtext(paste(d,"| ten separate BH families, three models in each"),side=3,outer=TRUE,line=.3)
    mtext("Fixed-OOF conditional approximations. Intervals are unadjusted 95% bootstrap percentiles.",side=1,outer=TRUE,line=1,cex=.8)
    mtext("BH3 does not account for all earlier development/selection. Do not infer usefulness from P alone.",side=1,outer=TRUE,line=2.3,cex=.75)
  }
}
plot_stage <- function(state,output_dir) {
  read<-function(n)read.csv(file.path(output_dir,n),stringsAsFactors=FALSE)
  dir.create(file.path(output_dir,"figures"),showWarnings=FALSE)
  p<-function(n)file.path(output_dir,"figures",n)
  plot_roc_base(read("roc_coordinates.csv"),p("ROC_curves.pdf"))
  plot_calibration_base(read("calibration_bins.csv"),p("calibration.pdf"))
  plot_cv_metrics(read("cv_metrics_summary.csv"),p("cv_metrics.pdf"))
  plot_hypothesis_tests(read("hypothesis_tests.csv"),p("hypothesis_tests.pdf"))
  plot_quantitative_diagnostics(read("quantitative_plot_source.csv"),read("quantitative_bias_summary.csv"),
                                p("quantitative_predicted_observed.pdf"))
  plot_species_predictions_base(read("full_panel_predictions.csv"),file.path(output_dir,"figures"))
  files<-list.files(file.path(output_dir,"figures"),full.names=TRUE)
  if(!length(files)||any(file.info(files)$size<=0))stop("Missing/empty plots")
  stage_receipt("plot",state,output_dir,file.path("figures",basename(files)))
  invisible(files)
}
if(sys.nframe()==0L) {
  script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
  source(file.path(dirname(normalizePath(script)),"R/load.R"));run_stage_cli("plot")
}
