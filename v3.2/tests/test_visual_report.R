#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(script)),"R","bootstrap.R"))
root<-resolve_v3_root();load_v3_modules(root)
out<-file.path(root,"review","visual_fixture_distinct");dir.create(file.path(out,"results"),recursive=TRUE,showWarnings=FALSE)
state<-load_state_v3(root);sp<-state$sites$Species
pred<-expand.grid(Species=sp,Route=V3_ROUTES,Model=V3_MODELS,TrainWeighting=V3_TRAIN_WEIGHTINGS,stringsAsFactors=FALSE)
species_index<-match(pred$Species,sp);model_index<-match(pred$Model,V3_MODELS)
training_index<-match(pred$TrainWeighting,V3_TRAIN_WEIGHTINGS)
pred$Point<-ifelse(pred$Model=="Null",.4+.03*(training_index-1),
  .12+.66*species_index/length(sp)+.035*(model_index-2)+.01*(training_index-1))
width<-ifelse(pred$Model=="Null",.05,.035+.02*(species_index%%7)/6)
pred$CrI_lower<-pred$Point-width;pred$CrI_upper<-pred$Point+width
pred$PI_lower<-ifelse(pred$Route=="joint_bb",pmax(0,pred$Point-.28),NA)
pred$PI_upper<-ifelse(pred$Route=="joint_bb",pmin(1,pred$Point+.32),NA)
pred$WarningCodes<-ifelse(match(pred$Species,sp)%%7==0,"fixture_warning","");pred$FixtureOnly<-TRUE
reference<-pred
# Shuffle all but the first complete species panel; labels and values must still align.
pred<-pred[c(seq_along(sp),rev(seq.int(length(sp)+1,nrow(pred)))),]
plot_species_predictions_base(pred,file.path(out,"figures"))
x<-read.csv(file.path(out,"figures","species_prediction_plot_source.csv"))
stopifnot(nrow(x)==5840L,!anyDuplicated(x[,c("Species","Route","Model","TrainWeighting")]),max(x$Page)==9L)
for(r in V3_ROUTES)for(tw in V3_TRAIN_WEIGHTINGS)for(m in V3_MODELS)for(pg in 1:9) {
 z<-subset(x,Route==r&TrainWeighting==tw&Model==m&Page==pg)
 stopifnot(identical(as.character(z$Species),sp[((pg-1)*42+1):min(pg*42,length(sp))]),identical(as.integer(z$YPosition),rev(seq_len(nrow(z)))))
}
key<-function(z)paste(z$Species,z$Route,z$Model,z$TrainWeighting,sep="|")
ref<-reference[match(key(x),key(reference)),]
for(n in c("Point","CrI_lower","CrI_upper","PI_lower","PI_upper","WarningCodes"))stopifnot(isTRUE(all.equal(x[[n]],ref[[n]],check.attributes=FALSE,tolerance=1e-12)))
for(r in V3_ROUTES)for(tw in V3_TRAIN_WEIGHTINGS)for(m in V3_MODELS) {
 z<-subset(x,Route==r&TrainWeighting==tw&Model==m)
 stopifnot(length(unique(z$Point))==if(m=="Null")1L else 365L)
 if(m=="Null")stopifnot(length(unique(z$CrI_lower))==1L,length(unique(z$CrI_upper))==1L)
}
write_json_atomic(list(status="PASS_DISTINCT_SYNTHETIC_LAYOUT",rows=nrow(x),pages_per_file=9,files=4,labels="explicit Species match; shuffled data; point and every interval checked",Null="constant by design",M1_M2_M3="365 distinct synthetic points each",scientific_results=FALSE),file.path(out,"visual_status.json"))
cat("DISTINCT_VISUAL_PASS: 5840 keyed rows and all endpoints aligned after shuffling; Null constant; M1/M2/M3 distinct dummy values; not research results\n")
