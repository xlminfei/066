# Independent before/after checks using fixed inputs and saved native posteriors.
args<-commandArgs(TRUE);root<-args[1];oldroot<-args[2];formal<-args[3];out<-args[4]
dir.create(out,recursive=TRUE,showWarnings=FALSE)
source(file.path(root,"R/load.R"));load_v4(root)
checks<-list()
ok<-function(name,value) {
  checks[[length(checks)+1L]]<<-data.frame(Check=name,Pass=isTRUE(value))
  write.csv(do.call(rbind,checks),file.path(out,"core_contract_checks.csv"),row.names=FALSE)
  if(!isTRUE(value))stop(name)
}
fails<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
obs<-read.csv(file.path(root,"data/observations.csv"),stringsAsFactors=FALSE)
sites<-read.csv(file.path(root,"data/sites.csv"),stringsAsFactors=FALSE)
folds<-setNames(lapply(names(DESIGNS),function(d)setNames(lapply(ROUTES,function(r)
  read.csv(file.path(root,"data",paste0("folds_",r,"_species_",DESIGNS[[d]],".csv")))),ROUTES)),names(DESIGNS))
state<-prepare_from_tables(obs,sites,folds);state$input_hashes<-check_input_hashes(root)
state$analysis_id<-analysis_identity(root);state$version<-VERSION
plan<-task_plan(state)
ok("128 tasks, 8 full and 120 CV",nrow(plan)==128&&sum(plan$Design=="full")==8&&sum(plan$Design!="full")==120)
ok("fixed RS only",all(plan$TrainWeighting=="record_equal")&&EVAL_WEIGHTING=="species_equal")
ok("formal sampler unchanged",identical(SAMPLING,list(chains=4L,cores=4L,iter=4000L,warmup=2000L,adapt_delta=.99,max_treedepth=12L)))
ok("effective bootstrap sizes unchanged",B_ELPD==2000&&B_OTHER_METRICS==50000)
ok("Stan source byte-identical",sha256_file(file.path(root,"stan/joint_bb.stan"))==sha256_file(file.path(oldroot,"stan/joint_bb.stan")))
ok("count 0/20 remains legal",state$observations$High[state$observations$RecordID=="XLSX_R0002"]==0)
ok("count 30/30 remains legal",state$observations$High[state$observations$RecordID=="XLSX_R0023"]==1)
ok("exact 1 remains legal",state$observations$Exact[state$observations$RecordID=="XLSX_R0029"]==1)
bad<-obs;bad$RecordID[2]<-bad$RecordID[1];ok("duplicate record rejected",fails(validate_input_data(bad,sites)))
bad<-obs;i<-which(bad$Type=="count")[1];bad$Events[i]<-bad$Total[i]+1
ok("invalid count rejected",fails(validate_input_data(bad,sites)))
bad<-obs;i<-which(bad$Type=="exact")[1];bad$Exact[i]<-0
ok("exact zero retains original model boundary",fails(validate_input_data(bad,sites)))
bad<-folds;bad$fivefold$binary$Fold[1]<-NA
ok("NA fold cannot disappear in sort",fails(check_fold_tables(state,bad)))
bad<-folds;bad$fivefold$binary$Fold[1]<-1.5
ok("noninteger fold rejected",fails(check_fold_tables(state,bad)))
bad<-folds;bad$tenfold<-NULL;ok("missing CV design rejected",fails(check_fold_tables(state,bad)))
bad<-folds;bad$fivefold$binary$Species[2]<-bad$fivefold$binary$Species[1]
ok("duplicate species/fold rejected",fails(check_fold_tables(state,bad)))
old<-new.env(parent=.GlobalEnv)
sys.source(file.path(oldroot,"R/bootstrap.R"),envir=old);old$load_v3_modules(oldroot,envir=old)
before<-old$prepare_state(file.path(oldroot,"input"))
for(m in MODELS)for(r in ROUTES) {
  a<-before$blueprints[[blueprint_key(r,m)]];b<-state$blueprints[[blueprint_key(r,m)]]
  ok(paste("identical full design",r,m),identical(a,b))
}
changed<-state$sites;changed$Site151<-"A"
enc2<-encode_panel(changed,state$dictionary)$data
for(m in MODELS)ok(paste("Site151 excluded",m),identical(
  make_design_blueprint(state$encoded,state$joint_species,m)$X,
  make_design_blueprint(enc2,state$joint_species,m)$X))
