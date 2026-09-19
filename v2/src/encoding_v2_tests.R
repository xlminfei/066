root <- normalizePath(Sys.getenv("V2_ROOT", getwd()), winslash = "/", mustWork = TRUE)
run <- file.path(root, "runs", "formal_v2")
st <- readRDS(file.path(run, "prepared_v2.rds"))
stopifnot(identical(st$version, "ratio_analysis_v2_joint_bb_vs_schemeA_site151_excluded_20260918"))
stopifnot(nrow(st$obs) == 153L, nrow(st$panel) == 365L,
          length(st$binary_species) == 50L, length(st$joint_species) == 51L)
stopifnot(identical(st$site_cols,
                    c("Site3", "Site20", "Site117", "Site151", "Site196", "Site315")))
stopifnot(identical(st$model_sites,
                    c("Site3", "Site20", "Site117", "Site196", "Site315")))
stopifnot(all(vapply(st$blueprints, function(x) all(is.finite(x$X)), logical(1))))
stopifnot(all(vapply(st$blueprints, function(x) ncol(x$X) == length(x$columns), logical(1))))
stopifnot(all(vapply(st$blueprints, function(x) x$parameter_columns >= 1L, logical(1))))
stopifnot(identical(st$blueprints$joint_Site315$levels$Site315,
                    st$blueprints$joint_M1$levels$Site315))
stopifnot(!any(grepl("Site151", unlist(lapply(st$blueprints, `[[`, "columns")))))
stopifnot(identical(st$blueprints$joint_M2$levels$Site3,
                    c("CKST", "other", "MISSING")))
for (g in c("M1", "M2", "M3")) {
  b <- st$blueprints[[paste0("joint_", g)]]
  stopifnot(all(vapply(b$levels, function(x) "MISSING" %in% x, logical(1))))
}
pre <- jsonlite::read_json(file.path(root, "review", "preflight_v2.json"), simplifyVector = TRUE)
stopifnot(all(pre$tenfold_binary_gate))
jsonlite::write_json(list(status = "PASS", complete_dummy_columns = TRUE,
                          unseen_categories_are_numeric_capable = TRUE,
                          tenfold_gate = pre$tenfold_binary_gate),
                     file.path(root, "review", "encoding_v2_tests.json"),
                     auto_unbox = TRUE, pretty = TRUE)
cat("ENCODING_V2_TESTS_PASS\n")
