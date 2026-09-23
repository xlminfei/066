# Read and score completed current CV fits. No model fitting occurs in this script.
options(warn = 1) # Preserve warning messages in the job log as they occur.
source("/project/work/ratio_analysis_20260914/scripts/common.R",local=.GlobalEnv)
initialize_manual()
required_models<-prepared$model_grid$Model
NUMERICAL_SCORE_PROTOCOL <- "stable_beta_logtails_20260916_v1"
NUMERICAL_HELPERS <- c("stable_beta_interval.R","stable_cv_likelihood.R")
COMPATIBILITY_RELATIVE <- "review/likelihood_diagnosis_20260916/stable_compatibility_all.csv"
COMPATIBILITY_MANIFEST_RELATIVE <- "review/likelihood_diagnosis_20260916/stable_compatibility_sources.csv"
repair_models <- c("Phylogeny_only_P","Site315_P","M1_P","M2_P","M3_P")

# Verification only: no stable likelihood helper is sourced or executed here.
read_numerical_compatibility <- function(root,run_dir,models) {
  compatibility_path<-file.path(root,COMPATIBILITY_RELATIVE)
  manifest_path<-file.path(root,COMPATIBILITY_MANIFEST_RELATIVE)
  if(!file.exists(compatibility_path) || !file.exists(manifest_path))
    stop("Numerical compatibility evidence is not complete; require all100 folds and its source manifest")
  tab<-read.csv(compatibility_path,stringsAsFactors=FALSE)
  required<-c("Model","CVType","Fold","ParentKey","OriginalNonfiniteHeldout","OriginalNonfiniteTraining",
    "CorrectedNonfinite","MaxAbsTrainingJointLogDifference","ELPDDifference","MaxAbsHeldoutEventProbabilityDifference")
  stopifnot(all(required%in%names(tab)),nrow(tab)==100L,!anyDuplicated(paste(tab$Model,tab$CVType,tab$Fold)))
  expected<-expand.grid(Model=models,CVType=c("species","phylo_distance"),Fold=1:5,stringsAsFactors=FALSE)
  stopifnot(setequal(paste(tab$Model,tab$CVType,tab$Fold),paste(expected$Model,expected$CVType,expected$Fold)),
    all(is.finite(tab$OriginalNonfiniteHeldout)),all(tab$OriginalNonfiniteHeldout>=0),
    all(tab$OriginalNonfiniteTraining==0L),all(tab$CorrectedNonfinite==0L),
    all(is.finite(tab$MaxAbsTrainingJointLogDifference)),all(tab$MaxAbsTrainingJointLogDifference>=0),
    all(tab$MaxAbsTrainingJointLogDifference<=1e-8))
  finite_original<-tab$OriginalNonfiniteHeldout==0L
  stopifnot(all(is.finite(tab$ELPDDifference[finite_original])),all(abs(tab$ELPDDifference[finite_original])<=1e-8),
    all(is.finite(tab$MaxAbsHeldoutEventProbabilityDifference)),all(tab$MaxAbsHeldoutEventProbabilityDifference>=0),
    all(tab$MaxAbsHeldoutEventProbabilityDifference[finite_original]<=1e-9))
  selected<-read.csv(file.path(run_dir,"fit_index.csv"),stringsAsFactors=FALSE)
  selected<-selected[selected$Outcome=="joint" & selected$Variant=="primary",,drop=FALSE]
  selected<-selected[!duplicated(selected$Model,fromLast=TRUE),,drop=FALSE]
  stopifnot(nrow(selected)==10L,setequal(selected$Model,models),
    all(tab$ParentKey==selected$Key[match(tab$Model,selected$Model)]))
  sources<-read.csv(manifest_path,stringsAsFactors=FALSE)
  stopifnot(all(c("File","Bytes","SHA256")%in%names(sources)),!anyDuplicated(sources$File),
    all(!grepl("^(/|[A-Za-z]:)",sources$File)))
  root_normal<-normalizePath(root,winslash="/",mustWork=TRUE)
  paths<-normalizePath(file.path(root,sources$File),winslash="/",mustWork=TRUE)
  stopifnot(all(startsWith(paths,paste0(root_normal,"/"))),!anyDuplicated(paths))
  actual<-vapply(paths,function(p)digest::digest(file=p,algo="sha256"),character(1))
  stopifnot(all(file.info(paths)$size==sources$Bytes),all(actual==sources$SHA256))
  required_files<-c(COMPATIBILITY_RELATIVE,"input/observations.csv","input/sites.csv","input/tree.nwk",
    "scripts/audit_stable_cv_likelihood.R",file.path("scripts",NUMERICAL_HELPERS))
  stopifnot(all(gsub("\\\\","/",required_files)%in%gsub("\\\\","/",sources$File)))
  source_map<-stats::setNames(sources$SHA256,paths)
  directories<-read.csv(file.path(root,"provenance","cv_directory_manifest.csv"),stringsAsFactors=FALSE)
  directories<-directories[directories$Outcome=="joint",,drop=FALSE]
  stopifnot(nrow(directories)==2L,setequal(directories$CVType,c("species","phylo_distance")))
  for(model in models) {
    parent_file<-normalizePath(file.path(run_dir,selected$RelativeFile[match(model,selected$Model)]),winslash="/",mustWork=TRUE)
    stopifnot(parent_file%in%names(source_map))
    for(design in c("species","phylo_distance")) {
      folder<-normalizePath(directories$Directory[directories$CVType==design],winslash="/",mustWork=TRUE)
      stopifnot(paste0(folder,"/folds.csv")%in%names(source_map))
      for(k in 1:5) {
        matches<-paths[dirname(paths)==folder & grepl(paste0("^",model,"_[0-9a-f]{16}_fold",k,"[.]rds$"),basename(paths))]
        stopifnot(length(matches)==1L)
      }
    }
  }
  list(table=tab,sources=sources,source_map=source_map,manifest_sha256=digest::digest(file=manifest_path,algo="sha256"))
}

