**06A：在High/Low路线中加入ROC与交叉验证AUC。**

本页接在06之后，使用同一批物种、同一份折分配和已经完成的分类留出拟合。它只增加评分与ROC输出，不改变已有模型、ELPD的参照方式或07的期望比率结果。

如果当前R会话已经完成binary路线的06，可直接从下面开始。重新打开R时，按00恢复原运行，执行05的binary读取块，再按原来的`CV_TYPE`、`CV_K`和`CV_SEED`执行06的折分配块，以定位同一个`CV_DIR`。只做这些读取和准备步骤不会重新训练模型。当前设计的十个分类CV模型需已完成；缺少时，本页会指出缺少的结果。

每次按当前规则可以分类的实验仍是一个评分对象。同一物种的多次实验使用该物种被留出时得到的High概率，既有High又有Low的物种不被强行变成单一标签。v3中40–50%已归Low，会进入ROC；只有Lower<0.5且Upper>0.5的严格跨越区间不进入ROC。所有原始区间的定量信息仍由03使用。

v3的分类标签已改变，需使用v3重新准备并拟合的分类CV结果；不能直接沿用旧版AUC。ROC计算公式本身没有变化。

主指标`CV_AUC`是**先在每一折内计算AUC，再对所有折的AUC取算术平均**。这是标准的折平均交叉验证AUC定义，见[cvAUC原作者文档](https://cran.r-project.org/web/packages/cvAUC/cvAUC.pdf)。不同折使用不同拟合，概率水平可能有偏移，因此本页不把跨折拼接后的单个AUC当成主指标。所有折必须同时含High和Low，才给出完整的CV_AUC；不会删除单类别折后只平均其余折。

本页使用现成的[pROC](https://xrobin.github.io/pROC/)计算每折ROC和AUC。预测分数越高表示越倾向High，方向固定；AUC低于0.5时也不会自动反转。相同分数按标准AUC规则处理。

<!-- R_BLOCK:06A_SETUP -->
```r
if(!exists("OUTCOME") || OUTCOME!="binary")stop("请先在05选择binary并读取模型。")
if(!exists("CV_DIR") || !file.exists(file.path(CV_DIR,"cv_index.csv")))stop("请先定位并完成binary路线的06留出结果。")
if(!requireNamespace("pROC",quietly=TRUE))stop("缺少pROC；执行下面的安装块后，重新执行本块。")
if(utils::packageVersion("pROC") < "1.18.0")stop("请使用pROC 1.18.0或更新版本。")
AUC_VERSION <- "binary_roc_console_v2.0"
auc_models <- prepared$model_grid$Model
auc_folds <- sort(unique(as.integer(fold_table$Fold)))
if(length(auc_folds)<2L)stop("交叉验证AUC至少需要两折。")
cat("使用pROC",as.character(utils::packageVersion("pROC")),"；模型数",length(auc_models),"；折数",length(auc_folds),"\n")
```

仅在缺少pROC时执行这一块，然后回到上面的检查。它是后处理依赖，没有加入原拟合缓存的包版本清单，因此不会仅因增加AUC而要求重跑02或03。

<!-- R_BLOCK:06A_INSTALL -->
```r
utils::install.packages("pROC",repos="https://cloud.r-project.org")
```

下面核对已有CV与当前输入、模型和折分配是否一致，再从每折拟合重新读取**留出物种的概率**。预测时设`Trials=1`，直接取得概率，避免“预测次数除以次数”产生的微小舍入差异把本来相同的分数变成虚假的排序。这只是后处理，不重新抽样或训练。

<!-- R_BLOCK:06A_LOAD -->
```r
if(!setequal(names(bundles),auc_models))stop("请先在05读取当前版本的十个binary模型。")
auc_index<-utils::read.csv(file.path(CV_DIR,"cv_index.csv"),stringsAsFactors=FALSE)
auc_index<-auc_index[!duplicated(auc_index$Model,fromLast=TRUE),,drop=FALSE]
if(!setequal(auc_index$Model,auc_models))stop("十个分类CV模型尚未齐全。")
known_records<-prepared$observations[!is.na(prepared$observations$High),
  c("RecordID","ExperimentID","SourceID","Species","High"),drop=FALSE]
if(!nrow(known_records) || anyDuplicated(known_records$RecordID))stop("可分类实验明细无效。")
if(anyDuplicated(known_records$ExperimentID))stop("独立实验编号重复。")
roc_rows<-list();auc_receipts<-list()
for(model in auc_models) {
  parent<-bundles[[model]]
  receipt<-auc_index[auc_index$Model==model,,drop=FALSE]
  cv_path<-file.path(CV_DIR,receipt$File)
  cv<-readRDS(cv_path)
  if(!identical(cv$key,receipt$Key) || !identical(digest::digest(cv$request,algo="sha256"),cv$key))stop("CV请求身份不一致。")
  if(cv$outcome!="binary" || cv$model!=model || !identical(cv$parent_key,parent$key))stop("CV与当前选中的分类模型不一致。")
  if(!identical(cv$request$fold_key,fold_key) || !identical(cv$request$folds,fold_table))stop("模型混用了不同折分配。")
  if(cv$status!="PASS" || any(cv$diagnostics$Status!="PASS"))stop("某个CV拟合未通过06诊断。")
  if(!identical(cv$source,parent$request$training))stop("CV响应与原分类拟合不一致。")
  current_map<-prepared$observations[,c("RecordID","ExperimentID","Species","High","BinaryReason"),drop=FALSE]
  if(!identical(parent$request$source_map,current_map))stop("实验分类明细与拟合时不同。")
  if(!setequal(cv$source$Species,unique(known_records$Species)))stop("分类实验物种集合不同。")
  counts_now<-table(factor(known_records$Species,levels=cv$source$Species),factor(known_records$High,levels=c(0L,1L)))
  if(any(counts_now[,1]!=cv$source$LowCount) || any(counts_now[,2]!=cv$source$HighCount))stop("实验明细无法还原High/Low次数。")
  preds<-cv$predictions
  if(anyDuplicated(preds$Species) || !setequal(preds$Species,cv$source$Species))stop("留出物种预测缺失或重复。")
  expected_fold<-fold_table$Fold[match(preds$Species,fold_table$Species)]
  if(anyNA(expected_fold) || any(preds$Fold!=expected_fold))stop("预测行与指定折不一致。")
  direct_scores<-numeric(nrow(cv$source))
  all_held<-as.integer(unlist(cv$heldout_rows,use.names=FALSE))
  if(anyDuplicated(all_held) || !setequal(all_held,seq_len(nrow(cv$source))))stop("留出记录未恰好覆盖一次。")
  for(k in auc_folds) {
    held<-cv$heldout_rows[[k]]
    test_species<-cv$source$Species[held]
    if(!setequal(test_species,fold_table$Species[fold_table$Fold==k]))stop("实际留出物种与折分配不同。")
    ff<-cv$fold_fits[[k]]
    if(any(as.character(ff$data$Species) %in% test_species))stop("测试物种结果出现在训练侧。")
    if(parent$request$spec$Phylo &&
       (!identical(levels(ff$data$Species),parent$species) || !isTRUE(all.equal(ff$data2$A,parent$request$A,tolerance=0))))stop("留出拟合的物种水平或树矩阵改变。")
    si<-match(test_species,parent$species)
    nd<-cbind(data.frame(Species=factor(test_species,levels=parent$species),Trials=1L),
      as.data.frame(parent$blueprint$X[si,,drop=FALSE]))
    probability_draws<-brms::posterior_epred(ff,newdata=nd,re_formula=NULL,allow_new_levels=FALSE)
    if(ncol(probability_draws)!=length(held) || any(!is.finite(probability_draws)) ||
       any(probability_draws<0 | probability_draws>1))stop("留出概率维度或数值无效。")
    direct_scores[held]<-apply(probability_draws,2L,stats::median)
  }
  old_scores<-preds$PosteriorMedian[match(cv$source$Species,preds$Species)]
  if(any(!is.finite(old_scores)) || max(abs(direct_scores-old_scores))>1e-10)stop("直接概率与已保存的06预测不一致，请先核查。")
  r<-known_records
  source_pos<-match(r$Species,cv$source$Species)
  pred_pos<-match(r$Species,preds$Species)
  r$Model<-model;r$Fold<-as.integer(preds$Fold[pred_pos])
  r$OOFPrHigh<-direct_scores[source_pos]
  r$LevelSeenInTraining<-preds$LevelSeenInTraining[pred_pos]
  r$FixedEffectEstimable<-preds$FixedEffectEstimable[pred_pos]
  roc_rows[[model]]<-r
  auc_receipts[[model]]<-data.frame(Model=model,ParentKey=parent$key,CVKey=cv$key,
    CVFileSHA256=digest::digest(file=cv_path,algo="sha256"),stringsAsFactors=FALSE)
}
roc_data<-do.call(rbind,roc_rows);rownames(roc_data)<-NULL
auc_receipts<-do.call(rbind,auc_receipts);rownames(auc_receipts)<-NULL
cat("每个模型的可分类实验数:",nrow(known_records),"；跨阈值等无法分类记录数:",sum(is.na(prepared$observations$High)),"\n")
```

接着计算每折AUC及坐标。未见过的水平和不可估方向保留预测与标记，不因为它们难预测而删除。相同模型在一折内的所有可分类实验都进入评价。

<!-- R_BLOCK:06A_METRICS -->
```r
required_roc_columns<-c("Model","RecordID","Species","High","OOFPrHigh","Fold","LevelSeenInTraining","FixedEffectEstimable")
if(!all(required_roc_columns %in% names(roc_data)))stop("ROC输入缺少规定列。")
if(!setequal(unique(roc_data$Model),auc_models) || !length(auc_models))stop("ROC模型清单不一致。")
if(anyNA(roc_data[,required_roc_columns]) || any(!is.finite(roc_data$OOFPrHigh)) ||
   any(roc_data$OOFPrHigh<0 | roc_data$OOFPrHigh>1) || any(!roc_data$High %in% c(0L,1L)))stop("ROC分数或真实标签无效；不会补值或静默删行。")
if(anyDuplicated(paste(roc_data$Model,roc_data$RecordID,sep="|")))stop("同一模型的实验预测重复。")
fold_rows<-list();coordinate_rows<-list();summary_rows<-list();roc_objects<-list()
reference_records<-NULL
for(model in auc_models) {
  rows<-roc_data[roc_data$Model==model,,drop=FALSE]
  if(!setequal(unique(rows$Fold),auc_folds))stop("有模型缺少规定测试折。")
  species_fold_counts<-tapply(rows$Fold,rows$Species,unique)
  if(any(lengths(species_fold_counts)!=1L))stop("同一物种跨越了多个测试折。")
  identity<-rows[order(rows$RecordID),c("RecordID","Species","High","Fold"),drop=FALSE];rownames(identity)<-NULL
  if(is.null(reference_records))reference_records<-identity
  if(!identical(identity,reference_records))stop("各模型不是在相同实验和折分配上计算AUC。")
  model_fold_auc<-rep(NA_real_,length(auc_folds))
  for(fi in seq_along(auc_folds)) {
    k<-auc_folds[fi];part<-rows[rows$Fold==k,,drop=FALSE]
    n_high<-sum(part$High==1L);n_low<-sum(part$High==0L)
    status<-if(n_high>0 && n_low>0)"DEFINED"else"NOT_DEFINED_ONE_CLASS"
    if(status=="DEFINED") {
      ro<-pROC::roc(response=part$High,predictor=part$OOFPrHigh,levels=c(0L,1L),
        direction="<",quiet=TRUE,na.rm=FALSE,percent=FALSE,auc=TRUE)
      model_fold_auc[fi]<-as.numeric(pROC::auc(ro))
      roc_objects[[paste(model,k,sep="|")]]<-ro
      co<-pROC::coords(ro,x="all",ret=c("threshold","specificity","sensitivity"),transpose=FALSE)
      coordinate_rows[[paste(model,k,sep="|")]]<-data.frame(Model=model,Fold=k,Threshold=co$threshold,
        FPR=1-co$specificity,TPR=co$sensitivity,stringsAsFactors=FALSE)
    }
    fold_rows[[paste(model,k,sep="|")]]<-data.frame(Model=model,Fold=k,Species=length(unique(part$Species)),
      Records=nrow(part),High=n_high,Low=n_low,AUC=model_fold_auc[fi],Status=status,stringsAsFactors=FALSE)
  }
  all_defined<-all(is.finite(model_fold_auc))
  summary_rows[[model]]<-data.frame(Model=model,Species=length(unique(rows$Species)),Records=nrow(rows),
    High=sum(rows$High==1L),Low=sum(rows$High==0L),Folds=length(auc_folds),ValidFolds=sum(is.finite(model_fold_auc)),
    CV_AUC=if(all_defined)mean(model_fold_auc)else NA_real_,
    FoldAUC_Min=if(all_defined)min(model_fold_auc)else NA_real_,
    FoldAUC_Max=if(all_defined)max(model_fold_auc)else NA_real_,
    UnseenLevelRecords=sum(!rows$LevelSeenInTraining),NonestimableRecords=sum(!rows$FixedEffectEstimable),
    Status=if(all_defined)"DEFINED"else"NOT_DEFINED_ONE_CLASS_FOLD",stringsAsFactors=FALSE)
}
auc_by_fold<-do.call(rbind,fold_rows);rownames(auc_by_fold)<-NULL
auc_summary<-do.call(rbind,summary_rows);rownames(auc_summary)<-NULL
roc_coordinates<-if(length(coordinate_rows))do.call(rbind,coordinate_rows)else
  data.frame(Model=character(),Fold=integer(),Threshold=numeric(),FPR=numeric(),TPR=numeric())
rownames(roc_coordinates)<-NULL
print(auc_summary)
```

`DEFINED`只表示数学上能够计算AUC，不表示预测优秀。`FoldAUC_Min/Max`是各折结果的范围，**不是95%置信区间**。本页不把同物种的多次实验误当作独立物种，套用默认DeLong区间；也不从少量折的波动编造一个精确的总体置信区间。若以后需要AUC差异的正式推断，还需结合物种间亲缘相关性和整个交叉验证过程制定不确定性评估。

下面保存用于你自行作图与核查的原始评分表、逐折ROC坐标和汇总。阈值中的`Inf/-Inf`代表ROC的两个端点，不是输入数据错误。结果目录带输入与评分身份的哈希；只有后处理输出写入新子目录。

<!-- R_BLOCK:06A_SAVE -->
```r
auc_request<-list(version=AUC_VERSION,variant=VARIANT,fold_key=fold_key,folds=fold_table,
  source_hashes=prepared$input_hashes,receipts=auc_receipts,score_summary="posterior_median_probability_with_Trials_1",
  primary_metric="unweighted_mean_of_all_fold_AUCs",direction="higher_score_is_High",data=roc_data,
  packages=c(pROC=as.character(utils::packageVersion("pROC")),brms=as.character(utils::packageVersion("brms"))),
  R=R.version.string)
auc_key<-digest::digest(auc_request,algo="sha256")
AUC_DIR<-file.path(RUN_DIR,"results","roc_auc_v2",paste0(VARIANT,"_",substr(auc_key,1,16)))
dir.create(AUC_DIR,recursive=TRUE,showWarnings=FALSE)
utils::write.csv(roc_data,file.path(AUC_DIR,"roc_oof_experiments.csv"),row.names=FALSE,na="")
utils::write.csv(auc_by_fold,file.path(AUC_DIR,"auc_by_fold.csv"),row.names=FALSE,na="")
utils::write.csv(auc_summary,file.path(AUC_DIR,"auc_summary.csv"),row.names=FALSE,na="")
utils::write.csv(roc_coordinates,file.path(AUC_DIR,"roc_coordinates_by_fold.csv"),row.names=FALSE,na="")
utils::write.csv(auc_receipts,file.path(AUC_DIR,"auc_source_receipts.csv"),row.names=FALSE)
saveRDS(list(key=auc_key,request=auc_request,summary=auc_summary,by_fold=auc_by_fold,
  coordinates=roc_coordinates,rocs=roc_objects),file.path(AUC_DIR,"roc_auc_results.rds"))
cat("ROC/AUC结果目录:",AUC_DIR,"\n")
```

如需ROC图，执行下面这一块。每个模型单独一页，同一页上展示该模型各折的ROC，图中列出每折AUC，并在标题中标出折平均CV_AUC。它没有把跨折分数拼接成一条曲线，也没有把不同折的后验当作同一次联合后验。其它三类图不在这次新增内容中。

<!-- R_BLOCK:06A_PLOT -->
```r
roc_pdf<-file.path(AUC_DIR,"roc_by_model_and_fold.pdf")
grDevices::pdf(roc_pdf,width=7,height=7,onefile=TRUE)
fold_colors<-grDevices::hcl.colors(length(auc_folds),palette="Dark 3")
for(model in auc_models) {
  row<-auc_summary[auc_summary$Model==model,,drop=FALSE]
  caption<-if(is.finite(row$CV_AUC))sprintf("%s | mean fold AUC = %.3f",model,row$CV_AUC)else paste(model,"| mean fold AUC not defined")
  graphics::plot(NA_real_,NA_real_,xlim=c(0,1),ylim=c(0,1),xaxs="i",yaxs="i",asp=1,
    xlab="False positive rate",ylab="True positive rate",main=caption)
  graphics::abline(a=0,b=1,col="grey60",lty=2)
  labels<-character(length(auc_folds))
  for(fi in seq_along(auc_folds)) {
    k<-auc_folds[fi];co<-roc_coordinates[roc_coordinates$Model==model & roc_coordinates$Fold==k,,drop=FALSE]
    af<-auc_by_fold[auc_by_fold$Model==model & auc_by_fold$Fold==k,,drop=FALSE]
    if(nrow(co))graphics::lines(co$FPR,co$TPR,col=fold_colors[fi],lwd=2,lty=1+(fi-1)%%6)
    labels[fi]<-if(is.finite(af$AUC))sprintf("Fold %d: AUC %.3f",k,af$AUC)else sprintf("Fold %d: one class; ROC undefined",k)
  }
  graphics::legend("bottomright",legend=labels,col=fold_colors,lty=1+(seq_along(auc_folds)-1)%%6,lwd=2,bty="n",cex=.85)
  graphics::mtext("Held-out experiment labels; species kept within one fold",side=3,line=.2,cex=.75)
}
grDevices::dev.off()
cat("已保存ROC图:",roc_pdf,"\n")
```

只比较同一种划分、同一套真实High/Low定义下的模型。随机物种分组与系统发育距离分块产生的AUC分别解释。AUC不评价定量比率误差，也不能证明High概率已经校准；两条路线原有ELPD评分继续保留。