specs<-list();binary_keys<-character()
for(r in ROUTES)for(m in MODELS)for(d in c("full",names(DESIGNS))) {
  active<-if(r=="binary")state$binary_species else state$joint_species
  held<-if(d=="full")character() else folds[[d]][[r]]$Species[folds[[d]][[r]]$Fold==1L]
  train<-setdiff(active,held);seed<-if(d=="full")SEED else SEED+1L+match(m,MODELS)
  a<-old$fit_spec_v3(before,r,m,train,"record_equal",file.path(oldroot,"stan/joint_bb.stan"),seed=seed)
  b<-fit_spec(state,r,m,train,file.path(root,"stan/joint_bb.stan"),seed=seed)
  same<-isTRUE(all.equal(a$data,b$data,tolerance=0))&&identical(a$blueprint,b$blueprint)&&identical(a$code,b$code)
  if(r=="binary") {
    same<-same&&isTRUE(all.equal(a$prior,b$prior,tolerance=0))&&all(b$data$TrainWeight==1)
    if(d=="full")binary_keys[m]<-binary_template_key(b)
  } else same<-same&&all(b$data$train_weight[b$data$train_rows]==1)&&
      all(b$data$train_weight[-b$data$train_rows]==0)&&!any(state$observations$Species[b$data$train_rows]%in%held)
  specs[[length(specs)+1L]]<-data.frame(Route=r,Model=m,Design=d,DataBlueprintCodePriorEqual=same,Seed=seed)
  ok(paste("fit specification equivalence",r,m,d),same)
  altered<-b;altered$request$seed<-b$request$seed+1L
  ok(paste("changed cache identity rejected",r,m,d),fails(validate_fit_cache(list(request=b$request),altered)))
}
ok("binary templates separated by model and design columns",length(unique(binary_keys))==4)
write.csv(do.call(rbind,specs),file.path(out,"model_spec_equivalence.csv"),row.names=FALSE)
saveRDS(state,file.path(out,"test_state.rds"))
# Native objects are read-only inputs from the already completed v3.4 run.
published<-read.csv(file.path(formal,"results/full_panel_predictions.csv"),stringsAsFactors=FALSE)
oof<-read.csv(file.path(formal,"results/cv_record_predictions.csv"),stringsAsFactors=FALSE)
savedppc<-read.csv(file.path(formal,"results/training_ppc_summary.csv"),stringsAsFactors=FALSE)
replays<-list();numeric_error<-function(a,b,columns) {
  errors<-vapply(columns,function(n) {
    x<-a[[n]];y<-b[[n]];if(!identical(is.na(x),is.na(y)))stop("NA pattern mismatch: ",n)
    if(all(is.na(x)))return(0);max(abs(x[!is.na(x)]-y[!is.na(y)]))
  },numeric(1));max(errors)
}
for(r in ROUTES)for(m in MODELS)for(d in c("full",names(DESIGNS))) {
  tag<-if(d=="full")"full" else paste0(d,"_f1")
  path<-file.path(formal,"runs/fits",paste(r,m,TRAIN_WEIGHTING,tag,sep="__"),"fit.rds")
  b<-readRDS(path)
  if(d=="full") {
    actual<-panel_prediction(b,state)
    reference<-published[published$Route==r&published$Model==m&published$TrainWeighting==TRAIN_WEIGHTING,]
    reference<-reference[match(actual$Species,reference$Species),]
    err<-numeric_error(actual,reference,c("Point","PosteriorMedian","CrI_lower","CrI_upper","PI_lower","PI_upper"))
    ok(paste("applicability flags",r,m),identical(actual$WarningCodes,reference$WarningCodes))
    pp<-ppc_summary_for_bundle(b,state)
    rp<-savedppc[savedppc$Route==r&savedppc$Model==m&savedppc$TrainWeighting==TRAIN_WEIGHTING&
      savedppc$EvalWeighting==EVAL_WEIGHTING,]
    key<-function(z)paste(z$Subset,z$Statistic);rp<-rp[match(key(pp),key(rp)),]
    ok(paste("PPC numeric and flags",r,m),numeric_error(pp,rp,c("Observed","PPC_Lower95","PPC_Median","PPC_Upper95"))<1e-12&&identical(pp$Status,rp$Status))
  } else {
    held<-folds[[d]][[r]]$Species[folds[[d]][[r]]$Fold==1L]
    rows<-which(state$observations$Species%in%held & if(r=="binary")!is.na(state$observations$High) else state$observations$Informative)
    actual<-if(r=="binary")binary_record_scores(b,state,rows) else joint_record_scores(b,state,rows)
    reference<-oof[oof$Design==d&oof$Fold==1L&oof$Route==r&oof$Model==m&oof$TrainWeighting==TRAIN_WEIGHTING,]
    reference<-reference[match(actual$RecordID,reference$RecordID),]
    err<-numeric_error(actual,reference,c("PredictedPrHigh","PredictedPoint","LogPredictiveDensityRaw",
      "PredictedPI_lower","PredictedPI_upper","PIWidth"))
  }
  ok(paste("native posterior replay",r,m,d),is.finite(err)&&err<1e-12)
  replays[[length(replays)+1L]]<-data.frame(Route=r,Model=m,Design=d,Rows=nrow(actual),MaxAbsError=err)
  if(d=="full"&&m=="M3") {
    spec<-fit_spec(state,r,m,if(r=="binary")state$binary_species else state$joint_species,file.path(root,"stan/joint_bb.stan"))
    ok(paste("cross-version data values equal before metadata adapter",r),isTRUE(all.equal(b$data,spec$data,tolerance=0)))
    current<-b;current$data<-spec$data;current$request<-spec$request;current$key<-spec$key;current$version<-VERSION
    current$payload_hash<-fit_payload_hash(current$fit)
    ok(paste("native cache valid",r),!fails(validate_fit_cache(current,spec)))
    tampered<-current;tampered$payload_hash<-"bad"
    ok(paste("tampered native cache rejected",r),fails(validate_fit_cache(tampered,spec)))
  }
  rm(b);invisible(gc(FALSE))
}
write.csv(do.call(rbind(replays),file.path(out,"posterior_replay_checks.csv"),row.names=FALSE)
write_json_atomic(list(status="PASS",checks=length(checks),fit_specs=length(specs),native_objects=length(replays),
  full_panel_rows=sum(vapply(replays,function(x)if(x$Design=="full")x$Rows else 0,numeric(1))),
  maximum_posterior_error=max(vapply(replays,function(x)x$MaxAbsError,numeric(1))),
  new_mcmc_fits=0),file.path(out,"core_status.json"))
cat("V4_CORE_AND_NATIVE_REPLAY_PASS",length(checks),"checks\n")
