#!/usr/bin/env Rscript
# Draw existing formal metrics only. No model fitting or new uncertainty estimation.
args <- commandArgs(TRUE)
if(length(args)!=2L)stop("Usage: Rscript make_metric_figures.R VERSION_ROOT OUTPUT_DIR")
root<-normalizePath(args[1],mustWork=TRUE);out<-normalizePath(args[2],mustWork=TRUE)
options(warn=1)
files<-file.path(root,"results",c("cv_metrics_summary.csv","model_vs_null.csv","training_method_comparisons.csv"))
hashes_before<-setNames(vapply(files,function(p)digest::digest(file=p,algo="sha256"),character(1)),basename(files))
cv<-read.csv(files[1],stringsAsFactors=FALSE)
z<-cv[cv$Route=="joint_bb",,drop=FALSE]
models<-c("Null","M1","M2","M3");train<-c("record_equal","species_equal");evals<-c("species_equal","record_equal");designs<-c("fivefold","tenfold")
keys<-c("Design","Route","Model","TrainWeighting","EvalWeighting")
key<-function(d)do.call(paste,c(d[keys],sep="|"))
expected<-expand.grid(Design=designs,Route="joint_bb",Model=models,TrainWeighting=train,EvalWeighting=evals,stringsAsFactors=FALSE)
stopifnot(nrow(z)==32L,!anyDuplicated(key(z)),setequal(key(z),key(expected)),all(z$LogScoreRecordsUsed==153),all(z$LogScoreSpeciesUsed==51),all(z$PointRecords==145),all(z$PointSpeciesUsed==48))
stopifnot(all(is.finite(as.matrix(z[,c("ELPD","MAE","RMSE")]))),all(z$MAE>=0&z$MAE<=1),all(z$RMSE>=z$MAE-1e-12),all(abs(z$ELPD-z$MeanLogScore*z$WeightSum)<1e-9))
z$MAE_PercentagePoints<-100*z$MAE;z$RMSE_PercentagePoints<-100*z$RMSE
write.csv(z,file.path(out,"quantitative_metric_source.csv"),row.names=FALSE,na="")
cols<-c(record_equal="#1F629B",species_equal="#B66A1D");pch<-c(record_equal=16,species_equal=18)
font<-"Microsoft YaHei"
metric_titles<-c(ELPD="ELPD：留出预测分布的评分",MAE="MAE：平均绝对预测误差",RMSE="RMSE：更强调大误差的预测指标")
axis_titles<-c(ELPD="ELPD（越大越好）",MAE="MAE（百分点；越小越好）",RMSE="RMSE（百分点；越小越好）")
plot_records<-list()
draw<-function(metric,data=z,route="joint_bb"){
 vals<-data[[metric]]*if(metric=="ELPD")1 else 100
 limits<-if(metric=="ELPD") {rr<-range(vals);rr+c(-.12,.27)*diff(rr)} else c(0,ceiling(max(vals)*1.18/5)*5)
 par(mfrow=c(2,2),oma=c(4.7,0,7.6,0),mar=c(4.7,4.1,3.7,1.8),family=font,cex=1,las=1,bg="white")
 for(design in designs)for(ew in evals){
  d<-data[data$Design==design&data$EvalWeighting==ew,,drop=FALSE];primary<-design=="fivefold"&&ew=="species_equal"
  plot(limits,c(.45,4.55),type="n",xlim=limits,ylim=c(.45,4.55),xaxs="i",yaxs="i",axes=FALSE,ann=FALSE)
  rect(limits[1],.45,limits[2],4.55,col=if(primary)"#F1F6FA" else "#FBFBFB",border=NA)
  ticks<-pretty(limits,n=5);ticks<-ticks[ticks>=limits[1]&ticks<=limits[2]]
  abline(v=ticks,col="#DEE4E9",lwd=.7);abline(h=1:4,col="#EEF0F2",lwd=.7)
  axis(1,at=ticks,tck=-.018,col="#82909D",col.axis="#293743",cex.axis=.88)
  axis(2,at=4:1,labels=models,tick=FALSE,cex.axis=1.12,font=2,col.axis="#293743")
  title(xlab=axis_titles[[metric]],line=2.7,cex.lab=.95,col.lab="#334350")
  title(main=paste0(if(design=="fivefold")"五折 CV" else "十折 CV","  |  ",if(ew=="species_equal")"物种等权评价" else "记录等权评价",if(primary)"  ·  主评价" else ""),line=1.5,cex.main=1.03,col.main=if(primary)"#174C72" else "#334350")
  if(primary)box(col="#A9C4D8",lwd=1.1,bty="l")
  for(i in seq_along(models)){
   q<-d[d$Model==models[i],,drop=FALSE];q<-q[match(train,q$TrainWeighting),,drop=FALSE]
   yy<-c(4.13,3.87)-(i-1);xx<-q[[metric]]*if(metric=="ELPD")1 else 100
   for(j in 1:2){points(xx[j],yy[j],pch=pch[j],col=cols[j],cex=1.2)
    text(xx[j]+diff(limits)*.021,yy[j],sprintf(if(metric=="ELPD")"%.2f" else "%.2f",xx[j]),adj=0,cex=.87,col=cols[j])}
  }
 }
 mtext(if(route=="binary")"ELPD：分类路线的留出评分" else metric_titles[[metric]],side=3,outer=TRUE,line=5.7,cex=1.52,font=2,col="#172F43")
 mtext(paste0(if(route=="binary")"定性路线 binary" else "定量联合路线 joint_bb","；只在同一面板内比较模型与训练方式"),side=3,outer=TRUE,line=4.1,cex=.95,col="#435766")
 par(fig=c(0,1,0,1),new=TRUE,mar=rep(0,4),oma=rep(0,4));plot.new()
 legend("top",inset=c(0,.087),legend=c("记录等权训练","物种等权训练"),col=cols,pch=pch,horiz=TRUE,bty="n",cex=1.02,x.intersp=.8,y.intersp=1.2)
 text(.5,.044,if(route=="binary")"分类评分使用 152 条可判定 HIGH/LOW 的记录 / 50 个物种；不与定量 ELPD 直接比较。" else if(metric=="ELPD")"ELPD 使用 153 条记录 / 51 个物种，包含 count、exact、interval。" else "点误差使用 145 条 count/exact 记录 / 48 个物种；interval 不替换为点值。",cex=.86,col="#435766")
 text(.5,.019,"图示为既有总体点估计；不同评价口径对应不同目标；未新增拟合、区间估计或显著性检验。",cex=.81,col="#65737D")
}
binary<-cv[cv$Route=="binary",,drop=FALSE];exp_binary<-expected;exp_binary$Route<-"binary"
stopifnot(nrow(binary)==32L,!anyDuplicated(key(binary)),setequal(key(binary),key(exp_binary)),all(binary$LogScoreRecordsUsed==152),all(binary$LogScoreSpeciesUsed==50),all(is.finite(binary$ELPD)))
write.csv(binary,file.path(out,"binary_metric_source.csv"),row.names=FALSE,na="")
for(task in c("ELPD","MAE","RMSE","ELPD_binary")){
 metric<-if(task=="ELPD_binary")"ELPD" else task;route<-if(task=="ELPD_binary")"binary" else "joint_bb";data<-if(route=="binary")binary else z
 png(file.path(out,paste0(task,"_comparison.png")),width=13,height=9.6,units="in",res=220,type="cairo",bg="white",family=font)
 draw(metric,data,route);dev.off()
 svg(file.path(out,paste0(task,"_comparison.svg")),width=13,height=9.6,family=font,bg="white")
 draw(metric,data,route);dev.off()
 png(file.path(out,paste0(task,"_preview.png")),width=13,height=9.6,units="in",res=110,type="cairo",bg="white",family=font)
 draw(metric,data,route);dev.off()
 pr<-data[,keys,drop=FALSE];pr$Metric<-metric;pr$RawValue<-data[[metric]];pr$PlotValue<-data[[metric]]*if(metric=="ELPD")1 else 100;pr$PlotUnits<-if(metric=="ELPD")"weighted_log_score_sum" else "percentage_points"
 plot_records[[task]]<-pr
}
source<-do.call(rbind,plot_records);write.csv(source,file.path(out,"plotted_values.csv"),row.names=FALSE,na="")
hashes_after<-setNames(vapply(files,function(p)digest::digest(file=p,algo="sha256"),character(1)),basename(files))
stopifnot(identical(hashes_before,hashes_after),nrow(source)==128L)
jsonlite::write_json(list(status="PASS",purpose="display_existing_formal_metrics_only",source_hashes=as.list(hashes_after),groups_per_route=32,plotted_values=128,figures=4,formats=c("PNG","SVG"),primary_design="fivefold",primary_evaluation="species_equal",plot_font=font,R=as.character(getRversion()),new_fits=0,new_bootstrap=0,new_hypothesis_tests=0,source_outputs_modified=FALSE),file.path(out,"plot_validation.json"),auto_unbox=TRUE,pretty=TRUE)
cat("METRIC_FIGURES_PASS: 3 quantitative metrics plus binary ELPD, 32 groups per plot, 128 plotted values; sources unchanged; no fitting\n")
