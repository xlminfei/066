args<-commandArgs(TRUE);out<-args[1]
r<-read.csv(file.path(out,"supplementary_metric_tests.csv"),stringsAsFactors=FALSE)
z<-r[r$Design=="fivefold"&r$EvalWeighting=="species_equal"&r$Model!="Null",]
orderkey<-as.vector(t(outer(c("M1","M2","M3"),c("record_equal","species_equal"),paste,sep="|")))
font<-"Microsoft YaHei";cols<-c(record_equal="#1F629B",species_equal="#B66A1D")
draw<-function(){
 par(mfrow=c(1,3),oma=c(4.8,0,4.8,0),mar=c(4.7,1.2,2.2,1.2),family=font)
 for(i in seq_along(c("AUC","MAE","RMSE"))){metric<-c("AUC","MAE","RMSE")[i];a<-z[z$Metric==metric,];a<-a[match(orderkey,paste(a$Model,a$TrainWeighting,sep="|")),]
  par(mar=c(4.7,if(i==1)10.6 else 1.0,2.2,1.2));yy<-6:1
  if(metric=="AUC"){x<-a$Estimate;lo<-a$CI95_lower+.5;hi<-a$CI95_upper+.5;ref<-.5;limits<-c(min(.48,min(lo)-.02),min(1,max(hi)+.03));lab<-"AUC（大于0.5表示区分较好）"}
  else{x<-100*a$Difference;lo<-100*a$CI95_lower;hi<-100*a$CI95_upper;ref<-0;rg<-range(c(lo,hi,0));limits<-rg+c(-1,1)*diff(rg)*.10;lab<-paste0(metric," − Null（百分点；负值为改善）")}
  plot(limits,c(.6,6.4),type="n",xlim=limits,ylim=c(.6,6.4),xlab=lab,ylab="",yaxt="n",bty="n",main=metric,cex.main=1.1,cex.lab=.82,cex.axis=.83)
  abline(v=pretty(limits),col="#E6EAEF",lwd=.7);abline(v=ref,col="#657785",lty=2,lwd=1.4)
  for(j in seq_len(nrow(a))){cc<-cols[[a$TrainWeighting[j]]];segments(lo[j],yy[j],hi[j],yy[j],col=cc,lwd=2);points(x[j],yy[j],pch=if(a$TrainWeighting[j]=="record_equal")16 else 18,col=cc,cex=1.15)}
  if(i==1)axis(2,at=yy,labels=paste(a$Model,ifelse(a$TrainWeighting=="record_equal","记录等权训练","物种等权训练")),las=2,tick=FALSE,cex.axis=.85)
 }
 mtext("新增指标检验：五折CV · 物种等权评价",side=3,outer=TRUE,line=2.4,cex=1.25,font=2,col="#173A54")
 mtext("AUC 对0.5；MAE、RMSE 对同训练方式的Null",side=3,outer=TRUE,line=.9,cex=.91,col="#405568")
 mtext("线段为95%物种重抽样百分位区间，未作多重区间校正；P值和BH校正见附表。",side=1,outer=TRUE,line=1.7,cex=.83,col="#405568")
 mtext("固定OOF预测的探索性条件近似；未重新训练，未计入训练重叠与模型选择的全部不确定性。",side=1,outer=TRUE,line=3.1,cex=.78,col="#657785")
}
png(file.path(out,"primary_supplementary_tests.png"),width=15,height=6.2,units="in",res=170,type="cairo",bg="white",family=font);draw();dev.off()
svg(file.path(out,"primary_supplementary_tests.svg"),width=15,height=6.2,bg="white",family=font);draw();dev.off()
cat("SUPPLEMENT_PRIMARY_PLOT_CREATED\n")
