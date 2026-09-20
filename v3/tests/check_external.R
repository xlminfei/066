#!/usr/bin/env Rscript
root <- Sys.getenv("V3_ROOT", unset = "/project/v3")
for (f in c("config.R", "data_encoding.R", "weights.R", "metrics.R", "applicability.R", "cache_io.R", "fitting.R", "prediction.R")) {
  source(file.path(root, "R", f), local = TRUE)
}
state <- readRDS(file.path(root, "runs", "prepared_v3.rds"))
paths <- list.files(file.path(root, "runs", "smoke"), pattern = "fit\\.rds$", full.names = TRUE, recursive = TRUE)
if (length(paths) < 2L) stop("Smoke fit bundles are missing")
bundles <- list()
for (p in paths) {
  b <- readRDS(p)
  bundles[[paste(b$route, b$model, b$train_weighting, sep = "|")]] <- b
}
for (route in c("binary", "joint_bb")) {
  key <- paste(route, "M1", "species_equal", sep = "|")
  if (is.null(bundles[[key]])) stop("Missing smoke bundle ", key)
}
new_sites <- state$sites[1:3, , drop = FALSE]
out <- external_prediction_table(state, bundles, new_sites, models = "M1", train_weightings = "species_equal")
stopifnot(nrow(out) == 3L * 2L * 1L * 1L,
          all(out$Species %in% new_sites$Species),
          all(is.finite(out$Point)), all(out$Point >= 0 & out$Point <= 1))
cat("EXTERNAL PROJECTION PASS\n")
