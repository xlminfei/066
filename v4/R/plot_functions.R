# Reused plotting definitions preserve fold-mean ROC and prediction targets.
roc_area <- function(x,y) sum(diff(x)*(head(y,-1)+tail(y,-1))/2)
mean_roc_summary <- function(q) {
  if(any(!is.finite(q$FPR))||any(q$FPR< -1e-12|q$FPR>1+1e-12))stop("Invalid ROC coordinates")
  q$FPR[abs(q$FPR)<1e-12]<-0;q$FPR[abs(q$FPR-1)<1e-12]<-1
  folds<-split(q,q$Fold);grid<-sort(unique(q$FPR));auc<-numeric();curves<-list()
  for(k in names(folds)) {
    r<-folds[[k]];r<-r[order(r$FPR,r$TPR),];a<-unique(r$AUC)
    if(length(a)!=1||!is.finite(a))stop("Inconsistent fold AUC")
    auc<-c(auc,a);knots<-sort(unique(r$FPR))
    lo<-vapply(knots,function(t)min(r$TPR[r$FPR==t]),numeric(1));hi<-vapply(knots,function(t)max(r$TPR[r$FPR==t]),numeric(1))
    curves[[k]]<-unlist(lapply(grid,function(t) {
      j<-match(t,knots);if(!is.na(j))return(c(lo[j],hi[j]))
      j<-findInterval(t,knots);v<-hi[j]+(lo[j+1]-hi[j])*(t-knots[j])/(knots[j+1]-knots[j]);c(v,v)
    }))
  }
  list(x=rep(grid,each=2),y=rowMeans(do.call(cbind,curves)),auc=mean(auc),folds=length(folds))
}
plot_roc_base <- function(roc_data,output_path) {
  if(!nrow(roc_data))stop("Empty ROC")
  dir.create(dirname(output_path),showWarnings=FALSE,recursive=TRUE);pdf(output_path,width=9,height=7);on.exit(dev.off(),add=TRUE)
  keys<-unique(roc_data[,c("Design","EvalWeighting","TrainWeighting")]);cols<-setNames(hcl.colors(4,"Dark 3"),MODELS)
  for(i in seq_len(nrow(keys))) {
    z<-roc_data
    for(n in names(keys))z<-z[z[[n]]==keys[[n]][i],]
    plot(0:1,0:1,type="n",xlab="FPR",ylab="TPR",main=paste(unlist(keys[i,]),collapse=" | "));abline(0,1,col="grey70",lty=2)
    labels<-character();used<-intersect(MODELS,unique(z$Model))
    for(m in used) {
      q<-z[z$Model==m,];s<-mean_roc_summary(q)
      for(f in unique(q$Fold)){r<-q[q$Fold==f,];lines(r$FPR,r$TPR,col=adjustcolor(cols[[m]],.25),lty=3)}
      lines(s$x,s$y,col=cols[[m]],lwd=2);labels<-c(labels,sprintf("%s | Mean CV AUC %.3f (%d folds)",m,s$auc,s$folds))
    }
    legend("bottomright",labels,col=cols[used],lwd=2,bty="n",cex=.85)
  };invisible(output_path)
}
plot_calibration_base <- function(calibration, output_path) {
  if (!nrow(calibration)) stop("Calibration table is empty")
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(output_path, width = 8, height = 6, onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)
  keys <- unique(calibration[, c("Design", "EvalWeighting", "TrainWeighting")])
  cols <- setNames(grDevices::hcl.colors(length(MODELS), "Dark 3"), MODELS)
  pchs <- setNames(seq_len(length(MODELS)) + 15L, MODELS)
  for (i in seq_len(nrow(keys))) {
    z <- calibration[calibration$Design == keys$Design[[i]] & calibration$EvalWeighting == keys$EvalWeighting[[i]] &
                       calibration$TrainWeighting == keys$TrainWeighting[[i]], , drop = FALSE]
    plot(c(0, 1), c(0, 1), type = "n", xlab = "Mean predicted HIGH probability",
         ylab = "Observed HIGH rate", main = paste(keys$Design[[i]], keys$EvalWeighting[[i]], keys$TrainWeighting[[i]], sep = " | "))
    abline(0, 1, col = "grey70", lty = 2)
    models <- intersect(MODELS, unique(z$Model))
    for (model in models) {
      q <- z[z$Model == model, , drop = FALSE]
      points(q$MeanPredicted, q$ObservedRate, col = cols[[model]], pch = pchs[[model]], type = "b")
      segments(q$MeanPredicted, q$CalibrationLower, q$MeanPredicted, q$CalibrationUpper, col = cols[[model]])
    }
    legend("topleft", legend = models, col = cols[models], pch = pchs[models], lty = 1, bty = "n")
  }
  invisible(output_path)
}

