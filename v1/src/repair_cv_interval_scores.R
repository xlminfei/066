# Rebuild a failed joint/phylo_distance score from existing, immutable fold draws.
# This script contains no fitting, update, or sampling call.
options(warn = 1)
source("/project/work/ratio_analysis_20260914/scripts/common.R", local = .GlobalEnv)
source("/project/work/ratio_analysis_20260914/scripts/stable_cv_likelihood.R", local = .GlobalEnv)
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, args[[1]] %in% c("M1_P", "Site315_P", "M2_P", "M3_P", "Phylogeny_only_P"))
model <- args[[1]]
initialize_manual()
job_id <- paste("cv", "joint", model, "phylo_distance", "attempt1", sep = "__")
job_dir <- file.path(analysis_root, "runs", "job_receipts", job_id)
old_status <- jsonlite::read_json(file.path(job_dir, "status.json"), simplifyVector = TRUE)
stopifnot(old_status$status == "ERROR", identical(old_status$message, "留出似然出现非有限值，不能形成可靠的数值评分。"))
parent_dir <- file.path(analysis_root, "runs", "job_receipts", paste("joint", model, "primary", "attempt1", sep = "__"))
chosen_index <- read.csv(file.path(parent_dir, "fit_index.csv"), stringsAsFactors = FALSE)
run_block("05_诊断与模型比较.md", "05_LOAD", overrides = list(OUTCOME = "joint", VARIANT = "primary", fit_index = chosen_index))
diagnostics <- read.csv(file.path(parent_dir, "results", "diagnostics_joint_primary.csv"), stringsAsFactors = FALSE)
sampling <- bundles[[model]]$request$sampling
run_block("06_留出验证.md", "06_FOLDS", overrides = list(CV_TYPE = "phylo_distance",
  CV_ITER = as.integer(max(4000, sampling$iter)), CV_WARMUP = as.integer(max(4000, sampling$iter) / 2),
  CV_ADAPT_DELTA = max(.99, sampling$adapt_delta), CV_MAX_TREEDEPTH = as.integer(max(12, sampling$max_treedepth))))
run_block("06_留出验证.md", "06_SELECT", overrides = list(CV_MODEL = model))
if (file.exists(cv_file)) stop("Preserve any existing CV bundle; this repair expects a previously failed score with no saved bundle")

source_rows <- obj$request$source_rows
row_folds <- as.integer(species_folds[source_rows$Species])
fold_fits <- heldout_rows <- vector("list", CV_K)
raw_files <- vector("list", CV_K)
for (k in seq_len(CV_K)) {
  held <- which(!source_rows$NoRatioInformation & !is.na(row_folds) & row_folds == k)
  d <- obj$request$data; d$train[held] <- 0L
  stopifnot(length(held) > 0L, !any(source_rows$Species[d$train == 1L] %in% source_rows$Species[held]))
  path <- file.path(CV_DIR, paste0(model, "_", substr(cv_key, 1, 16), "_fold", k, ".rds"))
  cached <- readRDS(path)
  stopifnot(identical(cached$data_key, digest::digest(d, algo = "sha256")),
    cached$fit@sim$chains == CV_CHAINS, cached$fit@sim$iter == CV_ITER,
    cached$fit@sim$warmup == CV_WARMUP)
  fold_fits[[k]] <- cached$fit; heldout_rows[[k]] <- held
  raw_files[[k]] <- data.frame(Fold = k, File = path, SHA256 = digest::digest(file = path, algo = "sha256"), DataKey = cached$data_key)
}
helper_names <- c("stable_beta_interval.R", "stable_cv_likelihood.R")
helper_hashes <- setNames(vapply(helper_names, function(n) digest::digest(file = file.path(analysis_root, "scripts", n), algo = "sha256"), character(1)), helper_names)
cv_bundle <- list(key = cv_key, request = cv_request, outcome = OUTCOME, model = CV_MODEL,
  parent_key = obj$key, fold_fits = fold_fits, heldout_rows = heldout_rows, source = source_rows, row_folds = row_folds,
  evaluated_log_lik = vector("list", CV_K),
  likelihood_evaluation = list(version = STABLE_BETA_INTERVAL_VERSION, helper_sha256 = as.list(helper_hashes),
    sampling_changed = FALSE, scope = "same one-inflated Beta model; stable interval log-tail arithmetic only",
    raw_fold_files = do.call(rbind, raw_files), fold_diagnostics = vector("list", CV_K)))

