evaluate_stage <- function(state, evidence, output_dir) {
  # The state-aware check binds every OOF row to the prepared observations and
  # frozen folds. Metric-only callers still receive pairing and grid checks.
  check_cv_evidence(state, evidence)
  tables <- evaluate_tables(evidence)
  inference <- hypothesis_tests(evidence, tables$cv_metrics_summary)
  tables$hypothesis_tests <- inference$hypothesis_tests
  tables$auc_fold_species_support <- inference$auc_fold_species_support
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (name in names(tables)) write_csv_atomic(tables[[name]], file.path(output_dir, paste0(name, ".csv")))
  save_rds_atomic(inference$bootstrap_draws, file.path(output_dir, "bootstrap_draws.rds"))
  save_rds_atomic(inference$bootstrap_multiplicities, file.path(output_dir, "bootstrap_multiplicities.rds"))
  invisible(tables)
}

if (sys.nframe() == 0L) {
  script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  source(file.path(dirname(normalizePath(script)), "R", "load.R"))
  run_stage_cli("evaluate")
}
