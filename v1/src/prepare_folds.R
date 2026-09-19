source("/project/work/ratio_analysis_20260914/scripts/common.R",local=.GlobalEnv)
initialize_manual()
fold_overview<-list();fold_manifest<-list()
for(route in c("binary","joint"))for(design in c("species","phylo_distance")) {
  OUTCOME<-route;VARIANT<-"primary"
  run_block("06_留出验证.md","06_FOLDS",overrides=list(CV_TYPE=design))
  fold_manifest[[length(fold_manifest)+1L]]<-data.frame(Outcome=OUTCOME,CVType=CV_TYPE,
    FoldKey=fold_key,Directory=CV_DIR,stringsAsFactors=FALSE)
  for(k in seq_len(CV_K)) {
    held_species<-fold_table$Species[fold_table$Fold==k]
    obs<-prepared$observations[prepared$observations$Species%in%held_species,,drop=FALSE]
    if(OUTCOME=="binary")obs<-obs[!is.na(obs$High),,drop=FALSE]
    fold_overview[[length(fold_overview)+1L]]<-data.frame(Outcome=OUTCOME,CVType=CV_TYPE,Fold=k,
      Species=length(held_species),Records=nrow(obs),High=sum(obs$High==1,na.rm=TRUE),
      Low=sum(obs$High==0,na.rm=TRUE),Unclassified=sum(is.na(obs$High)),
      Count=sum(obs$Type=="count"),Exact=sum(obs$Type=="exact"),Interval=sum(obs$Type=="interval"))
  }
}
write.csv(do.call(rbind,fold_manifest),file.path(analysis_root,"provenance","cv_directory_manifest.csv"),row.names=FALSE)
write.csv(do.call(rbind,fold_overview),file.path(analysis_root,"provenance","cv_fold_composition.csv"),row.names=FALSE)
print(do.call(rbind,fold_overview))
cat("FORMAL_FOLDS_PREPARED\n")
