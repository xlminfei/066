#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
i <- match("--root", args)
root <- if (!is.na(i) && i < length(args)) args[[i + 1L]] else normalizePath(".")
source(file.path(root, "R", "config.R"), local = TRUE)
source(file.path(root, "R", "plotting.R"), local = TRUE)
pred <- utils::read.csv(file.path(root, "results", "full_panel_predictions.csv"), stringsAsFactors = FALSE)
plot_species_predictions_base(pred, file.path(root, "figures"))
cat("PLOT_PASS\n")
