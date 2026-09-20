#!/usr/bin/env Rscript
root <- Sys.getenv("V3_ROOT", unset = "/project/v3")
files <- c(list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE),
           list.files(file.path(root, "src"), pattern = "\\.R$", full.names = TRUE),
           list.files(file.path(root, "tests"), pattern = "\\.R$", full.names = TRUE))
for (f in files) {
  parse(file = f)
  cat("PARSE PASS ", f, "\n", sep = "")
}
