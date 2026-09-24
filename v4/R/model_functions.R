# Fitting and predictions: record weights fixed at one; original observation model retained.
binary_training_data <- function(state, model, train_species) {
  obs <- state$observations
  keep <- obs$Species %in% train_species & !is.na(obs$High)
  dat <- obs[keep, c("RecordID", "Species", "High"), drop = FALSE]
  if (!nrow(dat)) stop("No classified training records for binary fit")
  bp <- state$blueprints[[blueprint_key("binary", model)]]
  idx <- match(dat$Species, state$encoded$Species)
  x <- as.data.frame(bp$X[idx, , drop = FALSE])
  if (ncol(x)) names(x) <- bp$columns
  dat <- cbind(dat, x)
  dat$TrainWeight <- rep(1, nrow(dat))
  dat$High <- as.integer(dat$High)
  dat
}

joint_training_data <- function(state, model, train_species) {
  obs <- state$observations
  n <- nrow(obs); sid <- match(obs$Species, state$encoded$Species)
  train_rows <- which(obs$Species %in% train_species & obs$Informative)
  if (!length(train_rows)) stop("No informative training records for joint fit")
  train_weight <- numeric(n); train_weight[train_rows] <- 1
  kind <- match(obs$Type, c("count", "exact", "interval")); kind[is.na(kind)] <- 3L
  events <- rep(0L, n); total <- rep(1L, n); exact <- rep(0, n)
  lower <- rep(0, n); upper <- rep(1, n)
  count <- obs$Type == "count"; exact_i <- obs$Type == "exact"; interval <- obs$Type == "interval"
  events[count] <- as.integer(obs$Events[count]); total[count] <- as.integer(obs$Total[count])
  exact[exact_i] <- obs$Exact[exact_i]
  lower[interval] <- obs$Lower[interval]; upper[interval] <- obs$Upper[interval]
  bp <- state$blueprints[[blueprint_key("joint_bb", model)]]
  X <- bp$X
  list(S = nrow(state$encoded), K = ncol(X), N = n, X = X,
       train = as.integer(train_weight > 0), train_weight = train_weight,
       kind = as.integer(kind), events = events, total = total,
       exact_ratio = as.numeric(exact), lower_ratio = as.numeric(lower),
       upper_ratio = as.numeric(upper), species_id = as.integer(sid),
       prior_intercept_sd = PRIORS$intercept, prior_beta_sd = PRIORS$beta,
       prior_rho_a = PRIORS$rho_a, prior_rho_b = PRIORS$rho_b,
       prior_log_phi_mean = PRIORS$log_phi_mean,
       prior_log_phi_sd = PRIORS$log_phi_sd,
       train_rows = train_rows)
}



