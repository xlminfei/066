source("/project/work/ratio_analysis_20260914/scripts/common.R",local=.GlobalEnv)
initialize_manual()
run_block("03_联合比率模型.md","03_STAN_MODEL")
joint_code_hash <- digest::digest(joint_model_code,algo="sha256",serialize=FALSE)
compiled_file <- file.path(analysis_root,"environment","joint_compiled.rds")
legacy_compiled <- "/project/work/verification/joint_compiled.rds"
legacy_hash_file <- "/project/work/verification/joint_compiled.sha256"
reused_compilation <- FALSE
if(file.exists(compiled_file)) {
  joint_compiled <- readRDS(compiled_file)
  stopifnot(identical(readLines(file.path(analysis_root,"environment","joint_compiled.sha256")),joint_code_hash))
} else if(file.exists(legacy_compiled) && file.exists(legacy_hash_file) &&
          identical(readLines(legacy_hash_file),joint_code_hash)) {
  joint_compiled <- readRDS(legacy_compiled)
  stopifnot(inherits(joint_compiled,"stanmodel"))
  saveRDS(joint_compiled,compiled_file)
  reused_compilation <- TRUE
} else {
  run_block("03_联合比率模型.md","03_COMPILE")
  saveRDS(joint_compiled,compiled_file)
}
writeLines(joint_code_hash,file.path(analysis_root,"environment","joint_compiled.sha256"))
writeLines(joint_model_code,file.path(analysis_root,"environment","joint_model.stan"))

# A seeded dispatch witness using the actual data and compiled target, without posterior fitting.
MODEL_NAME<-"Null_U";VARIANT<-"primary"
run_block("03_联合比率模型.md","03_PREPARE")
witness_init <- list(alpha=0,beta=as.array(numeric(stan_data$K)),
  z_phylo=as.array(numeric(0)),sd_phylo=as.array(numeric(0)),rho=.5,
  log_phi_ratio=log(10),log_phi_count=as.array(numeric(0)))
witness <- rstan::sampling(joint_compiled,data=stan_data,init=list(witness_init),
  seed=20260914,chains=1,cores=1,iter=2,warmup=0,algorithm="Fixed_param",refresh=0)
witness_draws <- rstan::extract(witness,pars=c("m","log_lik"))
stopifnot(identical(dim(witness_draws$m),c(2L,365L)),
  all(witness_draws$m==.5),all(is.finite(witness_draws$log_lik)))
atomic_json(list(status="PASS",compiled_code_sha256=joint_code_hash,
  reused_code_only_compilation=reused_compilation,posterior_or_old_data_reused=FALSE,
  seeded_actual_target_dispatch=TRUE,expected_species=365,expected_records=153),
  file.path(analysis_root,"environment","kernel_witness.json"))
cat("STAN_KERNEL_WITNESS_PASS\n")
