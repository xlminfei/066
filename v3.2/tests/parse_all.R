#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
files<-unlist(lapply(c("R","src","tests"),function(d)list.files(file.path(root,d),"\\.R$",full.names=TRUE)))
if(length(files)<25L)stop("No complete code tree found")
for(f in files)parse(f)
cat("PARSE_PASS",length(files),"R files\n")
