options(warn = 1)
suppressPackageStartupMessages(library(rstan))
root <- "/project/work/ratio_analysis_20260914"
folder <- file.path(root, "provenance", "recovery_20260915")
files <- read.csv(file.path(folder, "checkpoint_files.csv"), stringsAsFactors = FALSE)
rows <- list()
for (i in seq_len(nrow(files))) {
  path <- file.path(root, files$File[i])
  result <- tryCatch({
    obj <- readRDS(path)
    stopifnot(is.list(obj), is.character(obj$data_key), length(obj$data_key) == 1L,
      inherits(obj$fit, "stanfit"), obj$fit@sim$chains == 4L, length(obj$fit@sim$samples) == 4L,
      obj$fit@sim$iter == 4000L, obj$fit@sim$warmup == 2000L,
      all(obj$fit@sim$n_save - obj$fit@sim$warmup2 == 2000L))
    list(Status = "READABLE_COMPLETE_DRAWS", DataKey = obj$data_key, Message = "")
  }, error = function(e) list(Status = "INVALID_CHECKPOINT", DataKey = "", Message = conditionMessage(e)))
  rows[[i]] <- cbind(files[i, , drop = FALSE], as.data.frame(result, stringsAsFactors = FALSE))
  cat(i, "/", nrow(files), files$Job[i], result$Status, "\n")
  if (exists("obj")) rm(obj)
  invisible(gc())
}
result <- do.call(rbind, rows)
write.csv(result, file.path(folder, "checkpoint_read_checks.csv"), row.names = FALSE)
if (any(result$Status != "READABLE_COMPLETE_DRAWS")) stop("Inspect invalid checkpoint records before resuming")
cat("ALL_INTERRUPTED_NATIVE_CHECKPOINTS_READABLE; exact data keys are also checked by the unchanged CV resume code\n")
