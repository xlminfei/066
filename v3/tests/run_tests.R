#!/usr/bin/env Rscript
root <- Sys.getenv("V3_ROOT", unset = normalizePath(if (basename(getwd()) == "tests") ".." else getwd(), winslash = "/"))
if (!file.exists(file.path(root, "R", "config.R"))) root <- normalizePath(file.path(root, ".."), winslash = "/")
source(file.path(root, "tests", "test_contracts.R"), local = TRUE)
