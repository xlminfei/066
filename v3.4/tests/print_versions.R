packages <- c("brms", "rstan", "posterior", "digest", "jsonlite")
out <- c(R = R.version.string, setNames(vapply(packages, function(p) as.character(packageVersion(p)), character(1)), packages))
cat(paste(names(out), out, sep = "="), sep = "\n")
