diagnostic_metrics_pass <- function(draws) {
  cols<-c("rhat","ess_bulk","ess_tail")
  if(!nrow(draws)||!all(cols%in%names(draws)))return(FALSE)
  v<-as.matrix(as.data.frame(draws)[,cols,drop=FALSE])
  all(is.finite(v)) && max(draws$rhat)<1.01 && min(draws$ess_bulk)>=400 && min(draws$ess_tail)>=400
}
diagnose_draws_v3 <- function(array, sp, max_treedepth) {
  summary<-posterior::summarise_draws(posterior::as_draws_array(array),"rhat","ess_bulk","ess_tail")
  divergences<-sum(vapply(sp,function(x)sum(x[,"divergent__"]),numeric(1)))
  hits<-sum(vapply(sp,function(x)sum(x[,"treedepth__"]>=max_treedepth),numeric(1)))
  ebfmi<-vapply(sp,function(x)mean(diff(x[,"energy__"])^2)/var(x[,"energy__"]),numeric(1))
  ok<-all(is.finite(array))&&diagnostic_metrics_pass(summary)&&length(sp)>0&&divergences==0&&hits==0&&all(is.finite(ebfmi))&&min(ebfmi)>.3
  data.frame(Status=if(ok)"PASS" else "FAILED_DIAGNOSTICS",MaxRhat=if(all(is.finite(summary$rhat)))max(summary$rhat) else NA_real_,MinBulkESS=if(all(is.finite(summary$ess_bulk)))min(summary$ess_bulk) else NA_real_,MinTailESS=if(all(is.finite(summary$ess_tail)))min(summary$ess_tail) else NA_real_,Divergences=divergences,TreeDepthHits=hits,MinEBFMI=if(length(ebfmi))min(ebfmi) else NA_real_,ParametersChecked=nrow(summary),DiagnosticScope="sampled_parameters_and_lp; deterministic_outputs_checked_separately")
}
diagnose_brms_fit_v3 <- function(fit,max_treedepth=V3_SAMPLING$max_treedepth) {
  a<-as.array(fit);vars<-dimnames(a)[[3]];keep<-grepl("^b_|^lp__$",vars)
  if(!any(keep))stop("No binary parameters in fit")
  diagnose_draws_v3(a[,,keep,drop=FALSE],rstan::get_sampler_params(fit$fit,inc_warmup=FALSE),max_treedepth)
}
diagnose_rstan_fit_v3 <- function(fit,max_treedepth=V3_SAMPLING$max_treedepth) {
  a<-as.array(fit);vars<-dimnames(a)[[3]]
  keep<-grepl("^(alpha|beta\\[|rho$|log_phi_ratio$|log_phi_count$|lp__$)",vars)
  if(!all(c("alpha","rho","log_phi_ratio","log_phi_count")%in%vars))stop("Missing joint parameters")
  diagnose_draws_v3(a[,,keep,drop=FALSE],rstan::get_sampler_params(fit,inc_warmup=FALSE),max_treedepth)
}
binary_training_data <- function(state, model, train_species, train_weighting) {
  obs <- state$observations
  keep <- obs$Species %in% train_species & !is.na(obs$High)
  dat <- obs[keep, c("RecordID", "Species", "High"), drop = FALSE]
  if (!nrow(dat)) stop("No classified training records for binary fit")
  bp <- state$blueprints[[blueprint_key("binary", model)]]
  idx <- match(dat$Species, state$encoded$Species)
  x <- as.data.frame(bp$X[idx, , drop = FALSE])
  if (ncol(x)) names(x) <- bp$columns
  dat <- cbind(dat, x)
  wf <- build_train_weights(dat[, "Species", drop = FALSE], train_weighting)
  dat$TrainWeight <- wf$weight
  dat$High <- as.integer(dat$High)
  dat
}

joint_stan_code <- function(stan_path) {
  if (!file.exists(stan_path)) stop("Stan source not found: ", stan_path)
  paste(readLines(stan_path, warn = FALSE), collapse = "\n")
}

joint_training_data <- function(state, model, train_species, train_weighting) {
  obs <- state$observations
  n <- nrow(obs); sid <- match(obs$Species, state$encoded$Species)
  train_rows <- which(obs$Species %in% train_species & obs$Informative)
  if (!length(train_rows)) stop("No informative training records for joint fit")
  wf <- build_train_weights(obs[train_rows, "Species", drop = FALSE], train_weighting)
  train_weight <- numeric(n); train_weight[train_rows] <- wf$weight
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
       prior_intercept_sd = V3_PRIORS$intercept, prior_beta_sd = V3_PRIORS$beta,
       prior_rho_a = V3_PRIORS$rho_a, prior_rho_b = V3_PRIORS$rho_b,
       prior_log_phi_mean = V3_PRIORS$log_phi_mean,
       prior_log_phi_sd = V3_PRIORS$log_phi_sd,
       train_rows = train_rows)
}


