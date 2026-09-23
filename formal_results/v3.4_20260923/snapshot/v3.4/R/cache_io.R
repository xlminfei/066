fit_identity <- function(route, model, train_weighting, train_rows, state,
                         model_code_hash, sampling = V3_SAMPLING, seed = V3_SEED) {
  train_rows <- sort(unique(as.integer(train_rows)))
  if (!length(train_rows)) stop("Cannot create fit identity for zero training rows")
  if (any(train_rows < 1L | train_rows > nrow(state$observations))) stop("Training row index is out of range")
  sampling <- modifyList(V3_SAMPLING, sampling)
  weight_frame <- build_train_weights(state$observations[train_rows, "Species", drop = FALSE], train_weighting)
  bp <- state$blueprints[[blueprint_key(route, model)]]
  if (is.null(bp)) stop("Blueprint not found for fit identity: ", route, "/", model)
  list(version = V3_VERSION, route = route, model = model,
       train_weighting = train_weighting, train_rows = train_rows,
       training_species = sort(unique(state$observations$Species[train_rows])),
       input_hashes = state$input_hashes,
       blueprint_hash = sha256_object(bp), model_code_hash = model_code_hash,
       priors = V3_PRIORS, weight_algorithm = V3_WEIGHT_ALGORITHM,
       weight_implementation = sha256_object(body(build_train_weights)),
       preparation_identity = preparation_identity_v3(),
       training_data_hash = sha256_object(state$observations[train_rows,,drop=FALSE]),
       R_version = as.character(getRversion()),
       weight_hash = sha256_object(weight_frame$weight),
       sampling = sampling, seed = as.integer(seed),
       package_versions = v3_package_versions(formal = route %in% c("binary", "joint_bb")))
}

identity_key <- function(request) sha256_object(request)

validate_bundle_for_use <- function(bundle, request = NULL, require_pass = FALSE, allow_failed = FALSE) {
  if (is.null(bundle) || !is.list(bundle) || is.null(bundle$request) || is.null(bundle$key)) {
    stop("Fit bundle is missing identity metadata")
  }
  if (!is.null(request)) {
    if (!identical(bundle$key, identity_key(request)) || !identical(bundle$request, request)) {
      stop("Fit bundle identity does not match the requested fit")
    }
  }
  if (!identical(bundle$key, identity_key(bundle$request))) stop("Fit bundle key is invalid")
  if (is.null(bundle$fit) || !(inherits(bundle$fit,"brmsfit") || inherits(bundle$fit,"stanfit"))) stop("Invalid fit object class")
  if (!identical(bundle$request$data_hash,sha256_object(bundle$data))) stop("Stored training data hash mismatch")
  if (!identical(bundle$request$model_code_hash,sha256_object(bundle$code))) stop("Stored code hash mismatch")
  if (!identical(bundle$train_species,bundle$request$training_species)) stop("Stored training species mismatch")
  if (!identical(bundle$version, V3_VERSION)) stop("Fit bundle version mismatch")
  if (!bundle$route %in% V3_ROUTES || !bundle$model %in% V3_MODELS ||
      !bundle$train_weighting %in% V3_TRAIN_WEIGHTINGS) stop("Fit bundle grid identity is invalid")
  if (!is.null(bundle$blueprint) && !identical(bundle$request$blueprint_hash, sha256_object(bundle$blueprint))) {
    stop("Fit bundle blueprint hash does not match the stored blueprint")
  }
  if(is.null(bundle$fit_payload_hash)||!identical(bundle$fit_payload_hash,fit_payload_hash_v3(bundle$fit))) stop("Fitted payload integrity mismatch")
  for(n in c("route","model"))if(!identical(bundle[[n]],bundle$request[[n]]))stop("Bundle request identity mismatch")
  if(!identical(bundle$train_weighting,bundle$request$train_weighting))stop("Weighting identity mismatch")
  status <- if (!is.null(bundle$diagnostics$Status)) as.character(bundle$diagnostics$Status[[1L]]) else NA_character_
  if (is.na(status) || (!allow_failed && identical(status, "FAILED_DIAGNOSTICS")) || (require_pass && !identical(status, "PASS"))) {
    stop("Fit bundle diagnostics are not acceptable for use: ", status)
  }
  invisible(TRUE)
}

