args<-commandArgs(TRUE);repo<-args[1];root<-file.path(repo,"v4");out<-args[2]
source(file.path(root,"R/load.R"));load_v4(root)
state<-prepare_stage(root,out)
src<-file.path(repo,"validation/v4/orchestration")
files<-c("roc_coordinates.csv","calibration_bins.csv","cv_metrics_summary.csv",
         "hypothesis_tests.csv","quantitative_plot_source.csv","quantitative_bias_summary.csv",
         "full_panel_predictions.csv")
for(n in files)stopifnot(file.copy(file.path(src,n),file.path(out,n),overwrite=FALSE))
before<-vapply(files,function(n)sha256_file(file.path(out,n)),character(1))
plot_stage(state,out);check_stage_receipt("plot",state,out)
stopifnot(identical(before,vapply(files,function(n)sha256_file(file.path(out,n)),character(1))))
write_json_atomic(list(status="PASS",purpose="plot_only_replay_of_saved_predictions",
  new_fits=0L,source_tables_unchanged=TRUE,files=as.list(before),analysis_id=state$analysis_id),
  file.path(out,"plot_status.json"))
all_r<-c(list.files(root,pattern="[.]R$",recursive=TRUE,full.names=TRUE),
  list.files(file.path(repo,"validation/v4"),pattern="[.]R$",full.names=TRUE))
for(f in all_r)parse(f)
write_json_atomic(list(status="PASS",parsed_current_R_files=length(all_r),files=all_r),
  file.path(out,"syntax_status.json"))
cat("FINAL_PLOTS_AND_SYNTAX_PASS\n")
