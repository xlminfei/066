#!/usr/bin/env Rscript
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]);root<-normalizePath(dirname(dirname(script)),mustWork=TRUE)
source(file.path(root,"R","bootstrap.R"));load_v3_modules(root)
out<-file.path(root,"review","report_wording_fixture");dir.create(file.path(out,"results"),recursive=TRUE,showWarnings=FALSE)
# Output contract fixture only; no data fitting or scientific numerical result.
for(f in c("cv_metrics_summary.csv","model_vs_null.csv","training_method_comparisons.csv","training_ppc_summary.csv","quantitative_bias_summary.csv","quantitative_plot_source.csv"))write_csv_atomic(data.frame(FixtureOnly=TRUE,Meaning="synthetic_report_contract_fixture"),file.path(out,"results",f))
write_results_report_v3(out)
file<-file.path(out,"reports","REPORT_v3_4.md");text<-paste(readLines(file),collapse="\n")
checks<-c(fixed_route=grepl("same route, CV design, and evaluation weighting",text,fixed=TRUE),different_targets=grepl("Different evaluation weightings define different targets",text,fixed=TRUE),no_cross_target_ranking=grepl("do not rank training methods by comparing their scores across evaluation weightings",text,fixed=TRUE),old_ambiguous_text_absent=!grepl("compare MeanLogScore across weighting choices",text,fixed=TRUE),primary_species_target=grepl("Primary comparison: species-equal evaluation in fivefold",text,fixed=TRUE))
# Clearly mark this generated text fixture, while preserving actual writer output.
writeLines(c("SYNTHETIC REPORT CONTRACT TEST ONLY - NO SCIENTIFIC RESULTS",readLines(file)),file)
old<-readLines(file.path(root,"review","baseline_v3_3","R","reporting.R"))
stopifnot(any(grepl("same route, CV design, and evaluation weighting",old,fixed=TRUE)))
write_csv_atomic(data.frame(Check=names(checks),Pass=unname(checks)),file.path(out,"checks.csv"))
write_json_atomic(list(status=if(all(checks))"PASS" else "FAIL",checks=length(checks),computed_scores_changed=FALSE,posterior_sampling=FALSE),file.path(out,"status.json"))
stopifnot(all(checks));cat("REPORT_COMPARISON_WORDING_PASS: fixed route/design/evaluation; generated report checked\n")