# A request binds a cache to the actual data, design, model, priors and sampler.
fit_spec <- function(state,route,model,train_species,stan_path,sampling=SAMPLING,seed=SEED) {
  if(!route%in%ROUTES||!model%in%MODELS||!length(train_species)||
     anyNA(train_species)||anyDuplicated(train_species))stop("Invalid fit request")
  active<-if(route=="binary")state$binary_species else state$joint_species
  if(any(!train_species%in%active))stop("Unknown training species")
  sampling<-validate_sampling(sampling)
  state$blueprints[[blueprint_key(route,model)]]<-make_design_blueprint(state$encoded,train_species,model)
  bp<-state$blueprints[[blueprint_key(route,model)]]
  if(route=="binary") {
    dat<-binary_training_data(state,model,train_species)
    form<-brms::bf(stats::as.formula(paste("High | weights(TrainWeight, scale = FALSE) ~",
                         paste(c("1",bp$columns),collapse=" + "))),center=FALSE)
    prior<-brms::set_prior(sprintf("normal(0,%g)",PRIORS$intercept),class="b",coef="Intercept")
    if(length(bp$columns))prior<-c(prior,brms::set_prior(sprintf("normal(0,%g)",PRIORS$beta),class="b"))
    code<-as.character(brms::make_stancode(form,data=dat,family=brms::bernoulli(),prior=prior,
                                          save_pars=brms::save_pars(all=TRUE)))
    rows<-which(state$observations$RecordID%in%dat$RecordID)
  } else {
    dat<-joint_training_data(state,model,train_species);rows<-dat$train_rows
    code<-paste(readLines(stan_path,warn=FALSE),collapse="\n");form<-prior<-NULL
  }
  req<-list(version=VERSION,route=route,model=model,train_weighting=TRAIN_WEIGHTING,
    train_rows=rows,training_species=sort(unique(state$observations$Species[rows])),
    input_hashes=state$input_hashes,data_hash=sha256_object(dat),blueprint_hash=sha256_object(bp),
    code_hash=sha256_object(code),priors=PRIORS,sampling=sampling,seed=as.integer(seed),
    R_version=as.character(getRversion()),
    packages=vapply(c("brms","rstan","posterior"),function(p)as.character(packageVersion(p)),character(1)))
  list(state=state,blueprint=bp,data=dat,code=code,formula=form,prior=prior,
       request=req,key=sha256_object(req))
}
binary_template_key <- function(spec) sha256_object(list(spec$code,spec$request$model,spec$blueprint$columns))
.compiled_models <- new.env(parent=emptyenv())
.binary_templates <- new.env(parent=emptyenv())
validate_fit_cache <- function(bundle,spec) {
  req<-spec$request
  if(!is.list(bundle)||!identical(bundle$request,req)||!identical(bundle$key,spec$key)||
     !identical(bundle$key,sha256_object(req))||!identical(bundle$data,spec$data)||
     !identical(bundle$blueprint,spec$blueprint)||!identical(bundle$code,spec$code)||
     !identical(bundle$train_species,req$training_species)||!identical(bundle$route,req$route)||
     !identical(bundle$model,req$model)||!identical(bundle$train_weighting,TRAIN_WEIGHTING))stop("Fit cache identity mismatch")
  expected_class<-if(req$route=="binary")"brmsfit" else "stanfit"
  if(!inherits(bundle$fit,expected_class)||!identical(bundle$payload_hash,fit_payload_hash(bundle$fit)))
    stop("Fit cache payload mismatch")
  st<-if(req$route=="binary")bundle$fit$fit else bundle$fit
  if(trimws(rstan::get_stancode(st))!=trimws(spec$code))stop("Actual fitted code mismatch")
  ctl<-req$sampling
  if(length(st@stan_args)!=ctl$chains)stop("Cached chain count mismatch")
  for(a in st@stan_args)if(as.integer(a$iter)!=ctl$iter||as.integer(a$warmup)!=ctl$warmup||
    as.integer(a$seed)!=req$seed||a$control$adapt_delta!=ctl$adapt_delta||
    a$control$max_treedepth!=ctl$max_treedepth)stop("Actual cached sampler settings mismatch")
  if(req$route=="binary") {
    used<-c("High","TrainWeight",spec$blueprint$columns)
    if(!isTRUE(all.equal(as.data.frame(bundle$fit$data[,used,drop=FALSE]),spec$data[,used,drop=FALSE],
                        check.attributes=FALSE)))stop("Actual binary training data mismatch")
  }
  invisible(TRUE)
}
fit_from_spec <- function(spec,path) {
  req<-spec$request;ctl<-req$sampling
  if(file.exists(path)) {
    b<-readRDS(path);validate_fit_cache(b,spec)
    b$diagnostics<-if(req$route=="binary")diagnose_brms_fit(b$fit,ctl$max_treedepth) else diagnose_rstan_fit(b$fit,ctl$max_treedepth)
    if(req$route=="binary")assign(binary_template_key(spec),b$fit,.binary_templates)
    else assign(sha256_object(spec$code),b$fit@stanmodel,.compiled_models)
    cat("CACHE_VALID",req$route,req$model,"\n");return(b)
  }
  cat("FIT_START",req$route,req$model,"seed",req$seed,"\n");flush.console()
  control<-list(adapt_delta=ctl$adapt_delta,max_treedepth=ctl$max_treedepth)
  if(req$route=="binary") {
    key<-binary_template_key(spec)
    if(exists(key,.binary_templates,inherits=FALSE))
      fit<-stats::update(get(key,.binary_templates),newdata=spec$data,recompile=FALSE,
        seed=req$seed,chains=ctl$chains,cores=ctl$cores,iter=ctl$iter,warmup=ctl$warmup,control=control,refresh=50)
    else {
      fit<-brms::brm(spec$formula,data=spec$data,family=brms::bernoulli(),prior=spec$prior,
        save_pars=brms::save_pars(all=TRUE),backend="rstan",seed=req$seed,chains=ctl$chains,
        cores=ctl$cores,iter=ctl$iter,warmup=ctl$warmup,control=control,refresh=50,silent=2)
      assign(key,fit,.binary_templates)
    }
    diagnostics<-diagnose_brms_fit(fit,ctl$max_treedepth)
  } else {
    key<-sha256_object(spec$code)
    if(!exists(key,.compiled_models,inherits=FALSE))
      assign(key,rstan::stan_model(model_code=spec$code,model_name="ratio_v4_joint"),.compiled_models)
    fit<-rstan::sampling(get(key,.compiled_models),data=spec$data[setdiff(names(spec$data),"train_rows")],
      seed=req$seed,chains=ctl$chains,cores=ctl$cores,iter=ctl$iter,warmup=ctl$warmup,control=control,refresh=50)
    diagnostics<-diagnose_rstan_fit(fit,ctl$max_treedepth)
  }
  b<-list(version=VERSION,key=spec$key,request=req,route=req$route,model=req$model,
    train_weighting=TRAIN_WEIGHTING,train_species=req$training_species,blueprint=spec$blueprint,
    data=spec$data,fit=fit,code=spec$code,diagnostics=diagnostics,payload_hash=fit_payload_hash(fit))
  save_rds_atomic(b,path);cat("FIT_END",req$route,req$model,diagnostics$Status,"\n");b
}

