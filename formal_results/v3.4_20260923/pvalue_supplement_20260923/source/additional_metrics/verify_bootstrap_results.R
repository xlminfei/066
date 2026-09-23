args<-commandArgs(TRUE);root<-args[1];out<-args[2]
source(file.path(root,"R/bootstrap.R"));load_v3_modules(root)
e<-read.csv(file.path(root,"results/cv_record_predictions.csv"),stringsAsFactors=FALSE)
r<-read.csv(file.path(out,"supplementary_metric_tests.csv"),stringsAsFactors=FALSE)
boot<-readRDS(file.path(out,"bootstrap_difference_draws.rds"));counts<-readRDS(file.path(out,"bootstrap_species_multiplicities.rds"))
expand_species<-function(d,species,multiplicity){
 result<-list();j<-0L
 for(s in seq_along(species))if(multiplicity[s]>0)for(copy in seq_len(multiplicity[s])){
  z<-d[d$Species==species[s],,drop=FALSE];z$Species<-paste0(species[s],"__copy_",copy);result[[j<-j+1L]]<-z
 }
 do.call(rbind,result)
}
checks<-list();selected<-c(1L,17003L,50000L)
for(i in seq_len(nrow(r))){row<-r[i,];key<-paste(row$Metric,row$Design,row$Model,row$TrainWeighting,row$EvalWeighting,sep="|")
 draw<-boot[[key]];stopifnot(length(draw)==50000L,all(is.finite(draw)))
 se<-sd(draw);q<-quantile(draw,c(.025,.975),names=FALSE)
 stopifnot(abs(row$SE_approx-se)<1e-12,max(abs(c(row$CI95_lower,row$CI95_upper)-q))<1e-12)
 z<-e[e$Design==row$Design&e$Route==row$Route&e$Model==row$Model&e$TrainWeighting==row$TrainWeighting,,drop=FALSE]
 for(b in selected){
  if(row$Metric=="AUC"){
   cd<-counts[[paste0("AUC_",row$Design)]];values<-numeric(row$FoldCount)
   for(f in seq_len(row$FoldCount)){
    zz<-expand_species(z[z$Fold==f,,drop=FALSE],cd$metas[[f]]$species,cd$counts[[f]][,b])
    w<-build_eval_weights(zz[,"Species",drop=FALSE],row$EvalWeighting)$weight
    values[f]<-weighted_auc(zz$ObservedHigh,zz$PredictedPrHigh,w)
   }
   actual<-mean(values)-.5
  }else{
   z<-z[z$Type%in%c("count","exact"),,drop=FALSE]
   ref<-e[e$Design==row$Design&e$Route==row$Route&e$Model=="Null"&e$TrainWeighting==row$TrainWeighting&e$Type%in%c("count","exact"),,drop=FALSE]
   ref<-ref[match(z$RecordID,ref$RecordID),];stopifnot(identical(z$Species,ref$Species),identical(z$ObservedPoint,ref$ObservedPoint))
   z$ReferencePrediction<-ref$PredictedPoint;cd<-counts[[paste0("ERROR_",row$Design)]]
   zz<-expand_species(z,cd$meta$species,cd$counts[,b]);w<-build_eval_weights(zz[,"Species",drop=FALSE],row$EvalWeighting)$weight
   f<-if(row$Metric=="MAE")weighted_mae else weighted_rmse
   actual<-f(zz$ObservedPoint,zz$PredictedPoint,w)-f(zz$ObservedPoint,zz$ReferencePrediction,w)
  }
  error<-abs(actual-draw[b]);stopifnot(error<1e-12)
  checks[[length(checks)+1L]]<-data.frame(Key=key,Replicate=b,AbsoluteDifference=error,Status="PASS")
 }
}
checks<-do.call(rbind,checks);write.csv(checks,file.path(out,"expanded_record_bootstrap_checks.csv"),row.names=FALSE)
jsonlite::write_json(list(status="PASS",result_rows=80,draw_distributions_checked=80,expanded_record_checks=nrow(checks),max_expanded_error=max(checks$AbsoluteDifference),new_fits=0),file.path(out,"bootstrap_verification.json"),auto_unbox=TRUE,pretty=TRUE,digits=16)
cat("BOOTSTRAP_VERIFICATION_PASS",nrow(checks),"literal expanded-record checks and 80 full draw distributions\n")
