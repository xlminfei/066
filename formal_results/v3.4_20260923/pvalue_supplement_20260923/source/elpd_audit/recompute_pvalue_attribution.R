#!/usr/bin/env Rscript
# Forensic reanalysis of saved OOF scores. No MCMC, no primary-result changes.
args<-commandArgs(TRUE);repo<-args[1];root<-args[2];out<-args[3]
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
old<-read.csv(file.path(repo,"v2","results","cv_record_scores_v2.csv"),stringsAsFactors=FALSE)
new<-read.csv(file.path(root,"results","cv_record_predictions.csv"),stringsAsFactors=FALSE)
old_saved<-read.csv(file.path(repo,"v2","results","derived","paired_elpd_comparisons.csv"),stringsAsFactors=FALSE)
# Recompute the existing v2 algorithm for the original 42 comparisons.
old_recomputed<-old_saved
for(i in seq_len(nrow(old_saved))){r<-old_saved[i,]
 a<-old[old$Route==r$Route&old$Design==r$Design&old$Model==r$Model,c("RecordID","Species","Score")]
 b<-old[old$Route==r$Route&old$Design==r$Design&old$Model==r$Reference,c("RecordID","Species","Score")]
 stopifnot(nrow(a)==nrow(b),!anyDuplicated(a$RecordID),setequal(a$RecordID,b$RecordID));b<-b[match(a$RecordID,b$RecordID),]
 stopifnot(identical(a$Species,b$Species))
 z<-data.frame(Species=a$Species,Score_model=a$Score,Score_reference=b$Score)
 by<-aggregate(cbind(Score_model,Score_reference)~Species,z,sum);delta<-by$Score_model-by$Score_reference;S<-nrow(by)
 total<-sum(delta);se<-sqrt(S*var(delta));p<-2*pnorm(-abs(total/se))
 old_recomputed$ELPD_difference[i]<-total;old_recomputed$Paired_SE_species[i]<-se;old_recomputed$p_value_normal_approx[i]<-p
}
old_recomputed$p_value_BH_all<-p.adjust(old_recomputed$p_value_normal_approx,"BH")
old_fields<-c("ELPD_difference","Paired_SE_species","p_value_normal_approx","p_value_BH_all")
old_err<-max(abs(as.matrix(old_recomputed[old_fields])-as.matrix(old_saved[old_fields])))
stopifnot(old_err<1e-10)
write.csv(old_recomputed,file.path(out,"v2_original_comparisons_recomputed.csv"),row.names=FALSE)
# Reproduce the current production comparisons, including the frozen bootstrap seed/B.
for(kind in c("model_vs_null","training_method_comparisons")){
 fun<-if(kind=="model_vs_null")compare_evidence_models else compare_training_methods
 computed<-do.call(rbind,lapply(V3_EVAL_WEIGHTINGS,function(ew)fun(new,ew,"design")))
 saved<-read.csv(file.path(root,"results",paste0(kind,".csv")),stringsAsFactors=FALSE)
 keys<-c("Design","Route","Model","EvalWeighting",if(kind=="model_vs_null")"TrainWeighting" else c("ModelA","ModelB"))
 key<-function(d)do.call(paste,c(d[keys],sep="|"));stopifnot(!anyDuplicated(key(computed)),setequal(key(saved),key(computed)))
 computed<-computed[match(key(saved),key(computed)),]
 fields<-c("Difference","SE_approx","CI95_lower","CI95_upper","P_approx","P_BH")
 err<-max(abs(as.matrix(saved[fields])-as.matrix(computed[fields])))
 stopifnot(err<1e-10)
 write.csv(data.frame(Check=kind,Rows=nrow(saved),MaxAbsDifference=err,Status="PASS"),file.path(out,paste0("v34_",kind,"_recompute_receipt.csv")),row.names=FALSE)
}
# Identical OOF vectors, different inference/weighting definitions. These are diagnostics,
# not extra confirmatory tests or a search for a preferred P value.
old_evidence<-data.frame(Design=ifelse(old$Design=="species5","fivefold","tenfold"),Route=old$Route,Model=old$Model,TrainWeighting="record_equal",RecordID=old$RecordID,Species=old$Species,Fold=old$Fold,Score=old$Score)
new_evidence<-data.frame(Design=new$Design,Route=new$Route,Model=new$Model,TrainWeighting=new$TrainWeighting,RecordID=new$RecordID,Species=new$Species,Fold=new$Fold,Score=new$LogPredictiveDensityRaw)
inputs<-list(v2=old_evidence,v34_record_training=new_evidence[new_evidence$TrainWeighting=="record_equal",])
cf<-list();species_rows<-list()
for(version in names(inputs))for(design in V3_DESIGNS)for(route in V3_ROUTES)for(model in c("M1","M2","M3")){
 d<-inputs[[version]];a<-d[d$Design==design&d$Route==route&d$Model==model,];b<-d[d$Design==design&d$Route==route&d$Model=="Null",]
 stopifnot(nrow(a)==nrow(b),setequal(a$RecordID,b$RecordID));b<-b[match(a$RecordID,b$RecordID),];stopifnot(identical(a$Species,b$Species),identical(a$Fold,b$Fold))
 diff<-a$Score-b$Score;sp<-sort(unique(a$Species));nn<-vapply(sp,function(s)sum(a$Species==s),integer(1));sums<-vapply(sp,function(s)sum(diff[a$Species==s]),numeric(1));means<-sums/nn;S<-length(sp);N<-length(diff)
 species_rows[[length(species_rows)+1]]<-data.frame(Version=version,Design=design,Route=route,Model=model,Species=sp,Records=nn,SumDifference=sums,MeanDifference=means,ContributionToRecordMean=sums/N,ContributionToSpeciesMean=means/S)
 for(ew in V3_EVAL_WEIGHTINGS){
  point<-if(ew=="record_equal")sum(sums)/N else mean(means)
  analytical_se<-if(ew=="record_equal")sqrt(S*var(sums))/N else sd(means)/sqrt(S)
  dsmall<-data.frame(RecordID=a$RecordID,Species=a$Species,Difference=diff)
  boot<-cluster_bootstrap_difference(dsmall,ew,V3_SEED+match(design,V3_DESIGNS)*100L+match(route,V3_ROUTES))
  stopifnot(abs(point-boot$mean)<1e-12)
  for(method in c("analytic_species_sums_or_means","current_species_bootstrap")){
   se<-if(method=="current_species_bootstrap")boot$se else analytical_se
   cf[[length(cf)+1]]<-data.frame(Version=version,Design=design,Route=route,Model=model,TrainWeighting="record_equal",EvalWeighting=ew,Inference=method,Species=S,Records=N,Difference=point,SE=se,Z=point/se,P=2*pnorm(-abs(point/se)),ScaledDifference=point*N,ScaledSE=se*N,AuditPurpose="method_attribution_only_fixed_saved_OOF")
  }
 }
}
cf<-do.call(rbind,cf);species_rows<-do.call(rbind,species_rows)
write.csv(cf,file.path(out,"fixed_OOF_method_weighting_counterfactuals.csv"),row.names=FALSE)
write.csv(species_rows,file.path(out,"paired_species_logscore_contributions.csv"),row.names=FALSE)
# Show multiple-adjustment consequences using a few explicitly named families.
old_null<-old_saved[old_saved$Reference=="Null"&old_saved$Model%in%c("M1","M2","M3"),]
old_null$BH_all18<-p.adjust(old_null$p_value_normal_approx,"BH")
old_null$BH_per_design9<-ave(old_null$p_value_normal_approx,old_null$Design,FUN=function(x)p.adjust(x,"BH"))
old_null$BH_per_route_design3<-ave(old_null$p_value_normal_approx,interaction(old_null$Design,old_null$Route),FUN=function(x)p.adjust(x,"BH"))
ref<-read.csv(file.path(repo,"v2/results/derived/paired_elpd_M1M2M3_vs_Null_corrections_by_fold.csv"))
k<-function(d)paste(d$Route,d$Design,d$Model);ref<-ref[match(k(old_null),k(ref)),]
historical_difference<-data.frame(Route=old_null$Route,Design=old_null$Design,Model=old_null$Model,SourceOOF_P=old_null$p_value_normal_approx,CorrectionTable_P=ref$p_value_normal_approx,SourceOOF_Delta=old_null$ELPD_difference,CorrectionTable_Delta=ref$ELPD_difference,RecomputedBH=old_null$BH_per_design9,SavedCorrectionBH=ref$BH_by_design)
write.csv(historical_difference,file.path(out,"v2_historical_table_source_discrepancy.csv"),row.names=FALSE)
# The historical table carries a different set of Scheme A inputs. Verify its own BH calculation, preserve the discrepancy, and do not silently treat it as the same evidence.
ref_bh<-ave(ref$p_value_normal_approx,ref$Design,FUN=function(x)p.adjust(x,"BH"))
stopifnot(max(abs(ref_bh-ref$BH_by_design))<1e-10)
focus<-old_null$Route=="joint_bb"&old_null$Model=="M3"
stopifnot(max(abs(old_null$BH_per_design9[focus]-ref$BH_by_design[focus]))<1e-10)
write.csv(old_null,file.path(out,"v2_BH_family_reconciliation.csv"),row.names=FALSE)
new_null<-read.csv(file.path(root,"results","model_vs_null.csv"))
new_null$BH_per_training3<-ave(new_null$P_approx,interaction(new_null$Design,new_null$Route,new_null$EvalWeighting,new_null$TrainWeighting),FUN=function(x)p.adjust(x,"BH"))
write.csv(new_null,file.path(out,"v34_BH_family_diagnostic.csv"),row.names=FALSE)
# Estimate bootstrap-only numerical sensitivity for main M3, no new fitted draws.
z<-species_rows[species_rows$Version=="v34_record_training"&species_rows$Design=="fivefold"&species_rows$Route=="joint_bb"&species_rows$Model=="M3",]
bootstrap_sensitivity<-list()
for(ew in V3_EVAL_WEIGHTINGS)for(seed in c(20261022L,4101L,4102L,4103L,4104L)){
 set.seed(seed);ix<-matrix(sample.int(nrow(z),nrow(z)*20000,replace=TRUE),nrow=nrow(z))
 vals<-if(ew=="species_equal")colMeans(matrix(z$MeanDifference[ix],nrow(z))) else colSums(matrix(z$SumDifference[ix],nrow(z)))/colSums(matrix(z$Records[ix],nrow(z)))
 point<-if(ew=="species_equal")mean(z$MeanDifference) else sum(z$SumDifference)/sum(z$Records)
 bootstrap_sensitivity[[length(bootstrap_sensitivity)+1]]<-data.frame(EvalWeighting=ew,Seed=seed,Replicates=20000,Difference=point,SE=sd(vals),P=2*pnorm(-abs(point/sd(vals))),Purpose="numerical_bootstrap_stability_only_not_new_CV")
}
write.csv(do.call(rbind,bootstrap_sensitivity),file.path(out,"bootstrap_numerical_stability_audit.csv"),row.names=FALSE)
jsonlite::write_json(list(status="PASS",v2_original_rows=42,v2_historical_schemeA_source_discrepancy_rows=sum(abs(historical_difference$SourceOOF_P-historical_difference$CorrectionTable_P)>1e-10),v2_original_max_abs_error=old_err,v34_model_rows=48,v34_training_rows=32,method_attribution_rows=nrow(cf),production_bootstrap=V3_COMPARISON_BOOTSTRAP,production_seed=V3_SEED,new_mcmc_fits=0,source_results_modified=FALSE,notes="Counterfactual recalculations are explanatory; original configured analysis and all published results remain unchanged."),file.path(out,"recomputation_status.json"),pretty=TRUE,auto_unbox=TRUE,digits=16)
print(cf[cf$Route=="joint_bb"&cf$Model=="M3",c("Version","Design","EvalWeighting","Inference","Difference","SE","P","ScaledDifference","ScaledSE")],row.names=FALSE)
cat("P_VALUE_RECONCILIATION_PASS; saved results only; no MCMC\n")
