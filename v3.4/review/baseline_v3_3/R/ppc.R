ppc_stat_v3 <- function(x,w,stat) {
  if(stat=="Mean")return(sum(x*w)/sum(w))
  if(stat=="ZeroFraction")return(sum((x==0)*w)/sum(w))
  if(stat=="OneFraction")return(sum((x==1)*w)/sum(w))
  mu<-sum(x*w)/sum(w);sqrt(sum(w*(x-mu)^2)/sum(w))
}
ppc_summary_for_bundle_v3 <- function(bundle,state) {
  rows<-bundle$request$train_rows;obs<-state$observations[rows,,drop=FALSE]
  if(bundle$route=="binary") {
    m<-binary_prediction_draws(bundle,state,obs$Species);set.seed(V3_SEED)
    sim<-matrix(rbinom(length(m),1,as.numeric(m)),nrow=nrow(m));y<-obs$High;sets<-list(classified=seq_len(nrow(obs)))
  } else {
    sim<-joint_record_predictive_draws(bundle,state,rows,seed=V3_SEED)
    y<-rep(NA_real_,nrow(obs));co<-obs$Type=="count";ex<-obs$Type=="exact"
    y[co]<-obs$Events[co]/obs$Total[co];y[ex]<-obs$Exact[ex]
    sets<-list(count=which(co),exact=which(ex),all_point=which(co|ex))
  }
  out<-list()
  for(subset in names(sets)) {
    ix<-sets[[subset]];if(!length(ix))next
    for(ew in V3_EVAL_WEIGHTINGS) {
      w<-build_eval_weights(obs[ix,"Species",drop=FALSE],ew)$weight
      for(st in c("Mean","SD","ZeroFraction","OneFraction")) {
        observed<-ppc_stat_v3(y[ix],w,st)
        replicated<-apply(sim[,ix,drop=FALSE],1,ppc_stat_v3,w=w,stat=st)
        q<-quantile(replicated,c(.025,.5,.975),names=FALSE)
        out[[length(out)+1]]<-data.frame(Route=bundle$route,Model=bundle$model,TrainWeighting=bundle$train_weighting,EvalWeighting=ew,
          Subset=subset,Statistic=st,Records=length(ix),Species=length(unique(obs$Species[ix])),Observed=observed,
          PPC_Lower95=q[1],PPC_Median=q[2],PPC_Upper95=q[3],Status=if(observed<q[1]||observed>q[3])"REVIEW_REQUIRED" else "OK",
          Scope="training_only_same_records_types_weights; intervals_not_imputed")
      }
    }
  }
  do.call(rbind,out)
}
run_ppc_stage_v3 <- function(state,bundles,root,result_dir) {
  x<-do.call(rbind,lapply(bundles,ppc_summary_for_bundle_v3,state=state));rownames(x)<-NULL
  write_csv_atomic(x,file.path(result_dir,"training_ppc_summary.csv"))
  dir.create(file.path(root,"figures"),showWarnings=FALSE,recursive=TRUE)
  pdf(file.path(root,"figures","training_ppc_summary.pdf"),width=12,height=8);on.exit(dev.off(),add=TRUE)
  for(st in unique(x$Statistic))for(sub in unique(x$Subset)) {
    z<-x[x$Statistic==st&x$Subset==sub,,drop=FALSE];if(!nrow(z))next
    par(mar=c(9,4,3,1));xx<-seq_len(nrow(z));ylim<-range(c(z$Observed,z$PPC_Lower95,z$PPC_Upper95));if(diff(ylim)==0)ylim<-ylim+c(-.01,.01)
    plot(xx,z$Observed,ylim=ylim,xaxt="n",pch=19,col=ifelse(z$Status=="OK","black","#b64c22"),main=paste("Training PPC",sub,st),xlab="",ylab=st)
    segments(xx,z$PPC_Lower95,xx,z$PPC_Upper95,col="grey50");axis(1,xx,paste(z$Model,z$TrainWeighting,z$EvalWeighting,sep=" / "),las=2,cex.axis=.6)
  };x
}
