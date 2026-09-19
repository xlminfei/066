root <- normalizePath(Sys.getenv("V2_ROOT", getwd()), winslash = "/", mustWork = TRUE)
outdir <- file.path(root, "postprocess_20260919")
dir.create(outdir, showWarnings=FALSE, recursive=TRUE)
suppressPackageStartupMessages({library(brms);library(rstan);library(posterior)})
expr <- parse(file.path(root, "scripts", "v2_pipeline.R"))
e <- new.env(parent=globalenv())
for(x in expr) if(is.call(x) && identical(x[[1]],as.name("<-"))) {
  name <- as.character(x[[2]])
  rhs <- x[[3]]
  if((is.call(rhs) && identical(rhs[[1]], as.name("function"))) ||
     name %in% c("VERSION","MODELS","ALL_SITES","MODEL_SITES","SEED","CHAINS","CORES","ITER","WARMUP","ADAPT_DELTA","MAX_TREEDEPTH","PRIORS","joint_code","joint_compiled")) eval(x,e)
}
st <- readRDS(file.path(root,"runs/formal_v2/prepared_v2.rds"))
files <- list.files(file.path(root,"runs/formal_v2/fits"), pattern="_(full|cv_.*)\\.rds$",full.names=TRUE)
stopifnot(length(files)==240L)
rows <- list()
for(i in seq_along(files)) {
  f <- files[[i]]
  b <- readRDS(f)
  isfull <- identical(b$tag,"full")
  binary <- b$route=="binary"
  outcome <- if(binary) "binary" else "joint"
  bp <- st$blueprints[[paste0(outcome,"_",b$model)]]
  if(isfull) {
    exp_species <- if(binary) st$binary_species else st$joint_species
    k <- 0L; fold <- 0L
  } else {
    k <- as.integer(sub("^cv_species([0-9]+)_.*","\\1",b$tag))
    fold <- as.integer(sub(".*_f([0-9]+)$","\\1",b$tag))
    fn <- if(binary && k==10L) "folds_binary_candidate_10.csv" else paste0("folds_",outcome,"_species_",k,".csv")
    ff <- read.csv(file.path(root,"results",fn))
    exp_species <- ff$Species[ff$Fold!=fold]
  }
  actual_species <- if(b$route=="schemeA_tobit") unique(st$obs$Species[b$train_rows]) else b$train_species
  identity_ok <- identical(b$version,st$version) && identical(b$blueprint$X,bp$X) &&
    identical(b$blueprint$columns,bp$columns) && setequal(actual_species,exp_species)
  if(binary) {
    input_ok <- setequal(b$data$Species,exp_species) &&
      identical(as.numeric(b$data$HighCount), as.numeric(st$binary_counts$HighCount[match(b$data$Species,st$binary_counts$Species)]))
    code_ok <- TRUE
  } else if(b$route=="joint_bb") {
    input_ok <- identical(b$data$events,as.integer(st$obs$Events[st$obs$Type=="count"])) &&
      identical(b$data$total,as.integer(st$obs$Total[st$obs$Type=="count"])) &&
      identical(b$data$train, as.integer(st$obs$Species %in% exp_species))
    code_ok <- identical(b$code_hash,e$sha_code(e$joint_code)) &&
      !grepl("exp(log_phi_count)+m[s]",rstan::get_stancode(b$fit),fixed=TRUE)
  } else {
    expected <- e$scheme_data(st,b$model,b$train_rows)
    input_ok <- identical(b$data,expected)
    code_ok <- TRUE
  }
  d <- b$diagnostics
  rows[[i]] <- cbind(data.frame(File=basename(f),Route=b$route,Model=b$model,
                   Tag=b$tag,Full=isfull,K=k,Fold=fold,IdentityOK=identity_ok,
                   InputOK=input_ok,CodeOK=code_ok,TrainSpecies=length(actual_species),
                   stringsAsFactors=FALSE),d)
  if(i %% 15L==0L || any(!c(identity_ok,input_ok,code_ok)) || d$Status!="PASS") {
    cat(sprintf("AUDIT %d/%d %s %s identity=%s input=%s code=%s\n",
      i,length(files),basename(f),d$Status,identity_ok,input_ok,code_ok)); flush.console()
  }
  rm(b); gc(verbose=FALSE)
}
tab <- do.call(rbind,rows)
write.csv(tab,file.path(outdir,"fit_audit_all_240.csv"),row.names=FALSE)
fail <- tab[tab$Status!="PASS" | !tab$IdentityOK | !tab$InputOK | !tab$CodeOK,,drop=FALSE]
write.csv(fail,file.path(outdir,"fit_audit_failures.csv"),row.names=FALSE)
jsonlite::write_json(list(status=if(nrow(fail))"REVIEW_REQUIRED" else "PASS",
  full=sum(tab$Full),cv=sum(!tab$Full),failures=nrow(fail),
  diagnosis_pass=sum(tab$Status=="PASS"),maximum_Rhat=max(tab$MaxRhat),
  minimum_bulk_ESS=min(tab$MinBulkESS),minimum_tail_ESS=min(tab$MinTailESS),
  divergences=sum(tab$Divergences),treedepth_hits=sum(tab$TreeDepthHits),
  current_joint_code_hash=e$sha_code(e$joint_code),created_at=as.character(Sys.time())),
  file.path(outdir,"fit_audit_summary.json"),auto_unbox=TRUE,pretty=TRUE)
cat("AUDIT_COMPLETE failures=",nrow(fail),"\n",sep="")
