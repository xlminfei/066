#!/usr/bin/env Rscript
# Environment-only tests; temporary files/libraries are confined to tempdir().
options(warn = 1)
args <- commandArgs(trailingOnly = TRUE)
script <- sub("^--file=", "", commandArgs()[grep("^--file=", commandArgs())][1L])
root <- normalizePath(dirname(dirname(script)), mustWork = TRUE)
lockfile <- file.path(root, "renv.lock")
restore_script <- file.path(root, "scripts", "restore_environment.R")
run_restore <- function(path) {
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(restore_script), "--lockfile", shQuote(path), "--library", shQuote(.libPaths()[1L])),
    stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  list(status = if (is.null(status)) 0L else as.integer(status), output = out)
}
positive <- run_restore(lockfile)
cat(paste(positive$output, collapse = "\n"), "\n")
stopifnot(positive$status == 0L, any(grepl("79 locked packages", positive$output, fixed = TRUE)))
cat("PASS: all 79 locked package versions, full dependency closure, and model namespaces.\n")
lock <- renv::lockfile_read(lockfile)
bad_r <- lock; bad_r$R$Version <- "0.0.0"
bad_r_path <- tempfile(fileext = ".lock"); renv::lockfile_write(bad_r, bad_r_path)
negative_r <- run_restore(bad_r_path)
stopifnot(negative_r$status != 0L, any(grepl("R version differs from renv.lock", negative_r$output, fixed = TRUE)))
cat("PASS: altered R-version lock is rejected.\n")
bad_closure <- lock; bad_closure$Packages$BH <- NULL
bad_closure_path <- tempfile(fileext = ".lock"); renv::lockfile_write(bad_closure, bad_closure_path)
negative_closure <- run_restore(bad_closure_path)
stopifnot(negative_closure$status != 0L, any(grepl("Dependency closure is not fully locked: BH", negative_closure$output, fixed = TRUE)))
cat("PASS: missing transitive dependency in lock is rejected.\n")
# Exercise recovery from a repository, independent of the installed system library.
isolated <- tempfile("isolated-library-"); dir.create(isolated)
renv::restore(project = tempdir(), lockfile = lockfile, library = isolated,
              packages = "abind", prompt = FALSE, clean = FALSE)
stopifnot(identical(as.character(utils::packageDescription("abind", lib.loc = isolated, fields = "Version")),
                    lock$Packages$abind$Version))
cat("PASS: pinned RSPM/CRAN dependency restored into a clean temporary library.\n")
cat("ENVIRONMENT_TESTS_PASS; no MCMC was run.\n")
