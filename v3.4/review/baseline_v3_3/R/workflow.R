read_config_v3 <- function(root) jsonlite::read_json(file.path(root,"config","analysis.json"),simplifyVector=TRUE)
verify_input_contract_v3 <- function(root,cfg) {
  c<-jsonlite::read_json(file.path(root,"input","contract.json"),simplifyVector=TRUE)
  if(c$version!=V3_VERSION||c$records!=cfg$expected_records||c$panel_species!=cfg$expected_panel_species)stop("Input contract version/count mismatch")
  for(n in names(c$input_hashes))if(sha256_file(file.path(root,"input",n))!=c$input_hashes[[n]])stop("Input hash mismatch: ",n)
  invisible(c)
}
make_fold_tables_v3 <- function(state,seed=V3_SEED,output_dir=NULL) {
  ans<-list();offset<-c(fivefold=5L,tenfold=10L)
  for(d in V3_DESIGNS) {
    k<-V3_DESIGN_K[[d]];ans[[d]]<-list(binary=make_binary_folds_v3(state,k,seed+offset[[d]]),joint_bb=make_joint_folds_v3(state,k,seed+offset[[d]]+10L))
    if(!is.null(output_dir))for(r in V3_ROUTES)write_csv_atomic(ans[[d]][[r]],file.path(output_dir,paste0("folds_",r,"_species_",k,".csv")))
  };validate_fold_tables_v3(state,ans);ans
}
task_plan_v3 <- function(state,fold_tables,sampling=V3_SAMPLING,seed=V3_SEED) {
  out<-list()
  for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS)for(design in c("full",names(fold_tables))) {
    active<-if(route=="binary")state$binary_species else state$joint_species
    for(fold in if(design=="full")NA_integer_ else seq_len(V3_DESIGN_K[[design]])) {
      train<-if(design=="full")active else setdiff(active,fold_tables[[design]][[route]]$Species[fold_tables[[design]][[route]]$Fold==fold])
      rows<-which(state$observations$Species%in%train & if(route=="binary")!is.na(state$observations$High) else state$observations$Informative)
      wt<-build_train_weights(state$observations[rows,"Species",drop=FALSE],tw)$weight
      out[[length(out)+1]]<-data.frame(FitID=paste(design,if(is.na(fold))"all" else fold,route,model,tw,sep="__"),Route=route,Model=model,TrainWeighting=tw,Design=design,Fold=fold,
        TrainingDataHash=sha256_object(state$observations[rows,,drop=FALSE]),WeightHash=sha256_object(wt),ConfigHash=sha256_object(list(V3_VERSION,V3_PRIORS,sampling,seed,preparation_identity_v3())),
        Seed=if(design=="full")seed else seed+fold+match(model,V3_MODELS),stringsAsFactors=FALSE)
    }
  };do.call(rbind,out)
}
prepare_stage_v3 <- function(root) {
  cfg<-read_config_v3(root);apply_analysis_config(cfg);verify_input_contract_v3(root,cfg)
  state<-prepare_state(file.path(root,"input"),cfg$expected_panel_species,cfg$expected_records,file.path(root,"runs"))
  folds<-make_fold_tables_v3(state,output_dir=file.path(root,"results"));plan<-task_plan_v3(state,folds)
  write_csv_atomic(plan,file.path(root,"runs","run_plan.csv"))
  write_json_atomic(list(status="PASS",version=V3_VERSION,panel_species=nrow(state$sites),records=nrow(state$observations),binary_species=length(state$binary_species),joint_species=length(state$joint_species),formal_full_tasks=16,formal_cv_tasks=240,input_hashes=as.list(state$input_hashes)),file.path(root,"review","preflight_v3.json"))
  cat("PREFLIGHT_PASS: 256 planned; no formal fit claimed\n");state
}
load_state_v3 <- function(root) {
  cfg<-read_config_v3(root);apply_analysis_config(cfg);verify_input_contract_v3(root,cfg)
  p<-file.path(root,"runs","prepared_v3.rds");if(!file.exists(p))stop("Run prepare first")
  state<-readRDS(p);fresh<-prepare_state(file.path(root,"input"),cfg$expected_panel_species,cfg$expected_records)
  if(!identical(state,fresh))stop("Prepared state no longer matches inputs/encoding configuration; run prepare")
  state
}
load_full_bundles_v3 <- function(root,state,require_pass=TRUE) {
  bundles<-list()
  for(route in V3_ROUTES)for(model in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS) {
    train<-if(route=="binary")state$binary_species else state$joint_species
    spec<-fit_spec_v3(state,route,model,train,tw,file.path(root,"stan","joint_bb.stan"))
    p<-fit_path_v3(root,route,model,tw);if(!file.exists(p))stop("Missing full fit: ",p)
    b<-readRDS(p);validate_fitted_bundle_v3(b,spec,require_pass);bundles[[paste(route,model,tw,sep="|")]]<-b
  };bundles
}
postprocess_v3 <- function(root,evidence=NULL) {
  if(is.null(evidence))evidence<-read.csv(file.path(root,"results","cv_record_predictions.csv"),stringsAsFactors=FALSE)
  dir<-file.path(root,"results");make_roc_outputs(evidence,dir)
  write_quantitative_diagnostics_v32(evidence,dir)
  cal<-list()
  for(ew in V3_EVAL_WEIGHTINGS)for(d in unique(evidence$Design))for(m in unique(evidence$Model))for(tw in unique(evidence$TrainWeighting)) {
    z<-subset(evidence,Route=="binary"&Design==d&Model==m&TrainWeighting==tw)
    if(nrow(z))cal[[length(cal)+1]]<-cbind(data.frame(Design=d,Model=m,TrainWeighting=tw),calibration_bins(z,ew,bootstrap=V3_COMPARISON_BOOTSTRAP))
  }
  write_csv_atomic(do.call(rbind,cal),file.path(dir,"calibration_bins.csv"))
  for(scope in c("design","fold")) {
    suffix<-if(scope=="fold")"_by_fold" else ""
    write_csv_atomic(do.call(rbind,lapply(V3_EVAL_WEIGHTINGS,function(ew)compare_evidence_models(evidence,ew,scope))),file.path(dir,paste0("model_vs_null",suffix,".csv")))
    write_csv_atomic(do.call(rbind,lapply(V3_EVAL_WEIGHTINGS,function(ew)compare_training_methods(evidence,ew,scope))),file.path(dir,paste0("training_method_comparisons",suffix,".csv")))
  }
}
render_outputs_v3 <- function(root) {
  res<-file.path(root,"results");fig<-file.path(root,"figures")
  plot_roc_base(read.csv(file.path(res,"roc_coordinates.csv")),file.path(fig,"ROC_curves.pdf"))
  plot_calibration_base(read.csv(file.path(res,"calibration_bins.csv")),file.path(fig,"calibration_bins.pdf"))
  plot_species_predictions_base(read.csv(file.path(res,"full_panel_predictions.csv")),fig)
  qsource<-read.csv(file.path(res,"quantitative_plot_source.csv"),stringsAsFactors=FALSE)
  qsummary<-read.csv(file.path(res,"quantitative_bias_summary.csv"),stringsAsFactors=FALSE)
  plot_quantitative_diagnostics_v32(qsource,qsummary,file.path(fig,"quantitative_predicted_observed.pdf"))
  write_results_report_v3(root)
}
run_stage_v3 <- function(root,stage,args=list()) {
  state<-if(stage%in%c("all","prepare","preflight"))prepare_stage_v3(root) else load_state_v3(root)
  stan<-file.path(root,"stan","joint_bb.stan");res<-file.path(root,"results")
  if(stage%in%c("prepare","preflight"))return(invisible(TRUE))
  if(stage=="smoke") {
    checks<-list()
    for(r in V3_ROUTES) {
      tr<-if(r=="binary")state$binary_species else state$joint_species
      b<-fit_bundle_v3(state,r,"M1",tr,"species_equal",file.path(root,"runs","smoke"),"smoke",1,stan,iter=300,warmup=150,chains=2,cores=2)
      dr<-binary_prediction_draws(b,state);if(any(!is.finite(dr)))stop("Smoke projection failure")
      checks[[r]]<-b$diagnostics
    }
    write_json_atomic(list(status="PASS_WITH_DIAGNOSTIC_WARNINGS",version=V3_VERSION,purpose="interface_only",diagnostics=checks),file.path(root,"review","smoke_v3.json"));return(invisible(TRUE))
  }
  if(stage%in%c("fit","all")) {
    diagnostics<-list();weights<-list()
    for(r in V3_ROUTES)for(m in V3_MODELS)for(tw in V3_TRAIN_WEIGHTINGS) {
      b<-fit_bundle_v3(state,r,m,if(r=="binary")state$binary_species else state$joint_species,tw,root,stan_path=stan)
      diagnostics[[length(diagnostics)+1]]<-cbind(data.frame(Route=r,Model=m,TrainWeighting=tw,FitKey=b$key),b$diagnostics)
      d<-state$observations[b$request$train_rows,,drop=FALSE];w<-build_train_weights(d[,"Species",drop=FALSE],tw)
      w$RecordID<-d$RecordID;w$Route<-r;w$Model<-m;w$TrainWeighting<-tw;w$Design<-w$Stage<-"full";w$FitKey<-b$key;weights[[length(weights)+1]]<-w
      write_csv_atomic(do.call(rbind,diagnostics),file.path(res,"full_diagnostics.csv"))
      write_csv_atomic(do.call(rbind,weights),file.path(res,"training_weights_full.csv"))
      if(b$diagnostics$Status!="PASS")stop("Formal full fit diagnostic gate failed")
    }
  }
  if(stage%in%c("ppc","all")){run_ppc_stage_v3(state,load_full_bundles_v3(root,state),root,res);write_stage_receipt_v3(root,state,"ppc",c("results/training_ppc_summary.csv","figures/training_ppc_summary.pdf"))}
  if(stage%in%c("cv","all")) {
    folds<-make_fold_tables_v3(state,output_dir=res);ans<-run_cv_v3(state,root,folds,stan)
    postprocess_v3(root,ans$evidence)
    write_stage_receipt_v3(root,state,"cv",file.path("results",c("cv_record_predictions.csv","cv_fold_metrics.csv","cv_metrics_summary.csv","model_vs_null.csv","training_method_comparisons.csv","calibration_bins.csv","roc_coordinates.csv","quantitative_plot_source.csv","quantitative_bias_summary.csv")))
  }
  if(stage%in%c("predict","all")){make_prediction_table(state,load_full_bundles_v3(root,state),file.path(res,"full_panel_predictions.csv"));write_stage_receipt_v3(root,state,"predict","results/full_panel_predictions.csv")}
  if(stage=="external") {
    if(is.null(args$new_data)||!file.exists(args$new_data))stop("--new-data is required")
    external_prediction_table(state,load_full_bundles_v3(root,state),read.csv(args$new_data,check.names=FALSE),args$out%||%file.path(res,"external_predictions.csv"))
  }
  if(stage=="export")export_model_package_v3(root,state,load_full_bundles_v3(root,state),args$out%||%file.path(root,"exports","model_package.rds"))
  if(stage%in%c("report","all")){for(s in c("cv","predict","ppc"))verify_stage_receipt_v3(root,state,s);render_outputs_v3(root);seal_derived_outputs_v3(root,state)}
  if(stage%in%c("audit","all"))audit_plan_v3(state,root,file.path(root,"runs"),file.path(root,"review"))
  invisible(TRUE)
}
run_with_status_v3 <- function(root,stage,fun) {
  path<-file.path(root,"review","last_stage_status.json")
  final<-file.path(root,"review","final_v3_status.json")
  payload<-function(status,message=NULL)list(status=status,stage=stage,version=V3_VERSION,at=format(Sys.time(),tz="UTC",usetz=TRUE),message=message)
  write_json_atomic(payload("RUNNING"),path)
  if(stage%in%c("all","fit","cv","prepare","preflight"))write_json_atomic(payload("INCOMPLETE"),final)
  tryCatch({
    fun();write_json_atomic(payload("STAGE_COMPLETE"),path)
    if(stage=="all") { ppc<-read.csv(file.path(root,"results","training_ppc_summary.csv"));write_json_atomic(payload(if(any(ppc$Status=="REVIEW_REQUIRED"))"COMPLETE_WITH_REVIEW_FLAGS" else "COMPLETE"),final) }
  },error=function(e){write_json_atomic(payload("FAILED",conditionMessage(e)),path);write_json_atomic(payload("FAILED",conditionMessage(e)),final);stop(e)})
}
