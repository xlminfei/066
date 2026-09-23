#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)

plot_species_predictions_base(read.csv(file.path(root,"results","full_panel_predictions.csv")),file.path(root,"figures"))