# Execute the original common score block, changing exactly one likelihood-matrix assignment.
original_assignment <- quote(lm <- matrix(la, nrow = dim(la)[1] * dim(la)[2], ncol = dim(la)[3]))
replaced <- 0L
replace_score_matrix <- function(expression) {
  if (isTRUE(all.equal(expression, original_assignment, check.attributes = FALSE))) {
    replaced <<- replaced + 1L
    return(quote({
      stable_result <- stable_cv_loglik(sf, cv_bundle$source, held, obj$species)
      stopifnot(stable_result$diagnostic$OriginalNonfiniteTraining == 0L,
        stable_result$diagnostic$MaxAbsTrainingJointLogDifference <= 1e-8)
      lm <- stable_result$log_lik
      cv_bundle$evaluated_log_lik[[k]] <- lm
      cv_bundle$likelihood_evaluation$fold_diagnostics[[k]] <- cbind(Fold = k, stable_result$diagnostic)
    }))
  }
  if (is.call(expression)) return(as.call(lapply(as.list(expression), replace_score_matrix)))
  expression
}
expressions <- lapply(read_block("06_留出验证.md", "06_SCORE"), replace_score_matrix)
stopifnot(replaced == 1L)
for (expression in expressions) {
  if (is.call(expression) && identical(expression[[1]], as.name("<-")) && identical(expression[[2]], as.name("ci_file"))) {
    ci_file <- file.path(job_dir, "cv_index.csv")
  } else eval(expression, envir = .GlobalEnv)
}
stopifnot(cv_bundle$status == "PASS", all(cv_bundle$diagnostics$Status == "PASS"))
raw_files <- do.call(rbind, raw_files)
stopifnot(all(vapply(raw_files$File, function(p) digest::digest(file = p, algo = "sha256"), character(1)) == raw_files$SHA256))
write.csv(cv_bundle$fold_scores, file.path(job_dir, "fold_scores.csv"), row.names = FALSE)
write.csv(cv_bundle$diagnostics, file.path(job_dir, "fold_diagnostics.csv"), row.names = FALSE)
write.csv(do.call(rbind, cv_bundle$likelihood_evaluation$fold_diagnostics), file.path(job_dir, "likelihood_repair_diagnostics.csv"), row.names = FALSE)
archive <- file.path(analysis_root, "provenance", "numerical_score_repair_20260916", job_id)
dir.create(archive, recursive = TRUE, showWarnings = FALSE)
stopifnot(!file.exists(file.path(archive, "original_error_status.json")))
file.copy(file.path(job_dir, "status.json"), file.path(archive, "original_error_status.json"))
atomic_json(list(status = "PASS", job = job_id, outcome = OUTCOME, model = CV_MODEL, cv_type = CV_TYPE,
  attempt = 1L, key = cv_key, parent_key = obj$key, cv_dir = CV_DIR, cv_file = cv_file, fold_key = fold_key,
  sampling = cv_request$sampling, started_at = old_status$started_at, finished_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  diagnostics = cv_bundle$diagnostics, score_protocol = STABLE_BETA_INTERVAL_VERSION,
  sampling_changed = FALSE, likelihood_helper_sha256 = as.list(helper_hashes),
  repair_script_sha256 = digest::digest(file = file.path(analysis_root, "scripts", "repair_cv_interval_scores.R"), algo = "sha256")),
  file.path(job_dir, "status.json"))
cat("FIXED_DRAW_CV_SCORE_REPAIR_COMPLETE", model, "NO_FITTING_OR_SAMPLING\n")
