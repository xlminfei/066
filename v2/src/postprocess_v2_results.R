# Postprocess the completed v2 run: tables, figures, captions, and a Chinese results summary.
options(stringsAsFactors = FALSE, warn = 1)
root <- normalizePath(Sys.getenv("V2_ROOT", getwd()), winslash = "/", mustWork = TRUE)
outdir <- file.path(root, "postprocess_20260919")
figdir <- file.path(outdir, "figures")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
dir.create(figdir, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
})

read_csv <- function(name) {
  read.csv(file.path(root, "results", name), stringsAsFactors = FALSE,
           check.names = FALSE, na.strings = c("", "NA"))
}
cv_fold <- read_csv("cv_fold_scores_v2.csv")
cv_record <- read_csv("cv_record_scores_v2.csv")
cv_comp <- read_csv("cv_comparisons_v2.csv")
full <- read_csv("full_panel_predictions_v2.csv")
ppc <- read_csv("model_fit_checks_v2.csv")
audit <- jsonlite::read_json(file.path(outdir, "fit_audit_summary.json"),
                             simplifyVector = TRUE)
final_status <- jsonlite::read_json(file.path(root, "review", "final_v2_status.json"),
                                    simplifyVector = TRUE)

stopifnot(nrow(full) == 365L * 5L * 3L,
          nrow(cv_fold) == 225L,
          nrow(cv_record) > 0L,
          all(is.finite(full$Point)),
          all(is.finite(full$CrI_lower)),
          all(is.finite(full$CrI_upper)))
qfull <- full$Route != "binary"
stopifnot(all(is.finite(full$PI_lower[qfull])),
          all(is.finite(full$PI_upper[qfull])),
          all(full$CrI_lower <= full$CrI_upper),
          all(full$PI_lower[qfull] <= full$PI_upper[qfull]))

models <- c("Null", "Site315", "M1", "M2", "M3")
main_models <- c("M1", "M2", "M3")
route_labels <- c(binary = "High/Low", joint_bb = "Joint beta-binomial",
                  schemeA_tobit = "Scheme A report-level")
model_cols <- c(Null = "#999999", Site315 = "#D55E00",
                M1 = "#0072B2", M2 = "#009E73", M3 = "#CC79A7")
type_cols <- c(count = "#0072B2", exact = "#D55E00")

write.csv(cv_comp, file.path(outdir, "model_comparisons_all.csv"), row.names = FALSE)
write.csv(cv_comp[cv_comp$Route == "binary", ],
          file.path(outdir, "highlow_auc_elpd_summary.csv"), row.names = FALSE)
write.csv(cv_comp[cv_comp$Route != "binary", ],
          file.path(outdir, "quantitative_elpd_mae_summary.csv"), row.names = FALSE)
write.csv(ppc[ppc$Status == "REVIEW_REQUIRED", ],
          file.path(outdir, "model_fit_review_flags.csv"), row.names = FALSE)

status_tab <- as.data.frame(table(full$Route, full$Model, full$Status),
                            stringsAsFactors = FALSE)
names(status_tab) <- c("Route", "Model", "Status", "Rows")
write.csv(status_tab, file.path(outdir, "full_prediction_status_summary.csv"),
          row.names = FALSE)

point_rows <- cv_record[cv_record$Route != "binary" &
                          cv_record$Type %in% c("count", "exact") &
                          is.finite(cv_record$ObservedPoint) &
                          is.finite(cv_record$PredictedPoint), ]
point_summary <- do.call(rbind, lapply(split(point_rows,
                                               list(point_rows$Route,
                                                    point_rows$Design,
                                                    point_rows$Model)), function(z) {
  err <- abs(z$PredictedPoint - z$ObservedPoint)
  data.frame(Route = z$Route[[1L]], Design = z$Design[[1L]],
             Model = z$Model[[1L]], Records = nrow(z),
             MAE = mean(err), stringsAsFactors = FALSE)
}))
write.csv(point_summary, file.path(outdir, "quantitative_point_mae_by_type.csv"),
          row.names = FALSE)

save_plot <- function(p, stem, width, height) {
  ggsave(file.path(figdir, paste0(stem, ".pdf")), p, width = width,
         height = height, units = "in", device = "pdf")
  ggsave(file.path(figdir, paste0(stem, ".png")), p, width = width,
         height = height, units = "in", dpi = 300)
}

