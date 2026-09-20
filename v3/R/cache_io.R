fit_identity <- function(route, model, train_weighting, train_rows, state,
                         model_code_hash, sampling = V3_SAMPLING, seed = V3_SEED) {
  list(version = V3_VERSION, route = route, model = model,
       train_weighting = train_weighting, train_rows = as.integer(train_rows),
       training_species = sort(unique(state$observations$Species[train_rows])),
       input_hashes = state$input_hashes,
       blueprint_hash = sha256_object(state$blueprints[[paste0(route, "_", model)]]),
       model_code_hash = model_code_hash, priors = V3_PRIORS,
       sampling = sampling, seed = as.integer(seed))
}

identity_key <- function(request) sha256_object(request)

cache_is_valid <- function(path, request, route, model, train_weighting) {
  if (!file.exists(path)) return(FALSE)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$request)) return(FALSE)
  identical(obj$key, identity_key(request)) && identical(obj$request, request) &&
    identical(obj$route, route) && identical(obj$model, model) &&
    identical(obj$train_weighting, train_weighting) &&
    identical(obj$version, V3_VERSION)
}

cache_metadata <- function(bundle) {
  list(version = bundle$version, route = bundle$route, model = bundle$model,
       train_weighting = bundle$train_weighting, key = bundle$key,
       request = bundle$request, diagnostics = bundle$diagnostics)
}
