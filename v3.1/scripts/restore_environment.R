#!/usr/bin/env Rscript
# Restore and verify the complete R dependency closure used by v3.1.
# Supported host: Ubuntu 24.04 with the pinned R 4.6.1 runtime (or the Dockerfile).
options(warn = 1, repos = c(CRAN = "https://cloud.r-project.org", RSPM = "https://packagemanager.posit.co/cran/latest"))
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  i <- match(name, args)
  if (is.na(i)) return(default)
  if (i == length(args)) stop("Missing value for ", name)
  args[[i + 1L]]
}
script <- sub("^--file=", "", commandArgs()[grep("^--file=", commandArgs())][1L])
lockfile <- normalizePath(arg_value("--lockfile", file.path(dirname(dirname(script)), "renv.lock")), mustWork = TRUE)
library_path <- arg_value("--library", .libPaths()[1L])
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
library_path <- normalizePath(library_path, mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
if (!identical(as.character(getRversion()), "4.6.1")) stop("The validated runtime requires R 4.6.1; found ", getRversion())
# Do not let bspm replace a requested archived source with an unpinned apt package.
if (requireNamespace("bspm", quietly = TRUE)) bspm::disable()
renv_version <- "1.2.4"
renv_sha256 <- "e63c637dc785d55848d9dbc6c9599378103803efd47c1f3f1f82057c00575e8c"
installed_version <- function(package) {
  path <- find.package(package, quiet = TRUE)
  if (!length(path)) return(NA_character_)
  as.character(utils::packageDescription(package, lib.loc = dirname(path), fields = "Version"))
}
if (!identical(installed_version("renv"), renv_version)) {
  tarball <- tempfile(fileext = ".tar.gz")
  urls <- c(sprintf("https://cran.r-project.org/src/contrib/renv_%s.tar.gz", renv_version),
            sprintf("https://cran.r-project.org/src/contrib/Archive/renv/renv_%s.tar.gz", renv_version))
  downloaded <- FALSE
  for (url in urls) {
    downloaded <- isTRUE(tryCatch({download.file(url, tarball, mode = "wb", quiet = FALSE); TRUE}, error = function(e) FALSE))
    if (downloaded) break
  }
  if (!downloaded) stop("Could not retrieve the pinned renv bootstrap source")
  sha_program <- Sys.which("sha256sum")
  if (!nzchar(sha_program)) stop("Ubuntu sha256sum is required to verify the renv bootstrap source")
  actual_sha <- strsplit(system2(sha_program, shQuote(tarball), stdout = TRUE), "[[:space:]]+")[[1L]][1L]
  if (!identical(actual_sha, renv_sha256)) stop("renv bootstrap SHA-256 mismatch")
  install.packages(tarball, repos = NULL, type = "source", lib = library_path)
  if (!identical(installed_version("renv"), renv_version)) stop("Pinned renv bootstrap installation failed")
}
lock <- renv::lockfile_read(lockfile)
if (!identical(as.character(getRversion()), lock$R$Version)) stop("R version differs from renv.lock")
expected <- vapply(lock$Packages, function(x) x$Version, character(1))
actual <- vapply(names(expected), installed_version, character(1))
needs_restore <- names(expected)[is.na(actual) | actual != expected]
if (length(needs_restore)) {
  cat("Restoring pinned package versions:", paste(needs_restore, collapse = ", "), "\n")
  renv::restore(project = tempdir(), lockfile = lockfile, library = library_path,
                packages = needs_restore, prompt = FALSE, clean = FALSE)
} else {
  cat("All locked package versions already match; no restoration required.\n")
}
actual <- vapply(names(expected), installed_version, character(1))
wrong <- names(expected)[is.na(actual) | actual != expected]
if (length(wrong)) stop("Package version mismatch after restore: ", paste(wrong, collapse = ", "))
ip <- installed.packages(lib.loc = .libPaths())
roots <- c("brms", "rstan", "posterior", "digest", "jsonlite", "renv")
closure <- unique(c(roots, unlist(tools::package_dependencies(roots, db = ip,
  which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE), use.names = FALSE)))
missing <- setdiff(closure, rownames(ip))
if (length(missing)) stop("Installed dependency closure has missing packages: ", paste(missing, collapse = ", "))
nonbase <- closure[!(ip[closure, "Priority"] %in% "base")]
unlocked <- setdiff(nonbase, names(expected))
if (length(unlocked)) stop("Dependency closure is not fully locked: ", paste(unlocked, collapse = ", "))
# Loading the actual modeling namespaces checks shared-library and namespace compatibility.
for (package in roots) {
  if (!requireNamespace(package, quietly = TRUE)) stop("Cannot load required namespace: ", package)
}
cat("ENVIRONMENT_VERIFIED: R ", as.character(getRversion()), "; ", length(expected), " locked packages; complete Depends/Imports/LinkingTo closure.\n", sep = "")
cat("RUNTIME_LIBRARY=", library_path, "\n", sep = "")