verify_extension_numerics <- function(manifest,cv,parent,root,compatibility) {
  stopifnot(is.character(manifest$CVReceipt),length(manifest$CVReceipt)==1L,file.exists(manifest$CVReceipt))
  receipt<-jsonlite::read_json(manifest$CVReceipt,simplifyVector=TRUE)
  stopifnot(receipt$status=="PASS",receipt$key==cv$key,receipt$parent_key==parent$key,
    receipt$outcome==cv$outcome,receipt$model==cv$model,receipt$cv_type==cv$request$type)
  if(!"NumericalLikelihoodMethod"%in%names(manifest)) {
    stopifnot(manifest$ScriptSHA256==digest::digest(file=file.path(root,"scripts","export_cv_extensions.R"),algo="sha256"),
      !any(c("LikelihoodHelperSHA256","RawFoldFiles","CompatibilityManifest","ScoringUnchangedModel")%in%names(manifest)),
      is.null(cv$likelihood_evaluation),is.null(cv$evaluated_log_lik),!"score_protocol"%in%names(receipt))
    return("legacy_stan_generated_log_lik")
  }
  stopifnot(identical(manifest$NumericalLikelihoodMethod,NUMERICAL_SCORE_PROTOCOL),identical(manifest$ScoringUnchangedModel,TRUE),
    cv$outcome=="joint",cv$request$type=="phylo_distance",cv$model%in%repair_models,
    manifest$ScriptSHA256==digest::digest(file=file.path(root,"scripts","export_cv_extensions_stable.R"),algo="sha256"),
    identical(manifest$CompatibilityManifest,COMPATIBILITY_MANIFEST_RELATIVE),
    manifest$CompatibilityManifestSHA256==compatibility$manifest_sha256)
  helpers<-stats::setNames(vapply(NUMERICAL_HELPERS,function(n)digest::digest(file=file.path(root,"scripts",n),algo="sha256"),character(1)),NUMERICAL_HELPERS)
  mh<-unlist(manifest$LikelihoodHelperSHA256,use.names=TRUE)
  evaluation<-cv$likelihood_evaluation
  eh<-unlist(evaluation$helper_sha256,use.names=TRUE)
  rh<-unlist(receipt$likelihood_helper_sha256,use.names=TRUE)
  stopifnot(length(mh)==2L,setequal(names(mh),NUMERICAL_HELPERS),identical(unname(mh[NUMERICAL_HELPERS]),unname(helpers)),
    identical(evaluation$version,NUMERICAL_SCORE_PROTOCOL),identical(evaluation$sampling_changed,FALSE),
    length(eh)==2L,setequal(names(eh),NUMERICAL_HELPERS),identical(unname(eh[NUMERICAL_HELPERS]),unname(helpers)),
    identical(receipt$score_protocol,NUMERICAL_SCORE_PROTOCOL),identical(receipt$sampling_changed,FALSE),
    length(rh)==2L,setequal(names(rh),NUMERICAL_HELPERS),identical(unname(rh[NUMERICAL_HELPERS]),unname(helpers)),
    length(cv$evaluated_log_lik)==5L,length(evaluation$fold_diagnostics)==5L)
  raw<-evaluation$raw_fold_files;exposed<-manifest$RawFoldFiles
  for(x in list(raw,exposed))stopifnot(is.data.frame(x),nrow(x)==5L,
    all(c("Fold","File","SHA256","DataKey")%in%names(x)),setequal(x$Fold,1:5),!anyDuplicated(x$Fold))
  raw<-raw[order(raw$Fold),,drop=FALSE];exposed<-exposed[order(exposed$Fold),,drop=FALSE]
  stopifnot(identical(as.integer(raw$Fold),as.integer(exposed$Fold)),
    identical(as.character(raw$File),as.character(exposed$File)),identical(as.character(raw$SHA256),as.character(exposed$SHA256)),
    identical(as.character(raw$DataKey),as.character(exposed$DataKey)))
  for(k in 1:5) {
    path<-normalizePath(raw$File[k],winslash="/",mustWork=TRUE)
    stopifnot(path%in%names(compatibility$source_map),raw$SHA256[k]==compatibility$source_map[[path]],
      raw$SHA256[k]==digest::digest(file=path,algo="sha256"))
    original<-readRDS(path)
    d<-parent$request$data;held<-cv$heldout_rows[[k]];d$train[held]<-0L
    stopifnot(identical(original$data_key,raw$DataKey[k]),identical(original$data_key,digest::digest(d,algo="sha256")),
      identical(original$fit@sim,cv$fold_fits[[k]]@sim))
    dimensions<-dim(rstan::extract(cv$fold_fits[[k]],pars="alpha",permuted=FALSE,inc_warmup=FALSE))
    corrected<-cv$evaluated_log_lik[[k]]
    stopifnot(is.matrix(corrected),nrow(corrected)==prod(dimensions[1:2]),ncol(corrected)==length(held),all(is.finite(corrected)))
    dg<-evaluation$fold_diagnostics[[k]]
    stopifnot(nrow(dg)==1L,dg$Fold==k,dg$OriginalNonfiniteTraining==0L,dg$CorrectedNonfinite==0L,
      is.finite(dg$MaxAbsTrainingJointLogDifference),dg$MaxAbsTrainingJointLogDifference<=1e-8)
    rm(original);invisible(gc())
  }
  NUMERICAL_SCORE_PROTOCOL
}

