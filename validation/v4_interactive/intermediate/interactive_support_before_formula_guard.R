# 交互入口的薄封装：只负责日志、状态、恢复检查，不定义任何统计模型或评价公式。
interactive_status <- function(root, output_dir, step, status, message = NULL) { # 保存当前交互步骤的状态，便于中断后判断进度。
  files <- c("interactive_analysis.R", "interactive_support.R") # 另外记录交互入口自身的来源，不改变原有模型缓存身份。
  hashes <- setNames(vapply(files, function(f) sha256_file(file.path(root, f)), character(1)), files) # 为两个交互文件计算SHA256。
  record <- list(version = VERSION, interface = "interactive_R", stage = step, status = status, at = format(Sys.time(), tz = "UTC", usetz = TRUE), message = message, interface_sha256 = as.list(hashes)) # 汇总本次状态与来源信息。
  write_json_atomic(record, file.path(output_dir, "status.json")) # 通过现有原子写入函数保存状态，避免留下半个JSON文件。
  invisible(record) # 返回状态供检查，但不自动打印重复内容。
} # 状态保存函数结束。
interactive_step <- function(step, root, output_dir, code) { # 执行一个完整R表达式或代码块，并保留成功、报错和中断记录。
  expression <- substitute(code) # 先取得要执行的表达式，避免它在日志开启前提前运行。
  caller <- parent.frame() # 记住调用者环境，使赋值后的对象仍可在R控制台查看。
  dir.create(file.path(output_dir, "interactive_logs"), recursive = TRUE, showWarnings = FALSE) # 创建本次输出目录内的交互日志文件夹。
  log_path <- file.path(output_dir, "interactive_logs", paste0(step, ".log")) # 同一步骤重复运行时，继续追加到对应日志。
  log_connection <- file(log_path, open = "at", encoding = "UTF-8") # 以UTF-8追加模式打开日志，保留之前的运行记录。
  previous_sinks <- sink.number(type = "output") # 记住用户原有的输出重定向层数。
  on.exit({ # 无论正常结束、报错还是中断，都执行清理。
    while (sink.number(type = "output") > previous_sinks) sink(type = "output") # 只撤销本函数增加的输出重定向。
    close(log_connection) # 关闭本函数打开的日志连接。
  }, add = TRUE) # 将清理动作登记到函数退出时。
  sink(log_connection, type = "output", split = TRUE) # 将主会话输出同时显示在控制台并写入日志。
  interactive_status(root, output_dir, step, "RUNNING") # 先标记步骤正在运行，不能预先写成完成。
  cat("\nSTART", step, format(Sys.time(), tz = "UTC", usetz = TRUE), "\n") # 在日志中明确标记本次尝试的开始时间。
  value <- tryCatch(withCallingHandlers(eval(expression, envir = caller), # 在调用者环境真正执行表达式，沿用原有底层函数。
    message = function(m) writeLines(paste("MESSAGE:", conditionMessage(m)), log_connection), # 额外将R消息写入日志，原消息仍会显示。
    warning = function(w) writeLines(paste("WARNING:", conditionMessage(w)), log_connection)), # 保留R警告，不消除或降低诊断要求。
    error = function(e) { # 捕获本步骤发生的错误。
      interactive_status(root, output_dir, step, "FAILED", conditionMessage(e)) # 将失败原因写入状态文件。
      cat("FAILED:", conditionMessage(e), "\n") # 在对应日志中保存错误文字。
      stop(e) # 把错误继续返回控制台，阻止后续语句误当作成功执行。
    }, # 错误处理分支结束。
    interrupt = function(e) { # 捕获用户中断，例如RStudio的Stop或Ctrl+C。
      interactive_status(root, output_dir, step, "INTERRUPTED", "User interrupted the current R step") # 明确记录中断，不写成完成。
      cat("INTERRUPTED: 已保存的缓存和输出保留。\n") # 提示用户之后可以按同一目录恢复。
      stop("步骤已中断；检查日志后再恢复。", call. = FALSE) # 以清楚的错误结束当前表达式。
    }) # 本步骤的错误和中断处理结束。
  interactive_status(root, output_dir, step, paste0(toupper(step), "_COMPLETE")) # 只标记这个步骤完成，不代表整个128项流程完成。
  cat("END", step, "\n") # 标记本次步骤正常结束。
  value # 返回计算结果，使控制台能继续查看其中对象。
} # 交互步骤函数结束。
interactive_refresh_state <- function(root, output_dir) { # 恢复阶段开始前核对输入，并恢复磁盘参数。
  source(file.path(root, "settings.R"), local = environment(fit_spec), encoding = "UTF-8") # 从唯一设置文件恢复参数，避免控制台临时改值影响正式计算。
  load_prepared(root, output_dir) # 调用原有检查：代码身份、输入哈希和实际准备内容必须匹配。
} # 状态恢复函数结束。
check_interactive_example <- function(root, output_dir, task, spec) { # 在真正拟合前核对展开的示例仍是正式计划中的同一任务。
  fresh <- interactive_refresh_state(root, output_dir) # 使用经过冻结输入核对的状态，避免沿用手工改动的数据对象。
  plan <- task_plan(fresh) # 重新取得原有128项任务清单。
  if (!is.data.frame(task) || nrow(task) != 1L || !all(names(plan) %in% names(task))) stop("示例任务不是完整的一行任务。") # 拒绝缺字段或多任务输入。
  index <- match(task$FitID, plan$FitID) # 根据正式任务ID定位该示例。
  if (is.na(index) || !isTRUE(all.equal(task[names(plan)], plan[index, ], check.attributes = FALSE))) stop("示例任务与正式计划不一致。") # 检查模型、路线、折号和种子均未变动。
  route <- task$Route # 读取本任务的路线。
  active <- if (route == "binary") fresh$binary_species else fresh$joint_species # 取得该路线全部有响应资料的物种。
  folds <- fresh$fold_tables[[task$Design]][[route]] # 取得该任务使用的冻结折表。
  held <- folds$Species[folds$Fold == task$Fold] # 找出本折测试物种。
  train <- setdiff(active, held) # 按原流程的物种顺序排除测试物种。
  expected <- fit_spec(fresh, route, task$Model, train, file.path(root, "stan", "joint_bb.stan"), seed = task$Seed) # 用同一底层函数重建应当拟合的规格。
  fields <- c("request", "key", "data", "blueprint", "code", "prior") # 核对真正决定拟合内容的字段，避免只看任务标签。
  for (name in fields) if (!identical(spec[[name]], expected[[name]])) stop("示例规格被修改：", name) # 若训练数据、先验、设计或模型代码变化则停止。
  invisible(TRUE) # 检查通过后才允许下一行开始拟合。
} # 示例规格检查函数结束。
interactive_finish <- function(root, output_dir) { # 使用原有结束检查，只有通过后才写全流程完成状态。
  result <- interactive_step("final_check", root, output_dir, { # 将结束检查的输出和失败原因写入日志。
    state <- interactive_refresh_state(root, output_dir) # 再次读取有可信来源的准备状态。
    check_complete_outputs(state, output_dir) # 执行原有128拟合文件、结果主键、BH3和阶段清单完整性检查。
    ppc <- read.csv(file.path(output_dir, "training_ppc_summary.csv"), stringsAsFactors = FALSE) # 读取训练内PPC检查摘要。
    if (anyNA(ppc$Status)) stop("PPC状态缺失。") # 不允许缺失状态被误当成没有提示。
    review_count <- sum(ppc$Status == "REVIEW_REQUIRED") # 统计需要解释的PPC提示数量。
    list(status = if (review_count > 0L) "COMPLETE_WITH_REVIEW_FLAGS" else "COMPLETE", ppc_review_rows = review_count) # 区分正常完成与完成但含PPC提示。
  }) # 结束核验代码块执行完毕。
  interactive_status(root, output_dir, "final_check", result$status) # 所有核验成功后才写最终完成状态。
  print(result) # 在控制台显示最终状态与PPC提示数量。
  invisible(result) # 返回状态，方便用户保存为对象。
} # 全流程完成函数结束。
