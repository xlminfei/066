args<-commandArgs(TRUE);root<-args[1];formal<-args[2]
source(file.path(root,"R/load.R"));load_v4(root)
state<-read_frozen_state(root);state$input_hashes<-check_input_hashes(root)
b<-readRDS(file.path(formal,"runs/fits/joint_bb__M3__record_equal__full/fit.rds"))
spec<-fit_spec(state,"joint_bb","M3",state$joint_species,file.path(root,"stan/joint_bb.stan"))
current<-b;current$request<-spec$request;current$key<-spec$key;current$version<-VERSION;current$payload_hash<-fit_payload_hash(current$fit)
print(c(request=identical(current$request,spec$request),key=identical(current$key,spec$key),
  data=identical(current$data,spec$data),blueprint=identical(current$blueprint,spec$blueprint),
  code=identical(current$code,spec$code),species=identical(current$train_species,spec$request$training_species),
  route=identical(current$route,spec$request$route),model=identical(current$model,spec$request$model),
  tw=identical(current$train_weighting,TRAIN_WEIGHTING)))
print(all.equal(current$data,spec$data));print(all.equal(current$blueprint,spec$blueprint))
tryCatch(validate_fit_cache(current,spec),error=function(e)cat("CACHE_ERROR:",conditionMessage(e),"\n"))
print(b$request$sampling);print(spec$request$sampling)
for(a in b$fit@stan_args)print(list(seed=a$seed,iter=a$iter,warmup=a$warmup,control=a$control[c("adapt_delta","max_treedepth")]))
