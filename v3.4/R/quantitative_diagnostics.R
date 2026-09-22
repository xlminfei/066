# Section 7.3 only: point-level predicted-vs-observed diagnostic and signed bias.
# No additional type-specific metrics or bootstrap intervals are introduced here.
quantitative_diagnostics_v32 <- function(evidence) {
  required<-c("Design","Fold","Route","Model","TrainWeighting","RecordID","Species","Type","ObservedPoint","PredictedPoint")
  if(!all(required%in%names(evidence)))stop("Quantitative diagnostic evidence lacks required fields")
  joint<-evidence[evidence$Route=="joint_bb",,drop=FALSE]
  if(!nrow(joint))stop("No quantitative OOF evidence")
  if(any(!joint$Type%in%c("count","exact","interval")))stop("Invalid quantitative observation type")
  key_cols<-c("Design","Route","Model","TrainWeighting","RecordID")
  if(anyNA(joint[,key_cols])||anyDuplicated(joint[,key_cols]))stop("Invalid or duplicated quantitative OOF keys")
  point<-joint$Type%in%c("count","exact")
  if(any(!is.finite(joint$ObservedPoint[point]))||any(!is.finite(joint$PredictedPoint[point])))stop("Missing/nonfinite point-level quantitative evidence")
  if(any(joint$ObservedPoint[point]<0|joint$ObservedPoint[point]>1|joint$PredictedPoint[point]<0|joint$PredictedPoint[point]>1))stop("Point proportion outside [0,1]")
  group_cols<-c("Design","Route","Model","TrainWeighting")
  keys<-unique(joint[,group_cols,drop=FALSE]);sources<-list();summaries<-list()
  for(i in seq_len(nrow(keys))) {
    q<-joint
    for(n in group_cols)q<-q[q[[n]]==keys[[n]][i],,drop=FALSE]
    z<-q[q$Type%in%c("count","exact"),,drop=FALSE]
    for(ew in V3_EVAL_WEIGHTINGS) {
      weights<-if(nrow(z))build_eval_weights(z[,"Species",drop=FALSE],ew)$weight else numeric()
      if(nrow(z)) {
        source<-z[,required,drop=FALSE];source$EvalWeighting<-ew;source$EvaluationWeight<-weights
        source$SignedError<-z$PredictedPoint-z$ObservedPoint
        if("FitKey"%in%names(z))source$FitKey<-z$FitKey
        if("RunPurpose"%in%names(z))source$RunPurpose<-z$RunPurpose
        sources[[length(sources)+1L]]<-source
      }
      summaries[[length(summaries)+1L]]<-cbind(keys[i,,drop=FALSE],data.frame(EvalWeighting=ew,
        LogScoreRecordsUsed=nrow(q),LogScoreSpeciesUsed=length(unique(q$Species)),
        PointRecords=nrow(z),PointSpeciesUsed=length(unique(z$Species)),PISpeciesUsed=length(unique(z$Species)),
        Bias=if(nrow(z))weighted_bias(z$ObservedPoint,z$PredictedPoint,weights) else NA_real_,
        BiasDefinition="weighted_mean(predicted_minus_observed)",PointSet="count_and_exact; interval_not_imputed",stringsAsFactors=FALSE))
    }
  }
  source<-if(length(sources))do.call(rbind,sources) else data.frame()
  summary<-do.call(rbind,summaries);rownames(source)<-rownames(summary)<-NULL
  list(plot_source=source,summary=summary)
}
plot_quantitative_diagnostics_v32 <- function(source,summary,output_path,test_only=FALSE) {
  if(!nrow(source))stop("No count/exact point records to plot")
  if("RunPurpose"%in%names(source)&&any(source$RunPurpose!="formal"))test_only<-TRUE
  dir.create(dirname(output_path),recursive=TRUE,showWarnings=FALSE)
  pdf(output_path,width=11,height=9,onefile=TRUE);on.exit(dev.off(),add=TRUE)
  pages<-unique(summary[,c("Design","TrainWeighting","EvalWeighting"),drop=FALSE])
  for(i in seq_len(nrow(pages))) {
    par(mfrow=c(2,2),pty="s",mar=c(4,4,3,1),oma=c(3,0,if(test_only)3 else 1,0))
    for(m in V3_MODELS) {
      z<-source[source$Design==pages$Design[i]&source$TrainWeighting==pages$TrainWeighting[i]&source$EvalWeighting==pages$EvalWeighting[i]&source$Model==m,,drop=FALSE]
      s<-summary[summary$Design==pages$Design[i]&summary$TrainWeighting==pages$TrainWeighting[i]&summary$EvalWeighting==pages$EvalWeighting[i]&summary$Model==m,,drop=FALSE]
      plot(0:1,0:1,type="n",xlab="Observed report proportion",ylab="OOF predicted expected proportion",main=m,asp=1)
      abline(0,1,lty=2,col="grey50")
      if(nrow(z)) {
        size<-.65*sqrt(z$EvaluationWeight/mean(z$EvaluationWeight))
        points(z$ObservedPoint,z$PredictedPoint,pch=ifelse(z$Type=="count",16,17),col=grDevices::adjustcolor("#1f5e9a",.55),cex=size)
        if(nrow(s)!=1)stop("Ambiguous plot summary key")
        legend("topleft",legend=c(sprintf("Bias = %+.4f",s$Bias),sprintf("%d point records / %d species",s$PointRecords,s$PointSpeciesUsed)),bty="n",cex=.8)
      }else text(.5,.5,"No point records for this model")
    }
    mtext(paste(unlist(pages[i,]),collapse=" | "),side=1,outer=TRUE,line=0,cex=.9)
    mtext("Count: circles; exact: triangles; interval excluded. Point area reflects evaluation weight; dashed line y = x.",side=1,outer=TRUE,line=1.2,cex=.72)
    if(test_only)mtext("SYNTHETIC TEST DATA - NOT RESEARCH RESULTS",side=3,outer=TRUE,line=1,font=2,col="#b3261e",cex=1.05)
  }
  invisible(output_path)
}
write_quantitative_diagnostics_v32 <- function(evidence,result_dir,figure_dir=NULL,test_only=FALSE) {
  d<-quantitative_diagnostics_v32(evidence)
  write_csv_atomic(d$plot_source,file.path(result_dir,"quantitative_plot_source.csv"))
  write_csv_atomic(d$summary,file.path(result_dir,"quantitative_bias_summary.csv"))
  if(!is.null(figure_dir))plot_quantitative_diagnostics_v32(d$plot_source,d$summary,file.path(figure_dir,"quantitative_predicted_observed.pdf"),test_only)
  invisible(d)
}
