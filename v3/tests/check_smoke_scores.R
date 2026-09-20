#!/usr/bin/env Rscript
root <- Sys.getenv("V3_ROOT", unset = "/project/v3")
for (f in c("config.R", "data_encoding.R", "weights.R", "metrics.R", "applicability.R", "cache_io.R", "fitting.R", "prediction.R", "cross_validation.R")) {
  source(file.path(root, "R", f), local = TRUE)
}
state <- readRDS(file.path(root, "runs", "prepared_v3.rds"))
paths <- list.files(file.path(root, "runs", "smoke"), pattern = "fit\\.rds$", full.names = TRUE, recursive = TRUE)
bundles <- list()
for (p in paths) { b <- readRDS(p); bundles[[b$route]] <- b }
held_b <- which(state$observations$Species %in% state$binary_species[1:3])
held_j <- which(state$observations$Species %in% state$joint_species[1:3] & state$observations$Informative)
eb <- binary_record_scores(bundles[["binary"]], state, held_b)
ej <- joint_record_scores(bundles[["joint_bb"]], state, held_j)
stopifnot(nrow(eb) > 0, nrow(ej) > 0, all(is.finite(eb$LogPredictiveDensityRaw)),
          all(is.finite(ej$LogPredictiveDensityRaw)), is.finite(evaluate_evidence(eb, "species_equal", "binary")$ELPD),
          is.finite(evaluate_evidence(ej, "species_equal", "joint_bb")$ELPD))
cat("SMOKE SCORE PASS\n")