fit_payload_hash <- function(fit) {
  st<-if(inherits(fit,"brmsfit"))fit$fit else fit
  if(!inherits(st,"stanfit"))stop("Invalid Stan fit payload")
  args<-lapply(st@stan_args,function(a)list(seed=as.character(a$seed),iter=as.integer(a$iter),warmup=as.integer(a$warmup),chain_id=as.integer(a$chain_id),adapt_delta=as.numeric(a$control$adapt_delta),max_treedepth=as.integer(a$control$max_treedepth)))
  dat<-if(inherits(fit,"brmsfit"))lapply(fit$data,function(x){if(is.factor(x))x<-as.character(x);unname(x)}) else NULL
  sha256_object(list(draws=as.array(st),sampler=lapply(rstan::get_sampler_params(st,inc_warmup=FALSE),unname),args=args,code=trimws(rstan::get_stancode(st)),data=dat))
}

log_mean_exp <- function(x) {
  if (!length(x) || anyNA(x)) stop("Empty or NA log draws")
  if (any(is.nan(x)) || any(is.infinite(x) & x > 0)) stop("log_mean_exp received invalid positive/NaN values")
  if (all(is.infinite(x) & x < 0)) return(-Inf)
  finite <- is.finite(x)
  m <- max(x[finite])
  m + log(mean(exp(x - m)))
}


