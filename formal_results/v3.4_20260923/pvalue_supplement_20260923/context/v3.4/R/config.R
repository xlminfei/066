V3_VERSION <- "ratio_analysis_v3_4_weighted_20260922"
V3_MODELS <- c("Null", "M1", "M2", "M3")
V3_ROUTES <- c("binary", "joint_bb")
V3_TRAIN_WEIGHTINGS <- c("record_equal", "species_equal")
V3_EVAL_WEIGHTINGS <- c("record_equal", "species_equal")
V3_DESIGNS <- c("fivefold", "tenfold")
V3_DESIGN_K <- c(fivefold = 5L, tenfold = 10L)
V3_SITE_COLUMNS <- c("Site3", "Site20", "Site117", "Site151", "Site196", "Site315")
V3_PREDICTOR_SITES <- c("Site3", "Site20", "Site117", "Site196", "Site315")
V3_RARE_MIN <- 4L
V3_SEED <- 20260920L
V3_COMPARISON_BOOTSTRAP <- 1000L
V3_WEIGHT_ALGORITHM <- "N_train/(S_train*R_species); total_weight=N_train"
V3_PRIORS <- list(intercept = 1.5, beta = 0.5, rho_a = 1, rho_b = 1,
                  log_phi_mean = log(10), log_phi_sd = 1)
V3_SAMPLING <- list(chains = 4L, cores = 4L, iter = 4000L, warmup = 2000L,
                    adapt_delta = 0.99, max_treedepth = 12L)
V3_ALLOWED_RESIDUES <- c("A", "C", "D", "E", "F", "G", "H", "I", "K", "L", "M",
                         "N", "P", "Q", "R", "S", "T", "V", "W", "Y", "MISSING")

`%||%` <- function(x, y) if (is.null(x)) y else x

require_v3_packages <- function(formal = FALSE) {
  needed <- c("digest", "jsonlite")
  if (formal) needed <- c(needed, "brms", "rstan", "posterior")
  missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Missing required packages: ", paste(missing, collapse = ", "))
  invisible(TRUE)
}

sha256_file <- function(path) {
  require_v3_packages(FALSE)
  digest::digest(file = path, algo = "sha256")
}

sha256_object <- function(x) {
  require_v3_packages(FALSE)
  digest::digest(x, algo = "sha256", serialize = TRUE)
}

write_json_atomic <- function(x, path) {
  require_v3_packages(FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  jsonlite::write_json(x, tmp, auto_unbox = TRUE, pretty = TRUE, na = "null")
  if (!file.rename(tmp, path)) stop("Could not atomically write ", path)
  invisible(path)
}

write_csv_atomic <- function(x, path, na = "") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  utils::write.csv(x, tmp, row.names = FALSE, na = na)
  if (!file.rename(tmp, path)) stop("Could not atomically write ", path)
  invisible(path)
}

save_rds_atomic <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  saveRDS(x, tmp)
  if (!file.rename(tmp, path)) stop("Could not atomically write ", path)
  invisible(path)
}

blueprint_key <- function(route, model) {
  if (!route %in% V3_ROUTES || !model %in% V3_MODELS) stop("Invalid blueprint identity")
  paste(route, model, sep = "_")
}

v3_model_predictor_sites <- function(model) {
  if (identical(model, "Null")) character() else V3_PREDICTOR_SITES
}

v3_expected_fit_count <- function() {
  length(V3_MODELS) * length(V3_ROUTES) * length(V3_TRAIN_WEIGHTINGS)
}

v3_expected_cv_fit_count <- function() {
  length(V3_MODELS) * length(V3_ROUTES) * length(V3_TRAIN_WEIGHTINGS) * sum(V3_DESIGN_K)
}

v3_package_versions <- function(formal = FALSE) {
  pkgs <- c("digest", "jsonlite")
  if (formal) pkgs <- c(pkgs, "brms", "rstan", "posterior")
  out <- lapply(pkgs, function(p) if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else NA_character_)
  names(out) <- pkgs
  out
}

validate_sampling_v3 <- function(x) {
  req<-c("chains","cores","iter","warmup","adapt_delta","max_treedepth")
  if(!all(req%in%names(x))||any(!is.finite(unlist(x[req]))))stop("Invalid sampling configuration")
  for(n in setdiff(req,"adapt_delta"))if(x[[n]]!=floor(x[[n]]))stop("Sampling integer required: ",n)
  if(x$chains<2||x$cores<1||x$warmup<1||x$iter<=x$warmup||x$adapt_delta<=0||x$adapt_delta>=1||x$max_treedepth<1)stop("Invalid sampling bounds")
  x
}
apply_analysis_config <- function(cfg) {
  require_v3_packages()
  fixed<-list(version=V3_VERSION,models=V3_MODELS,routes=V3_ROUTES,train_weightings=V3_TRAIN_WEIGHTINGS,eval_weightings=V3_EVAL_WEIGHTINGS,predictor_sites=V3_PREDICTOR_SITES,metadata_only_sites="Site151",primary_evaluation="species_equal",scheme_a=FALSE,phylogeny=FALSE,
    train_weight_normalization="N_train/(S_train*R_s), total weight equals N_train",
    classification_rule="count/exact >= 0.5 HIGH; interval Upper <= 0.5 LOW; interval Lower >= 0.5 HIGH; strict crossing excluded")
  for(n in names(fixed))if(!identical(unname(unlist(cfg[[n]])),unname(fixed[[n]])))stop("Unsupported or missing config field: ",n)
  dk<-unlist(cfg$designs);if(!identical(names(dk),names(V3_DESIGN_K))||any(dk!=V3_DESIGN_K))stop("v3.4 requires fixed fivefold/tenfold designs")
  for(n in c("rare_min","seed","expected_panel_species","expected_records","comparison_bootstrap"))if(length(cfg[[n]])!=1||!is.finite(cfg[[n]])||cfg[[n]]<1||cfg[[n]]!=floor(cfg[[n]]))stop("Invalid config field: ",n)
  for(n in names(V3_PRIORS))if(length(cfg$priors[[n]])!=1||!is.finite(cfg$priors[[n]])||(n!="log_phi_mean"&&cfg$priors[[n]]<=0))stop("Invalid prior: ",n)
  totals<-c(formal_full_fit_count=16L,formal_cv_fit_count=240L,formal_fit_count=256L)
  for(n in names(totals))if(!identical(as.integer(cfg[[n]]),totals[[n]]))stop("Invalid configured grid count: ",n)
  V3_RARE_MIN <<- as.integer(cfg$rare_min);V3_SEED <<- as.integer(cfg$seed)
  V3_COMPARISON_BOOTSTRAP <<- as.integer(cfg$comparison_bootstrap)
  V3_PRIORS <<- cfg$priors; V3_SAMPLING <<- validate_sampling_v3(cfg$sampling)
  invisible(cfg)
}
preparation_identity_v3 <- function() list(version=V3_VERSION,predictor_sites=V3_PREDICTOR_SITES,rare_min=V3_RARE_MIN,
  encoding=sha256_object(list(body(encode_panel),body(make_design_blueprint),body(classify_high_low),body(validate_input_data))))
