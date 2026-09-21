#!/usr/bin/env Rscript
root <- Sys.getenv("V3_ROOT")
if (!nzchar(root)) stop("Set V3_ROOT to the version directory")
source(file.path(root, "R", "bootstrap.R"))
load_v3_modules(root)
source(file.path(root, "R", "prediction_audit.R"))
source(file.path(root, "tests", "test_prediction_audit.R"), local = new.env(parent = .GlobalEnv))
