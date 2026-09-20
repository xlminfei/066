plot_roc_base <- function(roc_data, output_path) {
  if (!nrow(roc_data)) stop("ROC table is empty")
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(output_path, width = 8, height = 6, onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)
  keys <- unique(roc_data[, c("Design", "EvalWeighting", "TrainWeighting")])
  cols <- setNames(grDevices::hcl.colors(length(V3_MODELS), "Dark 3"), V3_MODELS)
  for (i in seq_len(nrow(keys))) {
    z <- roc_data[roc_data$Design == keys$Design[[i]] & roc_data$EvalWeighting == keys$EvalWeighting[[i]] &
                    roc_data$TrainWeighting == keys$TrainWeighting[[i]], , drop = FALSE]
    plot(c(0, 1), c(0, 1), type = "n", xlab = "False positive rate", ylab = "True positive rate",
         main = paste(keys$Design[[i]], keys$EvalWeighting[[i]], keys$TrainWeighting[[i]], sep = " | "))
    abline(0, 1, col = "grey70", lty = 2)
    for (model in intersect(V3_MODELS, unique(z$Model))) {
      q <- z[z$Model == model, , drop = FALSE]
      for (fold in unique(q$Fold)) {
        r <- q[q$Fold == fold, , drop = FALSE]
        r <- r[order(r$FPR, r$TPR), , drop = FALSE]
        lines(r$FPR, r$TPR, col = grDevices::adjustcolor(cols[[model]], .35), lty = 3)
      }
    }
    legend("bottomright", legend = intersect(V3_MODELS, unique(z$Model)),
           col = cols[intersect(V3_MODELS, unique(z$Model))], lwd = 2, bty = "n")
  }
  invisible(output_path)
}

plot_calibration_base <- function(calibration, output_path) {
  if (!nrow(calibration)) stop("Calibration table is empty")
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(output_path, width = 8, height = 6, onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)
  keys <- unique(calibration[, c("Design", "EvalWeighting", "TrainWeighting")])
  for (i in seq_len(nrow(keys))) {
    z <- calibration[calibration$Design == keys$Design[[i]] & calibration$EvalWeighting == keys$EvalWeighting[[i]] &
                       calibration$TrainWeighting == keys$TrainWeighting[[i]], , drop = FALSE]
    plot(c(0, 1), c(0, 1), type = "n", xlab = "Mean predicted HIGH probability",
         ylab = "Observed HIGH rate", main = paste(keys$Design[[i]], keys$EvalWeighting[[i]], keys$TrainWeighting[[i]], sep = " | "))
    abline(0, 1, col = "grey70", lty = 2)
    for (model in unique(z$Model)) {
      q <- z[z$Model == model, , drop = FALSE]
      points(q$MeanPredicted, q$ObservedRate, pch = 19, type = "b")
      if (all(c("CalibrationLower", "CalibrationUpper") %in% names(q))) {
        segments(q$MeanPredicted, q$CalibrationLower, q$MeanPredicted, q$CalibrationUpper)
      }
    }
    legend("topleft", legend = unique(z$Model), pch = 19, bty = "n")
  }
  invisible(output_path)
}

plot_species_predictions_base <- function(predictions, output_dir, page_size = 42L) {
  required <- c("Species", "Route", "Model", "TrainWeighting", "Point", "CrI_lower", "CrI_upper")
  if (!all(required %in% names(predictions))) stop("Prediction table lacks plotting columns")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  species <- unique(predictions$Species)
  pages <- split(species, ceiling(seq_along(species) / page_size))
  for (route in unique(predictions$Route)) for (tw in unique(predictions$TrainWeighting)) {
    path <- file.path(output_dir, paste0("species_predictions_", route, "_", tw, ".pdf"))
    grDevices::pdf(path, width = 11, height = 8.5, onefile = TRUE)
    for (sp_page in pages) {
      z <- predictions[predictions$Route == route & predictions$TrainWeighting == tw & predictions$Species %in% sp_page, , drop = FALSE]
      plot(seq_along(sp_page), rep(NA_real_, length(sp_page)), ylim = c(0, 1), xlim = c(.5, length(sp_page) + .5),
           xaxt = "n", xlab = "Species", ylab = "Predicted value", main = paste(route, tw))
      axis(1, at = seq_along(sp_page), labels = sp_page, las = 2, cex.axis = .45)
      for (model in intersect(V3_MODELS, unique(z$Model))) {
        q <- z[z$Model == model, , drop = FALSE]; q <- q[match(sp_page, q$Species), , drop = FALSE]
        xx <- seq_along(sp_page)
        points(xx, q$Point, pch = 19)
        segments(xx, q$CrI_lower, xx, q$CrI_upper)
      }
    }
    grDevices::dev.off()
  }
  invisible(output_dir)
}