numerical_compatibility<-read_numerical_compatibility(analysis_root,RUN_DIR,required_models)
score_protocol_rows<-list()
all_manifests<-list();all_mc<-list();all_comparisons<-list();all_quantitative<-list()
all_calibration_bins<-list();all_calibration_species<-list();all_brier<-list()
derived_root<-file.path(analysis_root,"derived","cv_comparisons")
dir.create(derived_root,recursive=TRUE,showWarnings=FALSE)
for(route in c("binary","joint")) {
  run_block("05_诊断与模型比较.md","05_LOAD",overrides=list(OUTCOME=route,VARIANT="primary"))
  diagnostics<-utils::read.csv(file.path(RUN_DIR,"results",paste0("diagnostics_",route,"_primary.csv")),stringsAsFactors=FALSE)
  stopifnot(setequal(names(bundles),required_models),setequal(diagnostics$Model,required_models),all(diagnostics$Status=="PASS"))
  for(design in c("species","phylo_distance")) {
    run_block("06_留出验证.md","06_FOLDS",overrides=list(CV_TYPE=design))
    run_block("06_留出验证.md","06_COMPARE")
    mc_rows<-list();quant_rows<-list();diagnostic_rows_cv<-list()
    selected_cv_index<-utils::read.csv(file.path(CV_DIR,"cv_index.csv"),stringsAsFactors=FALSE)
    selected_cv_index<-selected_cv_index[!duplicated(selected_cv_index$Model,fromLast=TRUE),,drop=FALSE]
    stopifnot(nrow(selected_cv_index)==length(required_models),setequal(selected_cv_index$Model,required_models))
    for(model in required_models) {
      selected_row<-selected_cv_index[selected_cv_index$Model==model,,drop=FALSE]
      selected_cv_path<-file.path(CV_DIR,selected_row$File)
      selected_cv<-readRDS(selected_cv_path)
      stopifnot(nrow(selected_row)==1L,selected_row$Status=="PASS",selected_cv$status=="PASS",
        selected_cv$key==selected_row$Key,selected_cv$key==digest::digest(selected_cv$request,algo="sha256"),
        selected_cv$outcome==route,selected_cv$model==model,selected_cv$request$type==design,
        selected_cv$request$fold_key==fold_key,identical(selected_cv$request$folds,fold_table),
        selected_cv$parent_key==bundles[[model]]$key,selected_row$ParentKey==bundles[[model]]$key)
      extension_dir<-file.path(analysis_root,"derived","cv_extensions",paste(route,design,model,sep="_"))
      manifest_path<-file.path(extension_dir,"postprocessing_manifest.json")
      if(!file.exists(manifest_path))stop("Missing current CV extensions: ",extension_dir)
      manifest<-jsonlite::read_json(manifest_path,simplifyVector=TRUE)
      stopifnot(manifest$status=="PASS",manifest$Outcome==route,manifest$Model==model,
        manifest$CVType==design,manifest$FoldKey==fold_key,manifest$FitKey==bundles[[model]]$key,
        manifest$CVKey==selected_cv$key,
        manifest$InputSHA256$CV==digest::digest(file=selected_cv_path,algo="sha256"))
      score_protocol<-verify_extension_numerics(manifest,selected_cv,bundles[[model]],analysis_root,numerical_compatibility)
      score_protocol_rows[[paste(route,design,model)]]<-data.frame(Outcome=route,CVType=design,Model=model,
        CVKey=selected_cv$key,ParentKey=selected_cv$parent_key,NumericalLikelihoodMethod=score_protocol,stringsAsFactors=FALSE)
      mc<-utils::read.csv(file.path(extension_dir,"cv_fold_scores_mc.csv"),stringsAsFactors=FALSE)
      stopifnot(nrow(mc)==CV_K,setequal(mc$Fold,seq_len(CV_K)),all(mc$SamplingStatus=="PASS"),
        all(is.finite(mc$ELPD)),all(abs(mc$ELPDReconstructionDifference)<1e-8),
        all(mc$Outcome==route),all(mc$Model==model),all(mc$CVType==design),all(mc$FoldKey==fold_key),
        all(mc$CVKey==selected_cv$key),all(mc$FitKey==bundles[[model]]$key),
        max(abs(mc$ELPD-selected_cv$fold_scores$ELPD[match(mc$Fold,selected_cv$fold_scores$Fold)]))<1e-8,
        abs(sum(mc$ELPD)-cv_comparison$ELPD[match(model,cv_comparison$Model)])<1e-8)
      mc_rows[[model]]<-mc
      dg<-selected_cv$diagnostics
      stopifnot(nrow(dg)==5L,setequal(dg$Fold,1:5),all(dg$Status=="PASS"))
      dg$Outcome<-route;dg$CVType<-design;dg$Model<-model;dg$CVKey<-selected_cv$key;dg$ParentKey<-selected_cv$parent_key
      diagnostic_rows_cv[[model]]<-dg
      if(route=="joint") {
        qm<-utils::read.csv(file.path(extension_dir,"quantitative_metrics_summary.csv"),stringsAsFactors=FALSE)
        qr<-utils::read.csv(file.path(extension_dir,"quantitative_metrics_by_record.csv"),stringsAsFactors=FALSE)
        actual_point<-prepared$observations[prepared$observations$Type%in%c("count","exact"),,drop=FALSE]
        stopifnot(nrow(qm)==3L,setequal(qm$Type,c("count+exact","count","exact")),all(is.na(qm$Fold)),
          nrow(qr)==nrow(actual_point),!anyDuplicated(qr$RecordID),setequal(qr$RecordID,actual_point$RecordID))
        for(tab in list(qm,qr))stopifnot(all(tab$Outcome==route),all(tab$Model==model),all(tab$CVType==design),
          all(tab$FoldKey==fold_key),all(tab$CVKey==selected_cv$key),all(tab$FitKey==bundles[[model]]$key),
          all(tab$PointRule=="posterior_mean_of_species_expected_ratio_m"))
        actual_point<-actual_point[match(qr$RecordID,actual_point$RecordID),,drop=FALSE]
        actual_ratio<-ifelse(actual_point$Type=="count",actual_point$Events/actual_point$Total,actual_point$Exact)
        stopifnot(identical(qr$Species,actual_point$Species),identical(qr$Type,actual_point$Type),
          max(abs(qr$ObservedRatio-actual_ratio))<1e-12,
          all(qr$Fold==selected_cv$predictions$Fold[match(qr$RecordID,selected_cv$predictions$RecordID)]))
        for(kind in c("count+exact","count","exact")) {
          expected<-if(kind=="count+exact")actual_point else actual_point[actual_point$Type==kind,,drop=FALSE]
          z<-if(kind=="count+exact")qr else qr[qr$Type==kind,,drop=FALSE]
          row<-qm[qm$Type==kind,,drop=FALSE]
          source_ids<-strsplit(row$SourceRecordIDs,"|",fixed=TRUE)[[1L]]
          stopifnot(length(source_ids)==nrow(expected),!anyDuplicated(source_ids),setequal(source_ids,expected$RecordID),
            row$NRecords==nrow(expected),row$NSpecies==length(unique(expected$Species)),
            abs(row$MAE-mean(z$AbsoluteError))<1e-12,abs(row$RMSE-sqrt(mean(z$SquaredError)))<1e-12,
            abs(row$CRPS-mean(z$CRPS))<1e-12,abs(row$Coverage50-mean(z$Covered50))<1e-12,
            abs(row$Coverage95-mean(z$Covered95))<1e-12)
        }
        quant_rows[[model]]<-qm
      }
      rm(selected_cv);gc()
    }
    mc_data<-do.call(rbind,mc_rows)
    comparison<-cv_comparison
    comparison$Outcome<-route;comparison$CVType<-design;comparison$FoldKey<-fold_key
    comparison$ReferenceModel<-names(which.max(setNames(comparison$ELPD,comparison$Model)))
    comparison$MCFlaggedFolds<-vapply(comparison$Model,function(model)sum(mc_rows[[model]]$MCReviewStatus!="NO_SCREEN_FLAG"),integer(1))
    comparison$DeltaMethod_MCSE_TotalELPD<-vapply(comparison$Model,function(model)sqrt(sum(mc_rows[[model]]$DeltaMethod_MCSE_LogPredictive^2)),numeric(1))
    comparison$MaximumLikelihoodContribution<-vapply(comparison$Model,function(model)max(mc_rows[[model]]$MaxNormalizedContribution),numeric(1))
    comparison$MinimumEffectiveContributions<-vapply(comparison$Model,function(model)min(mc_rows[[model]]$EffectiveContributionCount),numeric(1))
    comparison$AnyModelMCReview<-any(comparison$MCFlaggedFolds>0)
    comparison$Interpretation<-if(any(comparison$MCFlaggedFolds>0))"FINITE_DRAW_JOINT_SCORE_WITH_MC_REVIEW_NO_DEFINITIVE_RANK"else"FINITE_DRAW_JOINT_SCORE_NO_SCREEN_FLAG_NOT_PROOF_OF_UNIQUE_BEST"
    output_dir<-file.path(derived_root,paste(route,design,sep="_"))
    dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
    write.csv(comparison,file.path(output_dir,"cv_model_comparison_with_mc.csv"),row.names=FALSE,na="")
    write.csv(mc_data,file.path(output_dir,"cv_fold_scores_with_mc.csv"),row.names=FALSE,na="")
    write.csv(do.call(rbind,diagnostic_rows_cv),file.path(output_dir,"cv_fold_diagnostics.csv"),row.names=FALSE,na="")
    all_mc[[paste(route,design)]]<-mc_data;all_comparisons[[paste(route,design)]]<-comparison
    if(route=="joint") {
      quantitative<-do.call(rbind,quant_rows)
      for(kind in unique(quantitative$Type)) {
        q<-quantitative[quantitative$Type==kind,,drop=FALSE]
        stopifnot(nrow(q)==length(required_models),length(unique(q$SourceRecordIDs))==1L,
          length(unique(q$NRecords))==1L,all(q$PointRule=="posterior_mean_of_species_expected_ratio_m"))
      }
      write.csv(quantitative,file.path(output_dir,"quantitative_metrics_all_models.csv"),row.names=FALSE,na="")
      all_quantitative[[design]]<-quantitative
      auc_dir<-NA_character_
    } else {
      run_block("06A_HighLow_ROC_AUC.md","06A_SETUP")
      run_block("06A_HighLow_ROC_AUC.md","06A_LOAD")
      run_block("06A_HighLow_ROC_AUC.md","06A_METRICS")
      run_block("06A_HighLow_ROC_AUC.md","06A_SAVE")
      run_block("06A_HighLow_ROC_AUC.md","06A_PLOT")
      # Annotated plotting copies retain the original 06A CSV/RDS products and their identity.
      for(table_name in c("roc_oof_experiments","auc_by_fold","auc_summary","roc_coordinates_by_fold")) {
        object_name<-switch(table_name,roc_oof_experiments="roc_data",roc_coordinates_by_fold="roc_coordinates",table_name)
        annotated<-get(object_name)
        annotated$CVType<-design;annotated$FoldKey<-fold_key
        annotated$AUCKey<-auc_key;annotated$SourceDirectory<-AUC_DIR
        write.csv(annotated,file.path(output_dir,paste0(table_name,".csv")),row.names=FALSE,na="")
      }
      stopifnot(nrow(roc_data)==152L*length(required_models),nrow(auc_by_fold)==5L*length(required_models))
      if(design=="species")stopifnot(all(auc_summary$Status=="DEFINED"))
      if(design=="phylo_distance")stopifnot(all(auc_summary$Status=="NOT_DEFINED_ONE_CLASS_FOLD"),all(is.na(auc_summary$CV_AUC)))
      bin_rows<-list();species_rows<-list();brier_rows<-list()
      edges<-c(0,.2,.4,.6,.8,1)
      for(model in required_models) {
        z<-roc_data[roc_data$Model==model,,drop=FALSE]
        stopifnot(nrow(z)==152L,length(unique(z$RecordID))==152L)
        bin<-pmin(5L,findInterval(z$OOFPrHigh,edges,rightmost.closed=TRUE,all.inside=TRUE))
        for(b in 1:5) {
          part<-z[bin==b,,drop=FALSE]
          bin_rows[[length(bin_rows)+1L]]<-data.frame(Model=model,CVType=design,Bin=b,
            Lower=edges[b],Upper=edges[b+1L],UpperInclusive=b==5L,Records=nrow(part),
            Species=length(unique(part$Species)),MeanForecastScore=if(nrow(part))mean(part$OOFPrHigh)else NA_real_,
            ObservedHighFraction=if(nrow(part))mean(part$High)else NA_real_,High=sum(part$High),
            ScoreDefinition="posterior_median_high_probability_Trials_1",
            Status=if(nrow(part))"DESCRIPTIVE_OOF_CALIBRATION_NO_INDEPENDENT_BINOMIAL_CI"else"EMPTY_BIN")
        }
        for(species in unique(z$Species)) {
          part<-z[z$Species==species,,drop=FALSE]
          stopifnot(length(unique(part$Fold))==1L,diff(range(part$OOFPrHigh))<1e-12)
          species_rows[[length(species_rows)+1L]]<-data.frame(Model=model,CVType=design,Species=species,Fold=part$Fold[1],
            OOFPrHigh=part$OOFPrHigh[1],HighCount=sum(part$High),Trials=nrow(part),ObservedHighFraction=mean(part$High),
            SourceCount=length(unique(part$SourceID)),LevelSeenInTraining=all(part$LevelSeenInTraining),
            FixedEffectEstimable=all(part$FixedEffectEstimable))
        }
        for(k in c(0L,seq_len(CV_K))) {
          part<-if(k==0L)z else z[z$Fold==k,,drop=FALSE]
          brier_rows[[length(brier_rows)+1L]]<-data.frame(Model=model,CVType=design,Fold=if(k==0L)NA_integer_ else k,
            Records=nrow(part),Species=length(unique(part$Species)),BrierScore=mean((part$OOFPrHigh-part$High)^2),
            Weighting="equal_weight_per_experiment",ScoreDefinition="posterior_median_high_probability_Trials_1",
            RecordIDs=paste(part$RecordID,collapse="|"))
        }
      }
      bins<-do.call(rbind,bin_rows);cal_species<-do.call(rbind,species_rows);brier<-do.call(rbind,brier_rows)
      stopifnot(all(tapply(bins$Records,bins$Model,sum)==152L))
      write.csv(bins,file.path(output_dir,"calibration_bins.csv"),row.names=FALSE,na="")
      write.csv(cal_species,file.path(output_dir,"calibration_species.csv"),row.names=FALSE,na="")
      write.csv(brier,file.path(output_dir,"brier_scores.csv"),row.names=FALSE,na="")
      all_calibration_bins[[design]]<-bins;all_calibration_species[[design]]<-cal_species;all_brier[[design]]<-brier
      auc_dir<-AUC_DIR
    }
    all_manifests[[paste(route,design)]]<-data.frame(Outcome=route,CVType=design,FoldKey=fold_key,
      CVDirectory=CV_DIR,ComparisonDirectory=output_dir,AUCDirectory=auc_dir,
      Status="COMPLETE_KEEP_MC_AND_AUC_LIMITATIONS",stringsAsFactors=FALSE)
  }
  rm(bundles);gc()
}
protocol_table<-do.call(rbind,score_protocol_rows)
stopifnot(nrow(protocol_table)==40L,sum(protocol_table$NumericalLikelihoodMethod==NUMERICAL_SCORE_PROTOCOL)==5L,
  sum(protocol_table$NumericalLikelihoodMethod=="legacy_stan_generated_log_lik")==35L)
