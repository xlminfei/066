V3_VERSION <- "ratio_analysis_v3_weighted_20260920"
V3_MODELS <- c("Null", "M1", "M2", "M3")
V3_ROUTES <- c("binary", "joint_bb")
V3_TRAIN_WEIGHTINGS <- c("record_equal", "species_equal")
V3_EVAL_WEIGHTINGS <- c("record_equal", "species_equal")
V3_DESIGNS <- c("fivefold", "tenfold")
V3_SITE_COLUMNS <- c("Site3", "Site20", "Site117", "Site151", "Site196", "Site315")
V3_PREDICTOR_SITES <- c("Site3", "Site20", "Site117", "Site196", "Site315")
V3_RARE_MIN <- 4L
V3_SEED <- 20260920L
V3_PRIORS <- list(intercept = 1.5, beta = 0.5, rho_a = 1, rho_b = 1,
                  log_phi_mean = log(10), log_phi_sd = 1)
V3_SAMPLING <- list(chains = 4L, cores = 4L, iter = 4000L, warmup = 2000L,
                    adapt_delta = 0.99, max_treedepth = 12L)

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

v3_model_predictor_sites <- function(model) {
  if (identical(model, "Null")) character() else V3_PREDICTOR_SITES
}

v3_expected_fit_count <- function() {
  length(V3_MODELS) * length(V3_ROUTES) * length(V3_TRAIN_WEIGHTINGS)
}

v3_expected_cv_fit_count <- function() {
  length(V3_MODELS) * length(V3_ROUTES) * length(V3_TRAIN_WEIGHTINGS) *
    sum(c(5L, 10L))
}
