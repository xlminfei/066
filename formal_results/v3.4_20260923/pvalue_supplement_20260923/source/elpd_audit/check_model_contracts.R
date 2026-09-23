args<-commandArgs(TRUE);repo<-args[1];root<-args[2];out<-args[3]
source(file.path(root,"R/bootstrap.R"));load_v3_modules(root)
state<-prepare_state(file.path(root,"input"))
parsed<-parse(file.path(repo,"v2/src/v2_pipeline.R"));env<-new.env(parent=baseenv());chosen<-c("encode_raw","fixed_levels","make_blueprint","formula_from_X","PRIORS","SEED","CHAINS","ITER","WARMUP","ADAPT_DELTA","MAX_TREEDEPTH")
for(e in parsed)if(is.call(e)&&as.character(e[[1]])%in%c("<-","=")&&is.symbol(e[[2]])&&as.character(e[[2]])%in%chosen)eval(e,envir=env)
# Pure helper definitions only; the historical pipeline is never sourced/executed.
env$table<-base::table;env$qr<-base::qr
raw<-read.csv(file.path(repo,"v2/data/sites.csv"),stringsAsFactors=FALSE)
canonical<-function(x){x<-gsub("_C_validated","_C",x,fixed=TRUE);x<-gsub("_K_validated","_K",x,fixed=TRUE);gsub("_non_CKST","_other",x,fixed=TRUE)}
ans<-list()
for(m in V3_MODELS){
 old<-env$make_blueprint(raw,state$joint_species,m,V3_PREDICTOR_SITES)
 new<-make_design_blueprint(state$encoded,state$joint_species,m)
 old_names<-canonical(colnames(old$X));new_names<-canonical(colnames(new$X))
 stopifnot(setequal(old_names,new_names),!anyDuplicated(old_names),!anyDuplicated(new_names))
 aligned<-new$X[match(raw$Species,state$encoded$Species),match(old_names,new_names),drop=FALSE]
 err<-if(length(old$X))max(abs(old$X-aligned)) else 0
 stopifnot(err==0)
 ans[[length(ans)+1]]<-data.frame(Model=m,Species=nrow(old$X),DesignColumns=ncol(old$X),NumericDesignMaxDifference=err,Status="PASS")
}
write.csv(do.call(rbind,ans),file.path(out,"v2_v34_design_matrix_equivalence.csv"),row.names=FALSE)
shared_prior<-names(V3_PRIORS);stopifnot(isTRUE(all.equal(env$PRIORS[shared_prior],V3_PRIORS)))
stopifnot(env$CHAINS==V3_SAMPLING$chains,env$ITER==V3_SAMPLING$iter,env$WARMUP==V3_SAMPLING$warmup,env$ADAPT_DELTA==V3_SAMPLING$adapt_delta,env$MAX_TREEDEPTH==V3_SAMPLING$max_treedepth)
# Aggregated binomial vs per-record Bernoulli, identical parameter likelihood up to constants.
o<-state$observations[!is.na(state$observations$High),];sp<-sort(unique(o$Species));n<-vapply(sp,function(s)sum(o$Species==s),integer(1));h<-vapply(sp,function(s)sum(o$High[o$Species==s]),numeric(1));sid<-match(o$Species,sp);const<-sum(lchoose(n,h));diff<-numeric()
for(offset in c(-1,.3,1.2)){
 p<-plogis(offset+seq_along(sp)/length(sp)-.5)
 diff<-c(diff,sum(dbinom(h,n,p,log=TRUE))-sum(dbinom(o$High,1,p[sid],log=TRUE)))
}
stopifnot(max(abs(diff-const))<1e-10)
jsonlite::write_json(list(status="PASS",design_matrices=4,shared_priors_equal=TRUE,formal_sampling_settings_equal=TRUE,binomial_bernoulli_parameter_likelihood_equivalent=TRUE,likelihood_constant=const,max_equivalence_error=max(abs(diff-const)),old_seed=env$SEED,new_seed=V3_SEED,source_pipeline_executed=FALSE,new_fits=0),file.path(out,"model_contract_checks.json"),auto_unbox=TRUE,pretty=TRUE,digits=16)
cat("MODEL_CONTRACT_CHECK_PASS; pure helpers and fixed probabilities only, no historical pipeline execution or fitting\n")