write.csv(protocol_table,file.path(derived_root,"cv_numerical_protocols.csv"),row.names=FALSE)
write.csv(do.call(rbind,all_manifests),file.path(analysis_root,"provenance","cv_postprocessing_manifest.csv"),row.names=FALSE,na="")
write.csv(do.call(rbind,all_comparisons),file.path(derived_root,"cv_model_comparison_all.csv"),row.names=FALSE,na="")
write.csv(do.call(rbind,all_mc),file.path(derived_root,"cv_fold_scores_all.csv"),row.names=FALSE,na="")
write.csv(do.call(rbind,all_quantitative),file.path(derived_root,"quantitative_metrics_all.csv"),row.names=FALSE,na="")
atomic_json(list(status="COMPLETE_KEEP_MC_AND_AUC_LIMITATIONS",cv_designs=4L,cv_models=40L,fold_fits=200L,
  point_metric_rule="posterior_mean_of_species_expected_ratio_m",binary_score_rule="posterior_median_high_probability_Trials_1",
  numerical_likelihood_method=NUMERICAL_SCORE_PROTOCOL,numerical_compatibility_folds=100L,
  legacy_score_exports=35L,stable_score_exports=5L,compatibility_manifest_sha256=numerical_compatibility$manifest_sha256,
  calibration="descriptive pooled OOF bins; no independent-record confidence intervals",
  mc_screens="descriptive stability flags, not proof of accurate ranking",finished_at=format(Sys.time(),tz="UTC",usetz=TRUE)),
  file.path(derived_root,"postfit_cv_status.json"))
cat("FORMAL_CV_POSTPROCESSING_COMPLETE\n")
