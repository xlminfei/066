#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
out<-file.path(root,"review","visual_fixture");dir.create(file.path(out,"results"),recursive=TRUE,showWarnings=FALSE)
state<-load_state_v3(root);sp<-state$sites$Species
pred<-expand.grid(Species=sp,Route=V3_ROUTES,Model=V3_MODELS,TrainWeighting=V3_TRAIN_WEIGHTINGS,stringsAsFactors=FALSE)
pred$Point<- .3+.07*match(pred$Model,V3_MODELS);pred$CrI_lower<-pred$Point-.1;pred$CrI_upper<-pred$Point+.1
pred$PI_lower<-ifelse(pred$Route=="joint_bb",.05,NA);pred$PI_upper<-ifelse(pred$Route=="joint_bb",1,NA)
pred$WarningCodes<-ifelse(match(pred$Species,sp)%%7==0,"fixture_warning","");pred$FixtureOnly<-TRUE
plot_species_predictions_base(pred,file.path(out,"figures"))
x<-read.csv(file.path(out,"figures","species_prediction_plot_source.csv"))
stopifnot(nrow(x)==5840L,!anyDuplicated(x[,c("Species","Route","Model","TrainWeighting")]),max(x$Page)==9L)
for(r in V3_ROUTES)for(tw in V3_TRAIN_WEIGHTINGS)for(m in V3_MODELS)for(pg in 1:9) {
 z<-subset(x,Route==r&TrainWeighting==tw&Model==m&Page==pg)
 stopifnot(identical(as.character(z$Species),sp[((pg-1)*42+1):min(pg*42,length(sp))]),identical(as.integer(z$YPosition),rev(seq_len(nrow(z)))))
}
write_json_atomic(list(status="PASS_SYNTHETIC_LAYOUT",rows=nrow(x),pages_per_file=9,files=4,labels="explicit Species match",scientific_results=FALSE),file.path(out,"visual_status.json"))
cat("VISUAL_SOURCE_PASS: 5840 labels/values aligned, four nine-page PDFs; fixture only\n")
