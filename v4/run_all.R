# Run all four stages. Individual 01--04 scripts are also executable.
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(normalizePath(script)),"R/load.R"))
run_stage_cli("all")
