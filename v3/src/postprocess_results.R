#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
i <- match("--root", args)
root <- if (!is.na(i) && i < length(args)) args[[i + 1L]] else normalizePath(".")
source(file.path(root, "R", "config.R"), local = TRUE)
source(file.path(root, "R", "weights.R"), local = TRUE)
source(file.path(root, "R", "metrics.R"), local = TRUE)
source(file.path(root, "R", "comparison.R"), local = TRUE)
ev <- utils::read.csv(file.path(root, "results", "cv_record_predictions.csv"), stringsAsFactors = FALSE)
dir.create(file.path(root, "results"), recursive = TRUE, showWarnings = FALSE)
make_roc_outputs(ev, file.path(root, "results"))
cal <- list()
for (ew in V3_EVAL_WEIGHTINGS) for (design in unique(ev$Design)) for (model in V3_MODELS) for (tw in V3_TRAIN_WEIGHTINGS) {
  z <- ev[ev$Route == "binary" & ev$Design == design & ev$Model == model & ev$TrainWeighting == tw, , drop = FALSE]
  if (nrow(z)) cal[[length(cal) + 1L]] <- cbind(data.frame(Design = design, Model = model, TrainWeighting = tw), calibration_bins(z, ew))
}
if (length(cal)) write_csv_atomic(do.call(rbind, cal), file.path(root, "results", "calibration_bins.csv"))
write_csv_atomic(compare_evidence_models(ev, "species_equal"), file.path(root, "results", "model_vs_null.csv"))
write_csv_atomic(compare_training_methods(ev, "species_equal"), file.path(root, "results", "training_method_comparisons.csv"))
cat("POSTPROCESS_PASS\n")