posterior_quantiles <- function(draws,probs=c(.025,.5,.975)) {
  draws<-as.matrix(draws)
  if(!nrow(draws)||!ncol(draws)||any(!is.finite(draws)))stop("Invalid posterior draws")
  matrix(apply(draws,2,stats::quantile,probs=probs,names=FALSE),nrow=length(probs),ncol=ncol(draws))
}
extract_parameters <- function(bundle) {
  if(bundle$route=="binary") {
    b<-brms::fixef(bundle$fit,summary=FALSE)
    list(alpha=as.numeric(b[,"Intercept"]),beta=b[,bundle$blueprint$columns,drop=FALSE])
  } else {
    p<-rstan::extract(bundle$fit,pars=c("alpha","beta","rho","log_phi_count","log_phi_ratio"),permuted=TRUE)
    p$beta<-if(length(bundle$blueprint$columns))matrix(p$beta,nrow=length(p$alpha),ncol=length(bundle$blueprint$columns)) else matrix(numeric(),nrow=length(p$alpha),ncol=0L);p
  }
}
null_projection_draws <- function(alpha,n_species) matrix(rep(plogis(alpha),times=n_species),nrow=length(alpha),ncol=n_species)
project_parameters <- function(pars,x) {
  if(!ncol(x))return(null_projection_draws(pars$alpha,nrow(x)))
  if(ncol(x)!=ncol(pars$beta))stop("Projection dimension mismatch")
  plogis(sweep(pars$beta%*%t(x),1,pars$alpha,"+"))
}
joint_projection_draws <- function(bundle,x_new) project_parameters(extract_parameters(bundle),x_new)
binary_prediction_draws <- function(bundle,state,species=state$encoded$Species) {
  idx<-match(species,state$encoded$Species);if(anyNA(idx))stop("Unknown species for projection")
  x<-design_from_blueprint(state$encoded[idx,,drop=FALSE],bundle$blueprint)
  project_parameters(extract_parameters(bundle),x)
}
joint_expected_draws <- binary_prediction_draws
report_quantile <- function(u,m,rho,phi) {
  atom<-rho*m; mu<-m*(1-rho)/(1-atom)
  if(any(!is.finite(mu))||any(mu<=0|mu>=1)||any(!is.finite(phi)|phi<=0))stop("Invalid report distribution parameters")
  continuous<-u<1-atom;ans<-rep(1,length(m))
  ans[continuous]<-qbeta(u[continuous]/(1-atom[continuous]),phi[continuous]*mu[continuous],phi[continuous]*(1-mu[continuous]))
  ans
}
joint_predictive_draws <- function(bundle,state,species=state$encoded$Species,seed=SEED) {
  m<-joint_expected_draws(bundle,state,species);p<-extract_parameters(bundle)
  set.seed(seed);u<-runif(nrow(m));out<-m
  for(i in seq_len(ncol(m)))out[,i]<-report_quantile(u,m[,i],p$rho,exp(p$log_phi_ratio))
  out
}
joint_record_predictive_draws <- function(bundle,state,rows,seed=SEED) {
  obs<-state$observations[rows,,drop=FALSE];m<-joint_expected_draws(bundle,state,obs$Species);p<-extract_parameters(bundle)
  out<-m;set.seed(seed)
  for(i in seq_len(nrow(obs))) {
    if(obs$Type[i]=="count") {
      phi<-exp(p$log_phi_count);latent<-rbeta(nrow(m),phi*m[,i],phi*(1-m[,i]))
      out[,i]<-rbinom(nrow(m),obs$Total[i],latent)/obs$Total[i]
    } else out[,i]<-report_quantile(runif(nrow(m)),m[,i],p$rho,exp(p$log_phi_ratio))
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
  m<-joint_expected_draws(bundle,state,obs$Species);rep<-joint_record_predictive_draws(bundle,state,held_rows,seed=SEED+sum(held_rows))
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

applicability_status <- function(has_response = FALSE, missing_predictor = FALSE,
                                 unseen_category = FALSE, unseen_combination = FALSE,
                                 fixed_effect_estimable = TRUE,
                                 site151_outside_domain = FALSE,
                                 unseen_raw_residue = FALSE) {
  codes <- character()
  if (isTRUE(missing_predictor)) codes <- c(codes, "missing_predictor")
  if (isTRUE(unseen_category)) codes <- c(codes, "unseen_category")
  if (isTRUE(unseen_raw_residue)) codes <- c(codes, "unseen_raw_residue")
  if (isTRUE(unseen_combination)) codes <- c(codes, "unseen_combination")
  if (!isTRUE(fixed_effect_estimable)) codes <- c(codes, "fixed_effect_not_estimable")
  if (isTRUE(site151_outside_domain)) codes <- c(codes, "site151_outside_training_domain")
  status <- if (!isTRUE(has_response)) "unlabelled_projection" else if (length(codes)) "review_required" else "supported"
  list(ApplicabilityStatus = status, WarningCodes = codes)
}

assess_applicability <- function(state, model, route = "joint_bb", training_species = NULL) {
  bp <- state$blueprints[[blueprint_key(route, model)]]
  if (is.null(bp)) stop("Blueprint not found")
  encoded <- state$encoded
  response <- training_species %||% if (route == "binary") state$binary_species else state$joint_species
  vars <- bp$variables
  rows <- vector("list", nrow(encoded))
  for (i in seq_len(nrow(encoded))) {
    vals <- if (length(vars)) encoded[i, vars, drop = FALSE] else encoded[i, , drop = FALSE]
    raw_all <- setNames(vapply(SITE_COLUMNS, function(site) normalize_residue(state$sites[[site]][[i]]), character(1)), SITE_COLUMNS)
    missing_input <- any(raw_all == "MISSING")
    missing_pred <- length(vars) > 0 && any(vapply(vals, function(x) identical(as.character(x), "MISSING"), logical(1)))
    unseen_cat <- length(vars) > 0 && any(vapply(seq_along(vars), function(j) {
      site <- sub(paste0("^", model, "_"), "", vars[[j]])
      !as.character(encoded[[vars[[j]]]][i]) %in% bp$seen[[site]]
    }, logical(1)))
    unseen_raw <- length(vars) > 0 && any(vapply(sub(paste0("^", model, "_"), "", vars), function(site) {
      !raw_all[[site]] %in% bp$raw_seen[[site]]
    }, logical(1)))
    combo <- if (length(vars)) do.call(paste, c(encoded[i, vars, drop = FALSE], sep = "|")) else "(intercept-only)"
    unseen_combo <- !combo %in% bp$training_combinations
    row_x <- design_from_blueprint(encoded[i, , drop = FALSE], bp)
    fixed_est <- row_in_span(bp$train_matrix, c(1, row_x))
    codes <- applicability_status(
      has_response = encoded$Species[[i]] %in% response,
      missing_predictor = missing_pred,
      unseen_category = unseen_cat,
      unseen_raw_residue = unseen_raw,
      unseen_combination = unseen_combo,
      fixed_effect_estimable = fixed_est,
      site151_outside_domain = normalize_residue(state$sites$Site151[[i]]) != "C"
    )
    rows[[i]] <- data.frame(Species = encoded$Species[[i]], Model = model, Route = route,
      HasResponseData = encoded$Species[[i]] %in% response,
      AnyMissingPredictorSite = missing_pred, UnseenEncodedCategory = unseen_cat,
      AnyMissingInputSite = missing_input, UnseenRawResidue = unseen_raw,
      CombinationSeenInTraining = !unseen_combo,
      FixedEffectEstimable = fixed_est,
      Site151OutsideTrainingDomain = normalize_residue(state$sites$Site151[[i]]) != "C",
      ApplicabilityStatus = codes$ApplicabilityStatus,
      WarningCodes = paste(codes$WarningCodes, collapse = ";"), stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

ppc_stat <- function(x,w,stat) {
  if(stat=="Mean")return(sum(x*w)/sum(w))
  if(stat=="ZeroFraction")return(sum((x==0)*w)/sum(w))
  if(stat=="OneFraction")return(sum((x==1)*w)/sum(w))
  mu<-sum(x*w)/sum(w);sqrt(sum(w*(x-mu)^2)/sum(w))
}
ppc_summary_for_bundle <- function(bundle,state) {
  rows<-bundle$request$train_rows;obs<-state$observations[rows,,drop=FALSE]
  if(bundle$route=="binary") {
    m<-binary_prediction_draws(bundle,state,obs$Species);set.seed(SEED)
    sim<-matrix(rbinom(length(m),1,as.numeric(m)),nrow=nrow(m));y<-obs$High;sets<-list(classified=seq_len(nrow(obs)))
  } else {
    sim<-joint_record_predictive_draws(bundle,state,rows,seed=SEED)
    y<-rep(NA_real_,nrow(obs));co<-obs$Type=="count";ex<-obs$Type=="exact"
    y[co]<-obs$Events[co]/obs$Total[co];y[ex]<-obs$Exact[ex]
    sets<-list(count=which(co),exact=which(ex),all_point=which(co|ex))
  }
  out<-list()
  for(subset in names(sets)) {
    ix<-sets[[subset]];if(!length(ix))next
    {
      ew <- EVAL_WEIGHTING
      w<-species_weights(obs$Species[ix])
      for(st in c("Mean","SD","ZeroFraction","OneFraction")) {
        observed<-ppc_stat(y[ix],w,st)
        replicated<-apply(sim[,ix,drop=FALSE],1,ppc_stat,w=w,stat=st)
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