cache_is_valid <- function(path, request, route, model, train_weighting) {
  if (!file.exists(path)) return(FALSE)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(obj)) return(FALSE)
  ok <- tryCatch({
    validate_bundle_for_use(obj, request = request, require_pass = FALSE, allow_failed = TRUE)
    identical(obj$route, route) && identical(obj$model, model) &&
      identical(obj$train_weighting, train_weighting)
  }, error = function(e) FALSE)
  isTRUE(ok)
}

cache_metadata <- function(bundle) {
  list(version = bundle$version, route = bundle$route, model = bundle$model,
       train_weighting = bundle$train_weighting, key = bundle$key,
       request = bundle$request, diagnostics = bundle$diagnostics)
}

validate_fitted_bundle_v3 <- function(bundle,spec,require_pass=TRUE) {
  validate_bundle_for_use(bundle,spec$request,require_pass=FALSE,allow_failed=TRUE)
  if(!identical(bundle$data,spec$data)||!identical(bundle$blueprint,spec$blueprint))stop("Fit data/blueprint mismatch")
  actual_code<-if(bundle$route=="binary")as.character(brms::stancode(bundle$fit)) else rstan::get_stancode(bundle$fit)
  if(!isTRUE(trimws(actual_code)==trimws(spec$code)))stop("Actual fitted Stan code mismatch")
  st<-if(bundle$route=="binary")bundle$fit$fit else bundle$fit
  ctl<-spec$request$sampling
  if(length(st@stan_args)!=ctl$chains)stop("Actual chain count mismatch")
  for(a in st@stan_args) {
    if(as.integer(a$iter)!=ctl$iter||as.integer(a$warmup)!=ctl$warmup||as.integer(a$seed)!=spec$request$seed)stop("Actual sampling settings mismatch")
    if(a$control$adapt_delta!=ctl$adapt_delta||a$control$max_treedepth!=ctl$max_treedepth)stop("Actual sampler controls mismatch")
  }
  if(bundle$route=="binary") {
    used<-c("High","TrainWeight",bundle$blueprint$columns)
    if(!all(used%in%names(bundle$fit$data)) || !isTRUE(all.equal(as.data.frame(bundle$fit$data[,used,drop=FALSE]),spec$data[,used,drop=FALSE],check.attributes=FALSE)))stop("Actual brms training data mismatch")
  }
  d<-if(bundle$route=="binary")diagnose_brms_fit_v3(bundle$fit,spec$request$sampling$max_treedepth) else diagnose_rstan_fit_v3(bundle$fit,spec$request$sampling$max_treedepth)
  if(require_pass&&d$Status!="PASS")stop("Recomputed fit diagnostics failed")
  invisible(d)
}

fit_payload_hash_v3 <- function(fit) {
  st<-if(inherits(fit,"brmsfit"))fit$fit else fit
  if(!inherits(st,"stanfit"))stop("Invalid Stan fit payload")
  args<-lapply(st@stan_args,function(a)list(seed=as.character(a$seed),iter=as.integer(a$iter),warmup=as.integer(a$warmup),chain_id=as.integer(a$chain_id),adapt_delta=as.numeric(a$control$adapt_delta),max_treedepth=as.integer(a$control$max_treedepth)))
  dat<-if(inherits(fit,"brmsfit"))lapply(fit$data,function(x){if(is.factor(x))x<-as.character(x);unname(x)}) else NULL
  sha256_object(list(draws=as.array(st),sampler=lapply(rstan::get_sampler_params(st,inc_warmup=FALSE),unname),args=args,code=trimws(rstan::get_stancode(st)),data=dat))
}