roc_curve <- function(y, p) {
  keep <- is.finite(y) & is.finite(p)
  y <- as.integer(y[keep]); p <- p[keep]
  ord <- order(p, decreasing = TRUE, method = "radix")
  y <- y[ord]
  P <- sum(y == 1L); N <- sum(y == 0L)
  if (P == 0L || N == 0L) return(data.frame(FPR = 0, TPR = 0))
  tp <- c(0, cumsum(y == 1L), P)
  fp <- c(0, cumsum(y == 0L), N)
  data.frame(FPR = fp / N, TPR = tp / P)
}
auc_trap <- function(z) sum(diff(z$FPR) * (z$TPR[-1L] + z$TPR[-nrow(z)]) / 2)

brec <- cv_record[cv_record$Route == "binary", ]
roc_rows <- list()
roc_labels <- list()
for (design in unique(brec$Design)) {
  for (m in models) {
    z <- brec[brec$Design == design & brec$Model == m, ]
    if (!nrow(z)) next
    cr <- roc_curve(z$ObservedHigh, z$PredictedPrHigh)
    cr$Design <- design; cr$Model <- m
    roc_rows[[length(roc_rows) + 1L]] <- cr
    pooled <- auc_trap(cr)
    fold_auc <- cv_comp$AUC[cv_comp$Route == "binary" &
                              cv_comp$Design == design &
                              cv_comp$Model == m]
    roc_labels[[length(roc_labels) + 1L]] <- data.frame(
      Design = design, Model = m, PooledOOFAUC = pooled,
      FoldMeanAUC = if (length(fold_auc)) fold_auc[[1L]] else NA_real_)
  }
}
roc_data <- do.call(rbind, roc_rows)
roc_labels <- do.call(rbind, roc_labels)
write.csv(roc_data, file.path(outdir, "roc_oof_coordinates.csv"), row.names = FALSE)
write.csv(roc_labels, file.path(outdir, "roc_auc_summary.csv"), row.names = FALSE)
p_roc <- ggplot(roc_data,
                aes(FPR, TPR, colour = Model, group = Model)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey60") +
  geom_step(linewidth = 0.55, direction = "hv") +
  facet_wrap(~ Design, nrow = 1,
             labeller = as_labeller(c(species5 = "Five-fold",
                                      species10 = "Ten-fold"))) +
  scale_colour_manual(values = model_cols) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
  labs(title = "Held-out ROC curves for High/Low prediction",
       subtitle = "Pooled held-out curves; labels report the unweighted fold-mean AUC",
       x = "False-positive rate", y = "True-positive rate", colour = "Model") +
  theme_minimal(base_size = 9) +
  theme(legend.position = "bottom", legend.text = element_text(size = 7)) +
  guides(colour = guide_legend(nrow = 2, byrow = TRUE))
save_plot(p_roc, "F01_ROC_AUC_HighLow", 8.2, 4.8)

wilson <- function(x, n, z = 1.96) {
  if (!n) return(c(lower = NA_real_, upper = NA_real_))
  p <- x / n; den <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(lower = max(0, centre - half), upper = min(1, centre + half))
}
cal_rows <- list()
for (design in unique(brec$Design)) {
  for (m in models) {
    z <- brec[brec$Design == design & brec$Model == m, ]
    if (!nrow(z)) next
    if (length(unique(z$PredictedPrHigh)) <= 1L) {
      z$Bin <- 1L
    } else {
      ranks <- rank(z$PredictedPrHigh, ties.method = "first")
      z$Bin <- pmin(5L, ceiling(5 * ranks / nrow(z)))
    }
    for (bb in sort(unique(z$Bin))) {
      q <- z[z$Bin == bb, ]
      ci <- wilson(sum(q$ObservedHigh == 1, na.rm = TRUE), nrow(q))
      cal_rows[[length(cal_rows) + 1L]] <- data.frame(
        Design = design, Model = m, Bin = bb,
        MeanPredicted = mean(q$PredictedPrHigh),
        ObservedFraction = mean(q$ObservedHigh),
        Lower95 = ci[[1L]], Upper95 = ci[[2L]], Records = nrow(q))
    }
  }
}
cal <- do.call(rbind, cal_rows)
write.csv(cal, file.path(outdir, "highlow_calibration_bins.csv"), row.names = FALSE)
p_cal <- ggplot(cal, aes(MeanPredicted, ObservedFraction,
                         colour = Model, group = Model)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey60") +
  geom_errorbar(aes(ymin = Lower95, ymax = Upper95), width = 0,
                alpha = 0.55) +
  geom_line(linewidth = 0.45) + geom_point(size = 1.5) +
  facet_wrap(~ Design, nrow = 1,
             labeller = as_labeller(c(species5 = "Five-fold",
                                      species10 = "Ten-fold"))) +
  scale_colour_manual(values = model_cols) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
  labs(title = "High-probability calibration on held-out records",
       subtitle = "Bins are prediction-rank bins; bars are Wilson 95% intervals",
       x = "Mean predicted High probability", y = "Observed High fraction",
       colour = "Model") +
  theme_minimal(base_size = 9) + theme(legend.position = "bottom")
save_plot(p_cal, "F02_HighLow_calibration", 8.2, 4.8)

p_elpd <- cv_comp
p_elpd$Model <- factor(p_elpd$Model, levels = models)
p_elpd$RouteLabel <- factor(route_labels[p_elpd$Route],
                            levels = unname(route_labels))
p_elpd$DesignLabel <- factor(ifelse(p_elpd$Design == "species5",
                                     "Five-fold", "Ten-fold"),
                             levels = c("Five-fold", "Ten-fold"))
p_elpd$Label <- sprintf("%.2f", p_elpd$DeltaELPD_Null)
p_elpd_plot <- ggplot(p_elpd, aes(Model, DeltaELPD_Null, colour = Model)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey45") +
  geom_point(size = 2) + geom_text(aes(label = Label), vjust = -0.75,
                                   size = 2.6, show.legend = FALSE) +
  facet_grid(RouteLabel ~ DesignLabel, scales = "free_y") +
  scale_colour_manual(values = model_cols) +
  labs(title = "Held-out ELPD difference from Null",
       subtitle = "Positive values indicate higher summed held-out log predictive density; no paired SE is shown",
       x = NULL, y = "ELPD - Null ELPD", colour = "Model") +
  scale_y_continuous(expand = expansion(mult = c(0.06, 0.18))) +
  theme_minimal(base_size = 9) + theme(legend.position = "bottom")
save_plot(p_elpd_plot, "F03_ELPD_delta_Null", 9.0, 8.0)

qrec <- cv_record[cv_record$Route %in% c("joint_bb", "schemeA_tobit") &
                    cv_record$Model %in% main_models &
                    cv_record$Type %in% c("count", "exact") &
                    is.finite(cv_record$ObservedPoint) &
                    is.finite(cv_record$PredictedPoint), ]
qrec$Model <- factor(qrec$Model, levels = main_models)
qrec$RouteLabel <- factor(route_labels[qrec$Route],
                          levels = unname(route_labels[c("joint_bb","schemeA_tobit")]))
p_q <- ggplot(qrec, aes(ObservedPoint, PredictedPoint, colour = Type)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey55") +
  geom_point(alpha = 0.55, size = 1.2) +
  facet_grid(Model ~ RouteLabel) +
  scale_colour_manual(values = type_cols) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
  labs(title = "Held-out quantitative predictions versus observed point records",
       subtitle = "Count/exact point records shown; interval records remain in ELPD scoring",
       x = "Observed ratio", y = "Predicted expected ratio", colour = "Record type") +
  theme_minimal(base_size = 9) + theme(legend.position = "bottom")
save_plot(p_q, "F04_quantitative_predicted_observed", 8.6, 6.0)

main_full <- full[full$Model %in% main_models, ]
main_full$Model <- factor(main_full$Model, levels = main_models)
main_full$SpeciesOrder <- main_full$Species
order_bin <- main_full[main_full$Route == "binary" & main_full$Model == "M1", ]
order_bin <- order_bin[order(order_bin$Point), "Species"]
main_full$Species <- factor(main_full$Species, levels = order_bin)
bp <- main_full[main_full$Route == "binary", ]
p_heat_bin <- ggplot(bp, aes(Model, Species, fill = Point)) +
  geom_tile() + scale_fill_gradientn(colours = c("#F7FBFF","#6BAED6","#08306B"),
                                     limits = c(0,1), name = "Pr High") +
  labs(title = "High-probability predictions across the 365-species panel",
       subtitle = "Species ordered by M1 posterior High probability; Site151 is excluded from all model predictors",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 8) + theme(axis.text.y = element_blank(),
                                       axis.ticks.y = element_blank())
save_plot(p_heat_bin, "F05A_full_panel_High_heatmap", 5.5, 8.0)

rp <- main_full[main_full$Route == "joint_bb", ]
p_heat_ratio <- ggplot(rp, aes(Model, Species, fill = Point)) +
  geom_tile() + scale_fill_gradientn(colours = c("#FFF5F0","#FC8D59","#7F0000"),
                                     limits = c(0,1), name = "Expected ratio") +
  labs(title = "Joint-route expected ratio across the 365-species panel",
       subtitle = "Point is the posterior expected exact-report ratio; interval columns are retained in the source table",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 8) + theme(axis.text.y = element_blank(),
                                       axis.ticks.y = element_blank())
save_plot(p_heat_ratio, "F05B_full_panel_ratio_heatmap", 5.5, 8.0)

width_rows <- rbind(
  data.frame(Model = full$Model, Route = full$Route,
             Interval = "Posterior CrI",
             Width = full$CrI_upper - full$CrI_lower),
  data.frame(Model = full$Model[full$Route != "binary"],
             Route = full$Route[full$Route != "binary"],
             Interval = "Predictive PI",
             Width = full$PI_upper[full$Route != "binary"] -
                     full$PI_lower[full$Route != "binary"])
)
width_rows$Model <- factor(width_rows$Model, levels = models)
width_rows$RouteLabel <- factor(route_labels[width_rows$Route],
                                levels = unname(route_labels))
p_width <- ggplot(width_rows, aes(Model, Width, fill = Interval)) +
  geom_boxplot(outlier.size = 0.25, position = position_dodge(width = 0.75)) +
  facet_wrap(~ RouteLabel, nrow = 1) +
  scale_fill_manual(values = c("Posterior CrI" = "#0072B2",
                                "Predictive PI" = "#D55E00")) +
  coord_cartesian(ylim = c(0,1)) +
  labs(title = "Uncertainty width for full-panel predictions",
       subtitle = "Posterior CrI describes expected ratio uncertainty; PI describes one future exact report",
       x = NULL, y = "Interval width", fill = NULL) +
  theme_minimal(base_size = 9) + theme(legend.position = "bottom")
save_plot(p_width, "F06_prediction_interval_widths", 8.6, 4.8)

ppc_plot <- ppc[is.finite(ppc$Observed), ]
ppc_plot$Model <- factor(ppc_plot$Model, levels = models)
ppc_plot$RouteLabel <- factor(route_labels[ppc_plot$Route],
                              levels = unname(route_labels))
p_ppc <- ggplot(ppc_plot, aes(Model, Observed, colour = Status)) +
  geom_errorbar(aes(ymin = PPC_Lower95, ymax = PPC_Upper95), width = 0.12) +
  geom_point(size = 1.7) +
  facet_grid(Statistic ~ RouteLabel, scales = "free_y") +
  scale_colour_manual(values = c(IN_RANGE = "#009E73",
                                 REVIEW_REQUIRED = "#D55E00")) +
  labs(title = "Training-data posterior predictive checks",
       subtitle = "Points are observed summaries; bars are 95% posterior predictive ranges",
       x = NULL, y = "Observed summary", colour = "Check") +
  theme_minimal(base_size = 8) + theme(legend.position = "bottom",
                                       axis.text.x = element_text(angle = 45,
                                                                  hjust = 1))
save_plot(p_ppc, "F07_training_PPC_checks", 10.5, 9.0)

manifest <- list(
  version = final_status$version,
  final_status = final_status$status,
  figures = list.files(figdir, full.names = FALSE),
  source_files = c("cv_fold_scores_v2.csv", "cv_record_scores_v2.csv",
                   "cv_comparisons_v2.csv", "full_panel_predictions_v2.csv",
                   "model_fit_checks_v2.csv"),
  audit = audit,
  created_at = as.character(Sys.time())
)
jsonlite::write_json(manifest, file.path(outdir, "postprocess_manifest.json"),
                     auto_unbox = TRUE, pretty = TRUE)
cat("POSTPROCESS_COMPLETE\n")