fit_spec_v3 <- function(state,route,model,train_species,tw,stan_path,sampling=V3_SAMPLING,seed=V3_SEED) {
  require_v3_packages(TRUE);sampling<-validate_sampling_v3(sampling)
  state$blueprints[[blueprint_key(route,model)]]<-make_design_blueprint(state$encoded,train_species,model)
  bp<-state$blueprints[[blueprint_key(route,model)]]
  if(route=="binary") {
    dat<-binary_training_data(state,model,train_species,tw)
    form<-brms::bf(stats::as.formula(paste("High | weights(TrainWeight, scale = FALSE) ~",paste(c("1",bp$columns),collapse=" + "))),center=FALSE)
    pri<-brms::set_prior(sprintf("normal(0,%g)",V3_PRIORS$intercept),class="b",coef="Intercept")
    if(length(bp$columns))pri<-c(pri,brms::set_prior(sprintf("normal(0,%g)",V3_PRIORS$beta),class="b"))
    code<-as.character(brms::make_stancode(form,data=dat,family=brms::bernoulli(),prior=pri,save_pars=brms::save_pars(all=TRUE)))
    rows<-which(state$observations$RecordID%in%dat$RecordID)
  } else {
    dat<-joint_training_data(state,model,train_species,tw);rows<-dat$train_rows;code<-joint_stan_code(stan_path);form<-pri<-NULL
  }
  request<-fit_identity(route,model,tw,rows,state,sha256_object(code),sampling=sampling,seed=seed)
  request$data_hash<-sha256_object(dat)
  list(state=state,blueprint=bp,data=dat,code=code,formula=form,prior=pri,request=request,key=identity_key(request))
}
fit_from_spec_v3 <- function(spec,out_path,force=FALSE) {
  req<-spec$request
  if(!force && cache_is_valid(out_path,req,req$route,req$model,req$train_weighting)) {
    b<-readRDS(out_path);b$diagnostics<-validate_fitted_bundle_v3(b,spec,require_pass=FALSE)
    if(req$route=="joint_bb") { if(!exists(".v31_compiled",.GlobalEnv,inherits=FALSE))assign(".v31_compiled",new.env(),.GlobalEnv);assign(sha256_object(spec$code),b$fit@stanmodel,get(".v31_compiled",.GlobalEnv)) }
    if(req$route=="binary") { if(!exists(".v31_binary_templates",.GlobalEnv,inherits=FALSE))assign(".v31_binary_templates",new.env(),.GlobalEnv);assign(sha256_object(spec$code),b$fit,get(".v31_binary_templates",.GlobalEnv)) }
    return(b)
  }
  ctl<-req$sampling
  cat("FIT_START",req$route,req$model,req$train_weighting,"seed",req$seed,"\n");flush.console()
  if(req$route=="binary") {
    if(!exists(".v31_binary_templates",.GlobalEnv,inherits=FALSE))assign(".v31_binary_templates",new.env(),.GlobalEnv)
    templates<-get(".v31_binary_templates",.GlobalEnv);codekey<-sha256_object(spec$code)
    if(exists(codekey,templates,inherits=FALSE)) {
      fit<-stats::update(get(codekey,templates),newdata=spec$data,recompile=FALSE,seed=req$seed,
        chains=ctl$chains,cores=ctl$cores,iter=ctl$iter,warmup=ctl$warmup,
        control=list(adapt_delta=ctl$adapt_delta,max_treedepth=ctl$max_treedepth),refresh=50)
    } else {
      fit<-brms::brm(spec$formula,data=spec$data,family=brms::bernoulli(),prior=spec$prior,
        save_pars=brms::save_pars(all=TRUE),backend="rstan",seed=req$seed,chains=ctl$chains,cores=ctl$cores,iter=ctl$iter,warmup=ctl$warmup,
        control=list(adapt_delta=ctl$adapt_delta,max_treedepth=ctl$max_treedepth),refresh=50,silent=2)
      assign(codekey,fit,templates)
    }
    d<-diagnose_brms_fit_v3(fit,ctl$max_treedepth)
  } else {
    if(!exists(".v31_compiled",inherits=TRUE))assign(".v31_compiled",new.env(),.GlobalEnv)
    env<-get(".v31_compiled",.GlobalEnv);key<-sha256_object(spec$code)
    if(!exists(key,env,inherits=FALSE))assign(key,rstan::stan_model(model_code=spec$code,model_name="ratio_v31_joint"),env)
    fit<-rstan::sampling(get(key,env),data=spec$data[setdiff(names(spec$data),"train_rows")],seed=req$seed,chains=ctl$chains,cores=ctl$cores,iter=ctl$iter,warmup=ctl$warmup,
      control=list(adapt_delta=ctl$adapt_delta,max_treedepth=ctl$max_treedepth),refresh=50)
    d<-diagnose_rstan_fit_v3(fit,ctl$max_treedepth)
  }
  b<-list(version=V3_VERSION,key=spec$key,request=req,route=req$route,model=req$model,train_weighting=req$train_weighting,
    train_species=req$training_species,blueprint=spec$blueprint,data=spec$data,fit=fit,diagnostics=d,code=spec$code)
  b$fit_payload_hash<-fit_payload_hash_v3(fit)
  save_rds_atomic(b,out_path);cat("FIT_END",req$route,req$model,d$Status,"\n");b
}
fit_binomial_model_v3 <- function(state,model,train_species,train_weighting,out_path,iter=V3_SAMPLING$iter,warmup=V3_SAMPLING$warmup,chains=V3_SAMPLING$chains,cores=V3_SAMPLING$cores,seed=V3_SEED,force=FALSE) {
  ctl<-modifyList(V3_SAMPLING,list(iter=iter,warmup=warmup,chains=chains,cores=cores))
  fit_from_spec_v3(fit_spec_v3(state,"binary",model,train_species,train_weighting,NULL,ctl,seed),out_path,force)
}
fit_joint_model_v3 <- function(state,model,train_species,train_weighting,out_path,stan_path,iter=V3_SAMPLING$iter,warmup=V3_SAMPLING$warmup,chains=V3_SAMPLING$chains,cores=V3_SAMPLING$cores,seed=V3_SEED,force=FALSE) {
  ctl<-modifyList(V3_SAMPLING,list(iter=iter,warmup=warmup,chains=chains,cores=cores))
  fit_from_spec_v3(fit_spec_v3(state,"joint_bb",model,train_species,train_weighting,stan_path,ctl,seed),out_path,force)
}
