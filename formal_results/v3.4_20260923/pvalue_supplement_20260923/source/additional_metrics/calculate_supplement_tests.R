#!/usr/bin/env Rscript
args<-commandArgs(TRUE);root<-args[1];out<-args[2]
source(file.path(root,"R/bootstrap.R"));load_v3_modules(root);source(file.path(out,"supplement_functions.R"))
plan<-jsonlite::read_json(file.path(out,"ANALYSIS_PLAN.json"),simplifyVector=TRUE)
B<-as.integer(plan$bootstrap_replicates);seed_base<-as.integer(plan$seed_base)
evidence<-read.csv(file.path(root,"results/cv_record_predictions.csv"),stringsAsFactors=FALSE)
summary<-read.csv(file.path(root,"results/cv_metrics_summary.csv"),stringsAsFactors=FALSE)
stopifnot(nrow(evidence)==4880L,all(evidence$RunPurpose=="formal"),B==50000L)
for(n in names(plan$source_hashes))stopifnot(sha256_file(file.path(root,"results",n))==plan$source_hashes[[n]])
models<-V3_MODELS;tws<-V3_TRAIN_WEIGHTINGS;ews<-V3_EVAL_WEIGHTINGS;designs<-V3_DESIGNS
rows<-list();boot_draws<-list();count_draws<-list();fold_support<-list();point_checks<-list();identity_checks<-list()
point_ref<-function(design,route,model,tw,ew,metric){z<-summary[summary$Design==design&summary$Route==route&summary$Model==model&summary$TrainWeighting==tw&summary$EvalWeighting==ew,,drop=FALSE];stopifnot(nrow(z)==1L);z[[metric]]}
store_row<-function(metric,design,route,model,tw,ew,estimate,reference,reference_label,draw_delta,test,records,species,k,seed_note,support_note,eligible=TRUE){
 key<-paste(metric,design,model,tw,ew,sep="|")
 boot_draws[[key]]<<-draw_delta
 rows[[length(rows)+1L]]<<-cbind(data.frame(Metric=metric,Design=design,Route=route,Model=model,TrainWeighting=tw,EvalWeighting=ew,Estimate=estimate,Reference=reference_label,ReferenceEstimate=reference,Records=records,Species=species,FoldCount=k,BootstrapReplicates=B,BootstrapValid=B,SeedRule=seed_note,MultiplicityEligible=eligible,SupportNote=support_note,InferenceScope="fixed_OOF_predictions_conditional_exploratory_no_refitting",CIKind="percentile_cluster_bootstrap_interval_for_difference",stringsAsFactors=FALSE),as.data.frame(test,stringsAsFactors=FALSE))
}
for(di in seq_along(designs)){
 design<-designs[di];k<-V3_DESIGN_K[[design]]
 # AUC uses the production equal-fold mean, not pooled AUC.
 binary<-evidence[evidence$Design==design&evidence$Route=="binary",,drop=FALSE]
 base<-binary[binary$Model=="Null"&binary$TrainWeighting=="record_equal",,drop=FALSE]
 stopifnot(nrow(base)==152L,length(unique(base$Species))==50L,!anyDuplicated(base$RecordID))
 counts<-metas<-vector("list",k)
 for(f in seq_len(k)){
  d<-base[base$Fold==f,,drop=FALSE];m<-auc_species_stats(d);seed<-seed_base+1000L*di+10L*f
  metas[[f]]<-m;counts[[f]]<-auc_stratified_counts(m,B,seed)
  neg_species<-sum(m$low>0);pos_species<-sum(m$high>0)
  fold_support[[length(fold_support)+1L]]<-data.frame(Design=design,Fold=f,Species=length(m$n),Records=sum(m$n),HighOnly=sum(m$type=="HIGH_only"),LowOnly=sum(m$type=="LOW_only"),Mixed=sum(m$type=="mixed"),HighBearingSpecies=pos_species,LowBearingSpecies=neg_species,SingletonOutcomeStrata=sum(table(m$type)==1L),Seed=seed)
 }
 count_draws[[paste0("AUC_",design)]]<-list(metas=metas,counts=counts)
 support_text<-if(any(vapply(metas,function(m)sum(m$low>0)<2L||sum(m$high>0)<2L,logical(1))))"LIMITED_CLASS_SPECIES_IN_SOME_FOLDS" else "CONDITIONAL_ON_FOLD_AND_SPECIES_OUTCOME_STRATA"
 for(model in models)for(tw in tws){
  z<-binary[binary$Model==model&binary$TrainWeighting==tw,,drop=FALSE]
  stopifnot(!anyDuplicated(z$RecordID),setequal(z$RecordID,base$RecordID));z<-z[match(base$RecordID,z$RecordID),]
  stopifnot(identical(z$Species,base$Species),identical(z$Fold,base$Fold),identical(z$ObservedHigh,base$ObservedHigh))
  for(ew in ews){
   point_folds<-numeric(k);replicates<-numeric(B)
   for(f in seq_len(k)){
    m<-auc_species_stats(z[z$Fold==f,,drop=FALSE]);stopifnot(identical(m$species,metas[[f]]$species),identical(m$n,metas[[f]]$n),identical(m$high,metas[[f]]$high))
    point_folds[f]<-auc_from_cluster_counts(m,rep(1,length(m$n)),ew)
    replicates<-replicates+auc_from_cluster_counts(m,counts[[f]],ew)/k
   }
   point<-mean(point_folds);target<-point_ref(design,"binary",model,tw,ew,"AUC");err<-abs(point-target);stopifnot(err<1e-12,all(replicates>=0&replicates<=1))
   test<-normal_bootstrap_test(point,.5,replicates,model=="Null")
   store_row("AUC",design,"binary",model,tw,ew,point,.5,"chance_level_0.5",replicates-.5,test,nrow(z),50L,k,"seed_base+1000*design_index+10*fold",support_text,model!="Null")
   point_checks[[length(point_checks)+1L]]<-data.frame(Metric="AUC",Design=design,Model=model,TrainWeighting=tw,EvalWeighting=ew,AbsDifferenceFromFormal=err)
  }
 }
 cat("AUC_SUPPLEMENT_DONE",design,"\n");flush.console()
 # Error metrics: paired, whole-design resampling of point-eligible species.
 joint<-evidence[evidence$Design==design&evidence$Route=="joint_bb"&evidence$Type%in%c("count","exact"),,drop=FALSE]
 base<-joint[joint$Model=="Null"&joint$TrainWeighting=="record_equal",,drop=FALSE];base<-base[order(base$RecordID),]
 stopifnot(nrow(base)==145L,length(unique(base$Species))==48L,!anyDuplicated(base$RecordID))
 data<-base[,c("RecordID","Species","Type","ObservedPoint","Fold"),drop=FALSE];pred_cols<-character()
 for(model in models)for(tw in tws){
  z<-joint[joint$Model==model&joint$TrainWeighting==tw,,drop=FALSE]
  stopifnot(nrow(z)==145L,!anyDuplicated(z$RecordID),setequal(z$RecordID,base$RecordID));z<-z[match(base$RecordID,z$RecordID),]
  stopifnot(identical(z$Species,base$Species),identical(z$Fold,base$Fold),identical(z$Type,base$Type),identical(z$ObservedPoint,base$ObservedPoint))
  nm<-paste(model,tw,sep="|");data[[nm]]<-z$PredictedPoint;pred_cols<-c(pred_cols,nm)
 }
 meta<-error_species_stats(data,pred_cols);seed<-seed_base+1000L*di+999L
 set.seed(seed);multi<-rmultinom(B,length(meta$n),rep(1/length(meta$n),length(meta$n)))
 count_draws[[paste0("ERROR_",design)]]<-list(meta=meta,counts=multi,seed=seed)
 for(ew in ews){
  point<-error_metrics_from_counts(meta,rep(1,length(meta$n)),ew);boots<-error_metrics_from_counts(meta,multi,ew)
  stopifnot(all(boots$RMSE>=boots$MAE-1e-12),all(is.finite(boots$MAE)),all(is.finite(boots$RMSE)))
  for(metric in c("MAE","RMSE"))for(model in models)for(tw in tws){
   nm<-paste(model,tw,sep="|");candidate<-point[[metric]][1,nm];ref<-point[[metric]][1,paste("Null",tw,sep="|")]
   target<-point_ref(design,"joint_bb",model,tw,ew,metric);err<-abs(candidate-target);stopifnot(err<1e-12)
   point_checks[[length(point_checks)+1L]]<-data.frame(Metric=metric,Design=design,Model=model,TrainWeighting=tw,EvalWeighting=ew,AbsDifferenceFromFormal=err)
   if(model=="Null")next
   difference<-candidate-ref;draws<-boots[[metric]][,nm]-boots[[metric]][,paste("Null",tw,sep="|")]
   test<-normal_bootstrap_test(difference,0,draws)
   store_row(metric,design,"joint_bb",model,tw,ew,candidate,ref,"Null_same_training",draws,test,145L,48L,k,"seed_base+1000*design_index+999","paired_species_bootstrap_complete_point_subset",TRUE)
  }
 }
 cat("ERROR_SUPPLEMENT_DONE",design,"\n");flush.console()
}
ans<-do.call(rbind,rows);rownames(ans)<-NULL
keys<-c("Metric","Design","Route","Model","TrainWeighting","EvalWeighting")
stopifnot(nrow(ans)==80L,!anyDuplicated(ans[keys]),sum(ans$MultiplicityEligible)==72L)
ans$P_BH_endpoint<-ans$P_BH_three_metrics<-NA_real_
for(d in designs)for(ew in ews){
 ix<-which(ans$Design==d&ans$EvalWeighting==ew&ans$MultiplicityEligible);stopifnot(length(ix)==18L)
 ans$P_BH_three_metrics[ix]<-p.adjust(ans$P_approx[ix],method="BH",n=18L)
 for(metric in c("AUC","MAE","RMSE")){
  j<-ix[ans$Metric[ix]==metric];stopifnot(length(j)==6L);ans$P_BH_endpoint[j]<-p.adjust(ans$P_approx[j],method="BH",n=6L)
 }
}
ans$Alternative<-"two.sided";ans$AnalysisRole<-"post_hoc_exploratory_supplement"
write_csv_atomic(ans,file.path(out,"supplementary_metric_tests.csv"))
for(metric in c("AUC","MAE","RMSE"))write_csv_atomic(ans[ans$Metric==metric,,drop=FALSE],file.path(out,paste0(tolower(metric),"_tests.csv")))
write_csv_atomic(do.call(rbind,fold_support),file.path(out,"auc_fold_species_support.csv"))
write_csv_atomic(do.call(rbind,point_checks),file.path(out,"point_estimate_reconciliation.csv"))
saveRDS(boot_draws,file.path(out,"bootstrap_difference_draws.rds"),compress=TRUE)
saveRDS(count_draws,file.path(out,"bootstrap_species_multiplicities.rds"),compress=TRUE)
for(n in names(plan$source_hashes))stopifnot(sha256_file(file.path(root,"results",n))==plan$source_hashes[[n]])
write_json_atomic(list(status="COMPLETED",rows=80L,auc_rows=32L,mae_rows=24L,rmse_rows=24L,structural_null_auc_rows=sum(ans$Model=="Null"),inferential_tests=72L,bootstrap_replicates=B,degenerate_nonnull_rows=sum(ans$TestStatus=="DEGENERATE_CLUSTER_BOOTSTRAP"),max_point_difference=max(do.call(rbind,point_checks)$AbsDifferenceFromFormal),new_fits=0L,source_results_modified=FALSE),file.path(out,"calculation_status.json"))
cat("SUPPLEMENT_METRIC_TESTS_COMPLETE: 80 rows, 72 inferential tests, fixed OOF only, no MCMC\n")
