read_frozen_state <- function(root) {
  read<-function(n)read.csv(file.path(root,"data",n),stringsAsFactors=FALSE,check.names=FALSE,na.strings=c("","NA"))
  folds<-setNames(lapply(names(DESIGNS),function(d)setNames(lapply(ROUTES,function(r)
    read(paste0("folds_",r,"_species_",DESIGNS[[d]],".csv"))),ROUTES)),names(DESIGNS))
  prepare_from_tables(read("observations.csv"),read("sites.csv"),folds)
}
# Stage 1: read the six frozen CSVs, encode sites once, and check species folds.
prepare_from_tables <- function(observations,sites,fold_tables) {
  v<-validate_input_data(observations,sites)
  obs<-cbind(v$observations,classify_high_low(v$observations));sites<-v$sites
  counts<-build_binary_counts(obs,sites$Species);dictionary<-build_encoding_dictionary(sites)
  encoded<-encode_panel(sites,dictionary)$data
  state<-list(observations=obs,sites=sites,encoded=encoded,dictionary=dictionary,binary_counts=counts,
    binary_species=counts$Species[counts$Trials>0],joint_species=unique(obs$Species[obs$Informative]),
    predictor_sites=PREDICTOR_SITES,fold_tables=fold_tables,blueprints=list())
  check_fold_tables(state)
  for(r in ROUTES)for(m in MODELS)
    state$blueprints[[blueprint_key(r,m)]]<-make_design_blueprint(encoded,
      if(r=="binary")state$binary_species else state$joint_species,m)
  state
}
task_plan <- function(state) {
  rows<-list()
  for(r in ROUTES)for(m in MODELS)for(d in c("full",names(DESIGNS)))
    for(f in if(d=="full")NA_integer_ else seq_len(DESIGNS[[d]])) {
      rows[[length(rows)+1L]]<-data.frame(
        FitID=paste(d,if(is.na(f))"all" else f,r,m,sep="__"),Route=r,Model=m,
        TrainWeighting=TRAIN_WEIGHTING,Design=d,Fold=f,
        Seed=if(d=="full")SEED else SEED+f+match(m,MODELS),stringsAsFactors=FALSE)
    }
  do.call(rbind,rows)
}
prepare_stage <- function(root,output_dir) {
  check_settings();input_hashes<-check_input_hashes(root)
  state<-read_frozen_state(root)
  point<-state$observations$Type%in%c("count","exact")
  counts<-c(panel_species=nrow(state$sites),records=nrow(state$observations),
    binary_records=sum(!is.na(state$observations$High)),binary_species=length(state$binary_species),
    joint_species=length(state$joint_species),point_records=sum(point),
    point_species=length(unique(state$observations$Species[point])))
  if(!identical(as.integer(counts),as.integer(EXPECTED_COUNTS)))stop("Frozen input support counts changed")
  state$version<-VERSION;state$input_hashes<-input_hashes;state$analysis_id<-analysis_identity(root)
  old<-file.path(output_dir,"prepared.rds")
  if(file.exists(old)&&!identical(readRDS(old)$analysis_id,state$analysis_id))
    stop("Existing output belongs to different code/settings; choose a new --output directory")
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  save_rds_atomic(state,old)
  write_csv_atomic(task_plan(state),file.path(output_dir,"run_plan.csv"))
  write_csv_atomic(state$encoded,file.path(output_dir,"panel_encoded.csv"))
  write_csv_atomic(state$binary_counts,file.path(output_dir,"binary_counts.csv"))
  write_json_atomic(list(version=VERSION,analysis_id=state$analysis_id,input_sha256=as.list(input_hashes),
    counts=as.list(counts),planned_full_fits=8L,planned_cv_fits=120L,
    training=TRAIN_WEIGHTING,evaluation=EVAL_WEIGHTING,
    B_ELPD=B_ELPD,B_OTHER_METRICS=B_OTHER_METRICS,
    inference="fixed OOF conditional normal approximation; ten BH families of three",
    prepared_at=format(Sys.time(),tz="UTC",usetz=TRUE)),file.path(output_dir,"analysis_manifest.json"))
  capture.output(sessionInfo(),file=file.path(output_dir,"sessionInfo.txt"))
  file.copy(file.path(root,"settings.R"),file.path(output_dir,"settings_used.R"),overwrite=TRUE)
  cat("PREPARE_PASS: 8 full + 120 CV fits planned; no fit executed\n")
  state
}
if(sys.nframe()==0L) {
  script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
  source(file.path(dirname(normalizePath(script)),"R/load.R"));run_stage_cli("prepare")
}
