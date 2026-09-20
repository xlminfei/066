analysis_fingerprint_v3 <- function(root,state) {
  files<-sort(c(list.files(file.path(root,"R"),"\\.R$",full.names=TRUE),file.path(root,"stan","joint_bb.stan")))
  sha256_object(list(version=V3_VERSION,input=state$input_hashes,config=read_config_v3(root),sources=setNames(vapply(files,sha256_file,character(1)),basename(files))))
}
seal_derived_outputs_v3 <- function(root,state) {
  files<-unlist(lapply(c("results","figures","reports"),function(d)list.files(file.path(root,d),full.names=TRUE,recursive=TRUE)))
  files<-files[!dir.exists(files)]
  data.frame(Path=substring(files,nchar(root)+2),SHA256=vapply(files,sha256_file,character(1)),AnalysisFingerprint=analysis_fingerprint_v3(root,state)) |>
    write_csv_atomic(file.path(root,"review","derived_outputs_manifest.csv"))
}
verify_derived_outputs_v3 <- function(root,state) {
  p<-file.path(root,"review","derived_outputs_manifest.csv");if(!file.exists(p))stop("Missing derived output manifest")
  receipt<-read.csv(p,stringsAsFactors=FALSE)
  if(!nrow(receipt)||any(receipt$AnalysisFingerprint!=analysis_fingerprint_v3(root,state)))stop("Derived outputs belong to a different analysis/code/config")
  for(i in seq_len(nrow(receipt)))if(!file.exists(file.path(root,receipt$Path[i]))||sha256_file(file.path(root,receipt$Path[i]))!=receipt$SHA256[i])stop("Derived output integrity mismatch: ",receipt$Path[i])
  invisible(TRUE)
}

write_stage_receipt_v3 <- function(root,state,stage,files) {
  paths<-file.path(root,files)
  if(any(!file.exists(paths)))stop("Cannot receipt missing outputs")
  write_json_atomic(list(stage=stage,analysis_fingerprint=analysis_fingerprint_v3(root,state),files=as.list(setNames(vapply(paths,sha256_file,character(1)),files))),file.path(root,"review",paste0(stage,"_receipt.json")))
}
verify_stage_receipt_v3 <- function(root,state,stage) {
  p<-file.path(root,"review",paste0(stage,"_receipt.json"));if(!file.exists(p))stop("Missing stage receipt: ",stage)
  receipt<-jsonlite::read_json(p,simplifyVector=TRUE)
  if(receipt$analysis_fingerprint!=analysis_fingerprint_v3(root,state))stop("Stale stage outputs: ",stage)
  if(!length(receipt$files)||is.null(names(receipt$files))||any(!nzchar(names(receipt$files))))stop("Malformed output receipt")
  for(n in names(receipt$files))if(!file.exists(file.path(root,n))||sha256_file(file.path(root,n))!=receipt$files[[n]])stop("Changed stage output: ",n)
}