plot_species_predictions_base <- function(predictions,output_dir,page_size=42L) {
  validate_prediction_table(predictions);dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  ss<-unique(predictions$Species);pages<-split(ss,ceiling(seq_along(ss)/page_size));sources<-list()
  is_fixture<-"FixtureOnly"%in%names(predictions) && isTRUE(any(predictions$FixtureOnly,na.rm=TRUE))
  cols<-setNames(hcl.colors(4,"Dark 3"),MODELS)
  for(route in unique(predictions$Route))for(tw in unique(predictions$TrainWeighting)) {
    pdf(file.path(output_dir,paste0("species_predictions_",route,"_",tw,".pdf")),width=16,height=12)
    for(pg in seq_along(pages)) {
      sp<-pages[[pg]];par(mfrow=c(1,4),oma=c(2,0,if(is_fixture)3 else 0,0))
      for(m in MODELS) {
        z<-predictions[predictions$Route==route&predictions$TrainWeighting==tw&predictions$Model==m,,drop=FALSE];z<-z[match(sp,z$Species),]
        if(anyNA(z$Species))stop("Missing plotted species/model")
        par(mar=c(4,if(m=="Null")13 else 1,4,1));yy<-rev(seq_along(sp))
        plot(c(0,1),c(.5,length(sp)+.5),type="n",yaxt="n",xlab=if(route=="binary")"Pr(HIGH)" else "Ratio",ylab="",main=paste(m,route,tw,sep="\n"))
        if(m=="Null")axis(2,yy,gsub("_"," ",sp),las=2,cex.axis=.65)
        if(route=="joint_bb")segments(z$PI_lower,yy,z$PI_upper,yy,col=adjustcolor(cols[m],.28),lwd=3)
        segments(z$CrI_lower,yy,z$CrI_upper,yy,col=cols[m],lwd=2);points(z$Point,yy,pch=19,col=cols[m],cex=.6)
        warn<-!is.na(z$WarningCodes)&nzchar(z$WarningCodes);points(rep(.99,sum(warn)),yy[warn],pch=4,col="#aa4411",cex=.6)
        z$Page<-pg;z$YPosition<-yy;sources[[length(sources)+1]]<-z
      }
      note<-if(route=="joint_bb")"Point: posterior mean | dark: 95% CrI | pale: future-report 95% PI | x: applicability warning" else "Point: posterior Pr(HIGH) | line: 95% CrI | x: applicability warning"
      if(is_fixture) {
        note<-"SYNTHETIC: dummy points and intervals for layout only | x: dummy warning | no fitted species results"
        mtext("SYNTHETIC TEST DATA - NOT RESEARCH RESULTS",side=3,outer=TRUE,line=1,font=2,col="#b3261e",cex=1.05)
      }
      mtext(note,side=1,outer=TRUE,line=0,cex=.65)
    };dev.off()
  }
  write_csv_atomic(do.call(rbind,sources),file.path(output_dir,"species_prediction_plot_source.csv"));invisible(output_dir)
}

plot_quantitative_diagnostics <- function(source,summary,output_path,test_only=FALSE) {
  if(!nrow(source))stop("No count/exact point records to plot")
  if("RunPurpose"%in%names(source)&&any(source$RunPurpose!="formal"))test_only<-TRUE
  dir.create(dirname(output_path),recursive=TRUE,showWarnings=FALSE)
  pdf(output_path,width=11,height=9,onefile=TRUE);on.exit(dev.off(),add=TRUE)
  pages<-unique(summary[,c("Design","TrainWeighting","EvalWeighting"),drop=FALSE])
  for(i in seq_len(nrow(pages))) {
    par(mfrow=c(2,2),pty="s",mar=c(4,4,3,1),oma=c(3,0,if(test_only)3 else 1,0))
    for(m in MODELS) {
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
