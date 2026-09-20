#!/usr/bin/env Rscript
root <- Sys.getenv("V3_ROOT", unset = "/project/v3")
source(file.path(root, "R", "config.R"), local = TRUE)
source(file.path(root, "R", "data_encoding.R"), local = TRUE)
source(file.path(root, "R", "weights.R"), local = TRUE)
source(file.path(root, "R", "cross_validation.R"), local = TRUE)
state <- readRDS(file.path(root, "runs", "prepared_v3.rds"))
stopifnot(identical(length(state$binary_species), 50L), identical(length(state$joint_species), 51L))
for (model in c("M1", "M2", "M3")) {
  for (route in c("binary", "joint")) {
    bp <- state$blueprints[[paste(route, model, sep = "_")]]
    stopifnot(!any(grepl("Site151", bp$columns)), any(grepl("Site315", bp$columns)))
  }
}
b5 <- make_binary_folds_v3(state, 5L, 20260925L)
b10 <- make_binary_folds_v3(state, 10L, 20260926L)
stopifnot(all(binary_fold_has_both(state, b5)), all(binary_fold_has_both(state, b10)))
for (f in list(b5, b10)) stopifnot(!anyDuplicated(f$Species), setequal(f$Species, state$binary_species))
cat("PREPARED CONTRACT PASS\n")
