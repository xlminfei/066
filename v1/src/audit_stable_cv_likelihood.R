options(warn = 1)
suppressPackageStartupMessages(library(rstan))
suppressPackageStartupMessages(library(digest))
suppressPackageStartupMessages(library(matrixStats))
root <- "/project/work/ratio_analysis_20260914"
source(file.path(root, "scripts", "stable_cv_likelihood.R"))
run <- file.path(root, "runs", "formal_20260914_26e686af86fa")
out <- file.path(root, "review", "likelihood_diagnosis_20260916")
prepared <- readRDS(file.path(run, "prepared.rds"))
index <- read.csv(file.path(run, "fit_index.csv"), stringsAsFactors = FALSE)
index <- index[index$Outcome == "joint" & index$Variant == "primary", , drop = FALSE]
directories <- read.csv(file.path(root, "provenance", "cv_directory_manifest.csv"), stringsAsFactors = FALSE)
directories <- directories[directories$Outcome == "joint", , drop = FALSE]
results <- list()
for (i in seq_len(nrow(index))) {
  model <- index$Model[i]
  parent <- readRDS(file.path(run, index$RelativeFile[i]))
  for (j in seq_len(nrow(directories))) {
    design <- directories$CVType[j]; folder <- file.path(run, "cv", basename(directories$Directory[j]))
    folds <- read.csv(file.path(folder, "folds.csv"), stringsAsFactors = FALSE)
    rows <- list()
    for (k in 1:5) {
      paths <- list.files(folder, pattern = paste0("^", model, "_[a-f0-9]+_fold", k, "[.]rds$"), full.names = TRUE)
      stopifnot(length(paths) == 1L)
      cache <- readRDS(paths[[1]])
      d <- parent$request$data
      held <- which(parent$request$source_rows$Species %in% folds$Species[folds$Fold == k] & !parent$request$source_rows$NoRatioInformation)
      d$train[held] <- 0L
      stopifnot(identical(cache$data_key, digest::digest(d, algo = "sha256")))
      value <- stable_cv_loglik(cache$fit, parent$request$source_rows, held, parent$species)
      rows[[k]] <- cbind(data.frame(Model = model, CVType = design, Fold = k, ParentKey = parent$key), value$diagnostic)
      cat(model, design, k, "original_nonfinite", value$diagnostic$OriginalNonfiniteHeldout,
        "ELPD_difference", format(value$diagnostic$ELPDDifference, digits = 5),
        "max_training_log_difference", format(value$diagnostic$MaxAbsTrainingJointLogDifference, digits = 5), "\n")
      rm(cache, value); invisible(gc())
    }
    table <- do.call(rbind, rows)
    write.csv(table, file.path(out, paste0("stable_compatibility_", model, "_", design, ".csv")), row.names = FALSE)
    results[[paste(model, design)]] <- table
  }
  rm(parent); invisible(gc())
}
all <- do.call(rbind, results)
stopifnot(nrow(all) == 100L)
write.csv(all, file.path(out, "stable_compatibility_all.csv"), row.names = FALSE)
cat("ALL_100_JOINT_FOLDS_NUMERICAL_COMPATIBILITY_AUDITED\n")
