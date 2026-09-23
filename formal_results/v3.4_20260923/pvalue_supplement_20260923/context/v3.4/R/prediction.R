posterior_quantiles <- function(draws,probs=c(.025,.5,.975)) {
  draws<-as.matrix(draws)
  if(!nrow(draws)||!ncol(draws)||any(!is.finite(draws)))stop("Invalid posterior draws")
  matrix(apply(draws,2,stats::quantile,probs=probs,names=FALSE),nrow=length(probs),ncol=ncol(draws))
}
extract_parameters_v3 <- function(bundle) {
  if(!is.null(bundle$posterior))return(bundle$posterior)
  if(bundle$route=="binary") {
    b<-brms::fixef(bundle$fit,summary=FALSE)
    list(alpha=as.numeric(b[,"Intercept"]),beta=b[,bundle$blueprint$columns,drop=FALSE])
  } else {
    p<-rstan::extract(bundle$fit,pars=c("alpha","beta","rho","log_phi_count","log_phi_ratio"),permuted=TRUE)
    p$beta<-if(length(bundle$blueprint$columns))matrix(p$beta,nrow=length(p$alpha),ncol=length(bundle$blueprint$columns)) else matrix(numeric(),nrow=length(p$alpha),ncol=0L);p
  }
}
null_projection_draws <- function(alpha,n_species) matrix(rep(plogis(alpha),times=n_species),nrow=length(alpha),ncol=n_species)
project_parameters_v3 <- function(pars,x) {
  if(!ncol(x))return(null_projection_draws(pars$alpha,nrow(x)))
  if(ncol(x)!=ncol(pars$beta))stop("Projection dimension mismatch")
  plogis(sweep(pars$beta%*%t(x),1,pars$alpha,"+"))
}
joint_projection_draws <- function(bundle,x_new) project_parameters_v3(extract_parameters_v3(bundle),x_new)
binary_prediction_draws <- function(bundle,state,species=state$encoded$Species) {
  idx<-match(species,state$encoded$Species);if(anyNA(idx))stop("Unknown species for projection")
  x<-design_from_blueprint(state$encoded[idx,,drop=FALSE],bundle$blueprint)
  project_parameters_v3(extract_parameters_v3(bundle),x)
}
joint_expected_draws <- binary_prediction_draws
report_quantile_v3 <- function(u,m,rho,phi) {
  atom<-rho*m; mu<-m*(1-rho)/(1-atom)
  if(any(!is.finite(mu))||any(mu<=0|mu>=1)||any(!is.finite(phi)|phi<=0))stop("Invalid report distribution parameters")
  continuous<-u<1-atom;ans<-rep(1,length(m))
  ans[continuous]<-qbeta(u[continuous]/(1-atom[continuous]),phi[continuous]*mu[continuous],phi[continuous]*(1-mu[continuous]))
  ans
}
joint_predictive_draws <- function(bundle,state,species=state$encoded$Species,seed=V3_SEED) {
  m<-joint_expected_draws(bundle,state,species);p<-extract_parameters_v3(bundle)
  set.seed(seed);u<-runif(nrow(m));out<-m
  for(i in seq_len(ncol(m)))out[,i]<-report_quantile_v3(u,m[,i],p$rho,exp(p$log_phi_ratio))
  out
}
joint_record_predictive_draws <- function(bundle,state,rows,seed=V3_SEED) {
  obs<-state$observations[rows,,drop=FALSE];m<-joint_expected_draws(bundle,state,obs$Species);p<-extract_parameters_v3(bundle)
  out<-m;set.seed(seed)
  for(i in seq_len(nrow(obs))) {
    if(obs$Type[i]=="count") {
      phi<-exp(p$log_phi_count);latent<-rbeta(nrow(m),phi*m[,i],phi*(1-m[,i]))
      out[,i]<-rbinom(nrow(m),obs$Total[i],latent)/obs$Total[i]
    } else out[,i]<-report_quantile_v3(runif(nrow(m)),m[,i],p$rho,exp(p$log_phi_ratio))
  }
  if(any(!is.finite(out)))stop("Nonfinite record predictive draws")
  out
}
summarize_prediction_draws <- function(draws,predictive_draws=NULL) {
  q<-posterior_quantiles(draws)
  ans<-data.frame(Point=colMeans(draws),PosteriorMedian=q[2,],CrI_lower=q[1,],CrI_upper=q[3,],PI_lower=NA_real_,PI_upper=NA_real_)
  if(!is.null(predictive_draws)){qp<-posterior_quantiles(predictive_draws);ans$PI_lower<-qp[1,];ans$PI_upper<-qp[3,]}
  ans
}
validate_prediction_table_v3 <- function(x) {
  keys<-c("Species","Route","Model","TrainWeighting")
  if(!nrow(x)||anyDuplicated(x[,keys]))stop("Prediction keys are not unique")
  for(n in c("Point","CrI_lower","CrI_upper"))if(any(!is.finite(x[[n]]))||any(x[[n]]<0|x[[n]]>1))stop("Invalid prediction column: ",n)
  j<-x$Route=="joint_bb"
  if(any(!is.finite(x$PI_lower[j]))||any(!is.finite(x$PI_upper[j]))||any(x$PI_lower[j]<0|x$PI_upper[j]>1)||any(x$PI_lower[j]>x$PI_upper[j]))stop("Invalid joint PI")
  if(any(x$CrI_lower>x$CrI_upper))stop("Invalid CrI")
  invisible(TRUE)
}
external_prediction_table <- function(state,bundles,new_sites,output_path=NULL,models=V3_MODELS,train_weightings=V3_TRAIN_WEIGHTINGS,allow_diagnostic_warnings=FALSE) {
  new_sites<-validate_sites_panel(new_sites);enc<-encode_panel(new_sites,state$dictionary)$data;rows<-list()
  for(tw in train_weightings)for(model in models)for(route in V3_ROUTES) {
    b<-bundles[[paste(route,model,tw,sep="|")]]
    if(is.null(b))stop("Missing prediction bundle")
    if(!is.null(b$fit))validate_bundle_for_use(b,require_pass=!allow_diagnostic_warnings,allow_failed=allow_diagnostic_warnings)
    x<-design_from_blueprint(enc,b$blueprint);pars<-extract_parameters_v3(b);m<-project_parameters_v3(pars,x)
    pi<-NULL
    if(route=="joint_bb") {
      set.seed(V3_SEED);u<-runif(nrow(m));pi<-m
      for(i in seq_len(ncol(m)))pi[,i]<-report_quantile_v3(u,m[,i],pars$rho,exp(pars$log_phi_ratio))
    }
    ss<-list(encoded=enc,sites=new_sites,blueprints=setNames(list(b$blueprint),blueprint_key(route,model)))
    status<-assess_applicability(ss,model,route,training_species=b$train_species)
    z<-cbind(data.frame(Species=new_sites$Species,Route=route,Model=model,TrainWeighting=tw),summarize_prediction_draws(m,pi),status[,setdiff(names(status),c("Species","Model","Route")),drop=FALSE])
    z$PredictionTarget<-if(route=="binary")"Pr_HIGH" else "mean_ratio_and_future_exact_report_PI"
    rows[[length(rows)+1]]<-z
  }
  ans<-do.call(rbind,rows);rownames(ans)<-NULL;validate_prediction_table_v3(ans)
  if(!is.null(output_path))write_csv_atomic(ans,output_path);ans
}
make_prediction_table <- function(state,bundles,output_path=NULL) external_prediction_table(state,bundles,state$sites,output_path)
binary_record_scores <- function(bundle,state,held_rows) {
  obs<-state$observations[held_rows,,drop=FALSE];if(anyNA(obs$High))stop("Unclassified binary scoring record")
  m<-binary_prediction_draws(bundle,state,obs$Species);p<-colMeans(m)
  ll<-vapply(seq_len(nrow(obs)),function(i)log_mean_exp(if(obs$High[i]==1)log(m[,i]) else log1p(-m[,i])),numeric(1))
  data.frame(RecordID=obs$RecordID,ExperimentID=obs$ExperimentID,SourceID=obs$SourceID,Species=obs$Species,Type=obs$Type,
    ObservedHigh=obs$High,ObservedPoint=NA_real_,PredictedPrHigh=p,PredictedPoint=NA_real_,
    PredictedPI_lower=NA_real_,PredictedPI_upper=NA_real_,PIWidth=NA_real_,IntervalCovered=NA,
    IntervalOverlap=NA,PIObservationModel="not_applicable",LogPredictiveDensityRaw=ll,OriginalRow=held_rows)
}
joint_record_scores <- function(bundle,state,held_rows) {
  obs<-state$observations[held_rows,,drop=FALSE]
  ll<-rstan::extract(bundle$fit,pars="log_lik",permuted=TRUE)$log_lik
  m<-joint_expected_draws(bundle,state,obs$Species);rep<-joint_record_predictive_draws(bundle,state,held_rows,seed=V3_SEED+sum(held_rows))
  q<-posterior_quantiles(rep);count<-obs$Type=="count";exact<-obs$Type=="exact";interval<-obs$Type=="interval"
  y<-rep(NA_real_,nrow(obs));y[count]<-obs$Events[count]/obs$Total[count];y[exact]<-obs$Exact[exact]
  cover<-rep(NA,nrow(obs));cover[!interval]<-y[!interval]>=q[1,!interval]&y[!interval]<=q[3,!interval]
  overlap<-rep(NA,nrow(obs));overlap[interval]<-obs$Upper[interval]>=q[1,interval]&obs$Lower[interval]<=q[3,interval]
  data.frame(RecordID=obs$RecordID,ExperimentID=obs$ExperimentID,SourceID=obs$SourceID,Species=obs$Species,Type=obs$Type,
    ObservedHigh=obs$High,ObservedPoint=y,PredictedPrHigh=NA_real_,PredictedPoint=colMeans(m),
    PredictedPI_lower=q[1,],PredictedPI_upper=q[3,],PIWidth=q[3,]-q[1,],IntervalCovered=cover,IntervalOverlap=overlap,
    PIObservationModel=ifelse(count,"beta_binomial_at_observed_Total","one_inflated_beta_report"),
    LogPredictiveDensityRaw=vapply(held_rows,function(i)log_mean_exp(ll[,i]),numeric(1)),OriginalRow=held_rows)
}
