args<-commandArgs(TRUE);out<-args[1];root<-args[2]
source(file.path(root,"R/bootstrap.R"));load_v3_modules(root);source(file.path(out,"supplement_functions.R"))
checks<-list();ok<-function(name,pass){checks[[length(checks)+1]]<<-data.frame(Check=name,Pass=isTRUE(pass));if(!isTRUE(pass))stop(name)}
d<-data.frame(Species=c("a","a","b","b","c"),ObservedHigh=c(1,0,1,1,0),PredictedPrHigh=c(.2,.2,.8,.8,.5))
m<-auc_species_stats(d)
ok("hand-computed record AUC",abs(auc_from_cluster_counts(m,rep(1,3),"record_equal")-.75)<1e-14)
ok("hand-computed species AUC",abs(auc_from_cluster_counts(m,rep(1,3),"species_equal")-13/18)<1e-14)
expanded<-do.call(rbind,lapply(seq_along(m$species),function(i){n<-c(2,1,1)[i];do.call(rbind,lapply(seq_len(n),function(j){z<-d[d$Species==m$species[i],];z$Species<-paste0(z$Species,"_copy",j);z}))}))
for(ew in V3_EVAL_WEIGHTINGS){
 w<-build_eval_weights(expanded[,"Species",drop=FALSE],ew)$weight
 ok(paste("AUC duplicated species copies",ew),abs(weighted_auc(expanded$ObservedHigh,expanded$PredictedPrHigh,w)-auc_from_cluster_counts(m,c(2,1,1),ew))<1e-14)
 shuffled<-d[c(5,2,4,1,3),];ok(paste("AUC row-order invariance",ew),identical(auc_species_stats(shuffled),m))
}
null<-d;null$PredictedPrHigh[]<-.7;nm<-auc_species_stats(null);ok("tied scores AUC 0.5",abs(auc_from_cluster_counts(nm,c(3,1,2),"species_equal")-.5)<1e-14)
ms<-auc_species_stats(rbind(d,transform(d,Species=paste0(Species,"x"))))
cc<-auc_stratified_counts(ms,100,7301);ok("bootstrap strata counts fixed",all(vapply(unique(ms$type),function(t)all(colSums(cc[ms$type==t,,drop=FALSE])==sum(ms$type==t)),logical(1))))
ok("bootstrap seeded reproducibility",identical(cc,auc_stratified_counts(ms,100,7301)))
ok("no undefined-fold dropping",inherits(try(auc_from_cluster_counts(m,c(0,1,0),"record_equal"),silent=TRUE),"try-error"))
e<-data.frame(Species=c("a","b"),Type="exact",ObservedPoint=c(0,0),Model=c(0,1),Null=c(.5,.5))
em<-error_species_stats(e,c("Model","Null"));vals<-error_metrics_from_counts(em,c(1,1),"record_equal")
ok("MAE equality counterexample",abs(diff(vals$MAE[1,]))<1e-14)
ok("RMSE uses sqrt global MSE not MAE",abs(vals$RMSE[1,1]-sqrt(.5))<1e-14&&abs(vals$RMSE[1,2]-.5)<1e-14)
x<-data.frame(Species=c("a","a","b","c","c","c"),Type=c("count","exact","exact","count","count","exact"),ObservedPoint=c(0,.1,.8,.2,.3,1),Model=c(.2,.2,.7,.4,.4,.8),Null=.5)
xm<-error_species_stats(x,c("Model","Null"))
for(ew in V3_EVAL_WEIGHTINGS){
 v<-error_metrics_from_counts(xm,rep(1,3),ew);w<-build_eval_weights(x[,"Species",drop=FALSE],ew)$weight
 ok(paste("MAE direct weighted identity",ew),abs(v$MAE[1,1]-weighted_mae(x$ObservedPoint,x$Model,w))<1e-14)
 ok(paste("RMSE direct weighted identity",ew),abs(v$RMSE[1,1]-weighted_rmse(x$ObservedPoint,x$Model,w))<1e-14)
}
z<-normal_bootstrap_test(.5,.5,rep(.5,20),TRUE);ok("structural Null P is 1",z$P_approx==1&&z$SE_approx==0)
z<-normal_bootstrap_test(.8,.5,rep(.8,20));ok("non-null zero variance cannot imply P=0",is.na(z$P_approx)&&z$TestStatus=="DEGENERATE_CLUSTER_BOOTSTRAP")
write.csv(do.call(rbind,checks),file.path(out,"deterministic_checks.csv"),row.names=FALSE)
cat("SUPPLEMENT_DETERMINISTIC_PASS",length(checks),"checks\n")
