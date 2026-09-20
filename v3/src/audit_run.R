#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
root_i <- match("--root", args)
root <- if (!is.na(root_i) && root_i < length(args)) args[[root_i + 1L]] else normalizePath(".")
plan <- file.path(root, "runs", "run_plan.csv")
if (!file.exists(plan)) stop("run_plan.csv is missing")
z <- utils::read.csv(plan, stringsAsFactors = FALSE)
if (nrow(z) != 256L || anyDuplicated(z$FitID)) stop("Run plan is not the expected 256 unique tasks")
fit_path <- function(row) {
  tag <- if (row$Design == "full") "full" else paste0(row$Design, "_f", row$Fold)
  file.path(root, "runs", "fits", paste(row$Route, row$Model, row$TrainWeighting, tag, sep = "__"), "fit.rds")
}
paths <- vapply(seq_len(nrow(z)), function(i) fit_path(z[i, , drop = FALSE]), character(1))
present <- file.exists(paths)
if (!any(present)) {
  cat("PLAN_PASS: 256 task identities are present; formal fit files are not present yet\n")
} else if (!all(present)) {
  stop("INCOMPLETE: ", sum(!present), " planned fit files are missing")
} else {
  cat("PASS: v3 run plan and all 256 fit files are present\n")
}
