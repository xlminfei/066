#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
# Read-only input-contract inspection. No fitting, predictions or real-data scores.
obs<-read.csv(file.path(root,"input","observations.csv"),stringsAsFactors=FALSE)
high<-classify_high_low(obs)$High;point<-obs$Type%in%c("count","exact")
counts<-list(status="INPUT_INSPECTION_ONLY",records=nrow(obs),LogScoreSpeciesUsed=length(unique(obs$Species)),BinaryRecords=sum(!is.na(high)),BinarySpecies=length(unique(obs$Species[!is.na(high)])),PointRecords=sum(point),PointSpeciesUsed=length(unique(obs$Species[point])),PISpeciesUsed=length(unique(obs$Species[point])),IntervalOnlySpecies=setdiff(unique(obs$Species),unique(obs$Species[point])),formal_research_fits=0,real_data_predictions_or_scores_computed=FALSE)
stopifnot(counts$records==153L,counts$LogScoreSpeciesUsed==51L,counts$BinaryRecords==152L,counts$BinarySpecies==50L,counts$PointRecords==145L,counts$PointSpeciesUsed==48L,counts$PISpeciesUsed==48L)
write_json_atomic(counts,file.path(root,"review","input_support_counts.json"))
cat("INPUT_SUPPORT_COUNTS_PASS: logscore51 / binary50 / point-and-PI48 species; read-only inspection, no fitting\n")
