#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
i <- match("--root", args)
root <- if (!is.na(i) && i < length(args)) args[[i + 1L]] else normalizePath(".")
source(file.path(root, "R", "config.R"), local = TRUE)
pred <- if (file.exists(file.path(root, "results", "full_panel_predictions.csv"))) utils::read.csv(file.path(root, "results", "full_panel_predictions.csv"), stringsAsFactors = FALSE) else data.frame()
cv <- if (file.exists(file.path(root, "results", "cv_metrics_summary.csv"))) utils::read.csv(file.path(root, "results", "cv_metrics_summary.csv"), stringsAsFactors = FALSE) else data.frame()
lines <- c("# v3 analysis report", "", paste0("Version: `", V3_VERSION, "`"),
  "", "This report describes computed artifacts; it does not convert diagnostic completion into scientific proof.",
  "", paste0("Panel species: ", if (nrow(pred)) length(unique(pred$Species)) else NA_integer_),
  paste0("Prediction rows: ", nrow(pred)), paste0("CV metric rows: ", nrow(cv)),
  "", "Train weightings: record_equal and species_equal.",
  "Evaluation weightings: record_equal and species_equal.",
  "Site151 is metadata only; Site315 remains inside M1/M2/M3; Scheme A and phylogeny are excluded.")
dir.create(file.path(root, "reports"), recursive = TRUE, showWarnings = FALSE)
writeLines(lines, file.path(root, "reports", "REPORT_v3.md"), useBytes = TRUE)
cat("REPORT_PASS\n")
