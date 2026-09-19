# Read completed fold draws only. Never refit or alter saved samples.
options(warn = 1)
suppressPackageStartupMessages(library(rstan))
suppressPackageStartupMessages(library(jsonlite))
root <- "/project/work/ratio_analysis_20260914"
run <- file.path(root, "runs", "formal_20260914_26e686af86fa")
out <- file.path(root, "review", "likelihood_diagnosis_20260916")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
prepared <- readRDS(file.path(run, "prepared.rds"))
source_rows <- prepared$observations
folder <- file.path(run, "cv", "joint_phylo_distance_fc3673933fd7")
folds <- read.csv(file.path(folder, "folds.csv"), stringsAsFactors = FALSE)
models <- commandArgs(trailingOnly = TRUE)
if (!length(models)) models <- c("M1_P", "Site315_P", "M2_P", "M3_P", "Phylogeny_only_P")
flat <- function(x) matrix(x, nrow = dim(x)[1] * dim(x)[2], ncol = dim(x)[3])
summaries <- examples <- list()
for (model in models) {
  model_summary <- model_examples <- list()
  for (k in 1:5) {
    paths <- list.files(folder, pattern = paste0("^", model, "_[a-f0-9]+_fold", k, "[.]rds$"), full.names = TRUE)
    stopifnot(length(paths) == 1L)
    cached <- readRDS(paths[[1]])
    ff <- cached$fit
    la <- rstan::extract(ff, pars = "log_lik", permuted = FALSE, inc_warmup = FALSE)
    ll <- flat(la)
    stopifnot(ncol(ll) == nrow(source_rows))
    held <- which(source_rows$Species %in% folds$Species[folds$Fold == k] & !source_rows$NoRatioInformation)
    bad <- which(!is.finite(ll), arr.ind = TRUE)
    entry <- data.frame(Model = model, Fold = k, Draws = nrow(ll),
      NonfiniteHeldout = sum(!is.finite(ll[, held, drop = FALSE])),
      NonfiniteTraining = sum(!is.finite(ll[, setdiff(seq_len(ncol(ll)), held), drop = FALSE])),
      NegInf = sum(ll == -Inf, na.rm = TRUE), PosInf = sum(ll == Inf, na.rm = TRUE), NaNCount = sum(is.na(ll)),
      DataKey = cached$data_key, File = paths[[1]])
    model_summary[[k]] <- entry
    if (nrow(bad)) {
      vars <- lapply(c("eta", "shape_a", "shape_b", "m", "log_endpoint", "log_continuous_weight"), function(v)
        flat(rstan::extract(ff, pars = v, permuted = FALSE, inc_warmup = FALSE)))
      names(vars) <- c("Eta", "ShapeA", "ShapeB", "M", "LogEndpoint", "LogContinuousWeight")
      for (record in unique(bad[, 2])) {
        ds <- bad[bad[, 2] == record, 1]
        take <- unique(c(head(ds, 5L), tail(ds, 5L)))
        species_index <- match(source_rows$Species[record], prepared$species$Species)
        z <- source_rows[rep(record, length(take)), c("RecordID", "Species", "Type", "Events", "Total", "Exact", "Lower", "Upper")]
        z$Model <- model; z$Fold <- k; z$SourceRow <- record; z$DrawRow <- take
        z$Iteration <- (take - 1L) %% dim(la)[1] + 1L; z$Chain <- (take - 1L) %/% dim(la)[1] + 1L
        z$Heldout <- record %in% held; z$NonfiniteCountForRecord <- length(ds)
        z$StanLogLikelihood <- as.character(ll[take, record])
        for (v in names(vars)) z[[v]] <- vars[[v]][take, species_index]
        model_examples[[length(model_examples) + 1L]] <- z
      }
      rm(vars)
    }
    cat(model, k, "heldout_nonfinite", entry$NonfiniteHeldout, "training_nonfinite", entry$NonfiniteTraining, "\n")
    rm(cached, ff, la, ll); invisible(gc())
  }
  sm <- do.call(rbind, model_summary)
  write.csv(sm, file.path(out, paste0(model, "_summary.csv")), row.names = FALSE)
  if (length(model_examples)) write.csv(do.call(rbind, model_examples), file.path(out, paste0(model, "_examples.csv")), row.names = FALSE)
  summaries[[model]] <- sm
}
write.csv(do.call(rbind, summaries), file.path(out, "diagnostic_summary.csv"), row.names = FALSE)
cat("READ_ONLY_NONFINITE_DIAGNOSIS_COMPLETE\n")
