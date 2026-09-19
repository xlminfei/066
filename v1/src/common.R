# Orchestration only: all model and preprocessing expressions come from the frozen manual.
analysis_root <- normalizePath("/project/work/ratio_analysis_20260914", winslash="/", mustWork=TRUE)
manual_dir <- file.path(analysis_root,"manual")
read_block <- function(file,id) {
  lines <- readLines(file.path(manual_dir,file),warn=FALSE,encoding="UTF-8")
  start <- which(lines==paste0("<!-- R_BLOCK:",id," -->"))
  if(length(start)!=1L)stop("Missing or repeated manual block: ",id)
  finish <- which(seq_along(lines)>start & lines=="```")[[1L]]
  parse(text=lines[seq.int(start+2L,finish-1L)])
}
run_block <- function(file,id,overrides=list(),target=.GlobalEnv) {
  expressions <- read_block(file,id)
  for(expression in expressions) {
    assigned <- if(is.call(expression) && identical(expression[[1L]],as.name("<-")) && is.name(expression[[2L]])) as.character(expression[[2L]]) else ""
    if(nzchar(assigned) && assigned %in% names(overrides)) assign(assigned,overrides[[assigned]],envir=target)
    else eval(expression,envir=target)
  }
  invisible(NULL)
}
initialize_manual <- function(create=FALSE) {
  run_block("00_开始与使用顺序.md","00_SETTINGS")
  assign("PROJECT_DIR",analysis_root,envir=.GlobalEnv)
  assign("INPUT_DIR",file.path(analysis_root,"input"),envir=.GlobalEnv)
  assign("RUN_TAG","formal_20260914_26e686af86fa",envir=.GlobalEnv)
  assign("RUN_DIR",file.path(analysis_root,"runs","formal_20260914_26e686af86fa"),envir=.GlobalEnv)
  assign("RUN_MODE",if(file.exists(file.path(RUN_DIR,"prepared.rds")))"resume" else "new",envir=.GlobalEnv)
  if(!create && RUN_MODE=="new")stop("Run input preparation first.")
  run_block("00_开始与使用顺序.md","00_PACKAGES")
  run_block("00_开始与使用顺序.md","00_RUN_DIRECTORY")
  invisible(NULL)
}
atomic_json <- function(value,path) {
  temporary <- paste0(path,".tmp.",Sys.getpid())
  jsonlite::write_json(value,temporary,pretty=TRUE,auto_unbox=TRUE,na="null")
  for(attempt in seq_len(100L)) {
    if(suppressWarnings(file.rename(temporary,path)))return(invisible(NULL))
    Sys.sleep(.1)
  }
  stop("Cannot finalize JSON after retrying transient file locks: ",path)
}
