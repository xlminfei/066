markdown_table_v3 <- function(x) {
  if(!nrow(x))return("No computed rows available.")
  x[]<-lapply(x,function(v) {if(is.numeric(v))v<-formatC(v,digits=5,format="g");v<-as.character(v);v[is.na(v)]<-"NA";gsub("|","/",v,fixed=TRUE)})
  c(paste0("| ",paste(names(x),collapse=" | ")," |"),paste0("|",paste(rep("---",ncol(x)),collapse="|"),"|"),apply(x,1,function(z)paste0("| ",paste(z,collapse=" | ")," |")))
}
write_results_report_v3 <- function(root) {
  res<-file.path(root,"results");required<-c("cv_metrics_summary.csv","model_vs_null.csv","training_method_comparisons.csv","training_ppc_summary.csv","quantitative_bias_summary.csv","quantitative_plot_source.csv")
  for(f in required)if(!file.exists(file.path(res,f)))stop("Report requires computed output: ",f)
  cv<-read.csv(file.path(res,required[1]));mod<-read.csv(file.path(res,required[2]));train<-read.csv(file.path(res,required[3]));ppc<-read.csv(file.path(res,required[4]))
  bias<-read.csv(file.path(res,"quantitative_bias_summary.csv"),stringsAsFactors=FALSE)
  lines<-c("# v3.2 computed analysis report","",paste("Version:",V3_VERSION),"",
    "Purpose: predict a new species from a frozen six-site input table; Site151 is applicability metadata, five other sites enter M1/M2/M3. Models compare joint coding against Null, not causal site effects.","",
    "Primary comparison: species-equal evaluation in fivefold species-grouped CV. Tenfold and record-equal evaluation are supplementary. Four combinations reuse two fits, not four independent experiments.","",
    "AUC is the equal-fold mean. PooledAUC uses all OOF predictions and is distinct. Log score/MAE/RMSE use weights computed over each metric's complete valid-record set. ELPD is a scaled weighted log-score sum (weight sum=N); compare MeanLogScore across weighting choices.","",
    "Intervals in model comparisons are conditional species-cluster bootstrap intervals of fixed OOF predictions, excluding refitting and model-selection uncertainty. Approximate P/BH values are exploratory; degenerate or fewer-than-ten-species cases do not receive a P value. Training species may not represent every target species.","",
    "The weighted likelihood N/(S R_s) fixes a relative species contribution and overall likelihood scale, not N independent observations or automatic frequentist interval coverage. Do not duplicate records to improve apparent precision.","",
    "## All four training/evaluation combinations","",markdown_table_v3(cv),"",
    "## Quantitative point bias and observed-versus-predicted plot","",
    "Bias = weighted mean(predicted minus observed), on the same count/exact point subset and weights as MAE/RMSE. Positive means overprediction, negative means underprediction. Interval observations are never imputed as points. Zero mean bias can coexist with large absolute errors.","",
    "LogScoreSpeciesUsed/LogScoreRecordsUsed describe the log-score subset; PointSpeciesUsed/PointRecords describe MAE/RMSE/Bias; PISpeciesUsed/PIRecords describe point PI coverage and width. Legacy SpeciesUsed still denotes the log-score set, not all adjacent metrics.","",
    markdown_table_v3(bias),"",
    "See figures/quantitative_predicted_observed.pdf and results/quantitative_plot_source.csv. Plotted markers are individual count/exact reports; marker area represents evaluation weight; the diagonal indicates equality.","",
    "## Models versus Null","",markdown_table_v3(mod),"","## Training methods (species minus record)","",markdown_table_v3(train),"",
    "## Posterior predictive checks","","Observed and replicated statistics use the same record subset, observation type and evaluation weights. count simulations use each observed Total; exact reports use the one-inflated Beta. Interval records are not imputed as points. PPC uses training data and is not independent validation.","",markdown_table_v3(ppc),"",
    "Full-panel Point is the posterior mean; CrI describes uncertainty in the expected quantity. Joint full-panel PI describes a future exact-type report without a specified denominator. CV count PI uses the observed denominator; interval overlap is descriptive and is not point coverage.")
  dir.create(file.path(root,"reports"),showWarnings=FALSE,recursive=TRUE)
  writeLines(lines,file.path(root,"reports","REPORT_v3_2.md"),useBytes=TRUE)
}
export_model_package_v3 <- function(root,state,bundles,path) {
  wanted<-unlist(lapply(V3_ROUTES,function(r)unlist(lapply(V3_MODELS,function(m)paste(r,m,V3_TRAIN_WEIGHTINGS,sep="|")))))
  if(length(bundles)!=16L||!setequal(names(bundles),wanted))stop("Portable export requires the complete sixteen-fit grid")
  for(b in bundles)if(b$diagnostics$Status!="PASS")stop("Portable export requires accepted diagnostics")
  portable<-lapply(bundles,function(b) {
    list(version=b$version,key=b$key,request=b$request,route=b$route,model=b$model,train_weighting=b$train_weighting,train_species=b$train_species,blueprint=b$blueprint,posterior=extract_parameters_v3(b),diagnostics=b$diagnostics)
  })
  obj<-list(version=V3_VERSION,config=read_config_v3(root),state=list(dictionary=state$dictionary),bundles=portable)
  obj$digest<-sha256_object(obj);save_rds_atomic(obj,path)
  code_dir<-file.path(dirname(path),"R");dir.create(code_dir,recursive=TRUE,showWarnings=FALSE)
  for(f in c("config.R","data_encoding.R","weights.R","metrics.R","applicability.R","prediction.R","reporting.R"))file.copy(file.path(root,"R",f),code_dir,overwrite=TRUE)
  writeLines(c("Portable posterior model package. Requires R, digest and jsonlite; no compiler or RDS refitting.","Source all bundled R files (config.R first), then call predict_model_package_v3(package_path, new_sites, output_path).","Do not infer new residue coordinates from whole proteins; input remains the frozen six-site table."),file.path(dirname(path),"README.txt"))
  invisible(path)
}
predict_model_package_v3 <- function(path,new_sites,output_path=NULL) {
  obj<-readRDS(path);hash<-obj$digest;obj$digest<-NULL
  if(!identical(hash,sha256_object(obj)))stop("Portable model package integrity mismatch")
  if(obj$version!=V3_VERSION)stop("Portable model package version mismatch")
  apply_analysis_config(obj$config)
  for(b in obj$bundles)if(b$diagnostics$Status!="PASS")stop("Portable model lacks accepted diagnostics")
  external_prediction_table(obj$state,obj$bundles,new_sites,output_path)
}
