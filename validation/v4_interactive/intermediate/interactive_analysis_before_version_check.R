# v4交互式主文件：在Ubuntu的R或RStudio中，按顺序执行当前行或选中的完整代码块。
# 本文件调用原有v4函数，不重新编写模型、指标或P值公式；每个代码行都附中文解释。
# 开始前按UBUNTU_zh.md准备R4.6.1和锁定包；从干净的R会话开始，不需要清空其他项目对象。
# 如果整份source本文件，会按顺序执行正式拟合；学习时请逐行或选中完整的花括号代码块执行。

# 1．设置路径、加载同一套参数和函数。
project_dir <- "/home/your_name/v4" # 只把这里改成Ubuntu上解压后的v4目录，例如/home/minfei/project/v4。
root <- normalizePath(project_dir, mustWork = TRUE) # 将项目目录转换为确定存在的绝对路径。
output_dir <- file.path(root, "output_interactive") # 将本次结果放入独立目录；恢复时继续使用同一个目录。
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE) # 如果输出目录还不存在，就创建它。
output_dir <- normalizePath(output_dir, mustWork = TRUE) # 固定输出目录的绝对路径，避免工作目录变化造成混淆。
stopifnot(as.character(getRversion()) == "4.6.1") # 核对本次使用与已验证环境相同的R版本。
source(file.path(root, "R", "load.R"), encoding = "UTF-8") # 只加载公共加载函数，不调用Rscript或解析命令行参数。
load_v4(root) # 加载settings.R和已有底层函数；此行不会开始任何拟合。
source(file.path(root, "interactive_support.R"), encoding = "UTF-8") # 加载交互日志与阶段检查工具；不改变统计函数。
lock <- jsonlite::read_json(file.path(root, "renv.lock"), simplifyVector = TRUE) # 读取原有软件版本锁文件。
expected_versions <- vapply(lock$Packages, function(x) x$Version, character(1)) # 取出锁文件要求的各包版本。
actual_versions <- vapply(names(expected_versions), function(p) if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else NA_character_, character(1)) # 查看当前R会话能使用的对应包版本。
version_mismatch <- names(expected_versions)[is.na(actual_versions) | actual_versions != expected_versions] # 找出未安装或版本不符的包。
print(version_mismatch) # 正常应显示character(0)，否则先按环境说明恢复依赖。
stopifnot(length(version_mismatch) == 0L) # 存在版本差异时在正式拟合之前停止。
check_settings() # 核对单组合、两路线、四模型、固定五折十折和采样参数。
print(MODELS) # 应为Null、M1、M2、M3。
print(ROUTES) # 应为binary和joint_bb。
print(DESIGNS) # 应为fivefold=5、tenfold=10。
print(c(TrainWeighting = TRAIN_WEIGHTING, EvalWeighting = EVAL_WEIGHTING)) # 确认记录等权训练与物种等权评价。
print(SAMPLING) # 查看4链、4000迭代、2000预热及原控制参数。
print(c(SEED = SEED, SEED_OTHER = SEED_OTHER, B_ELPD = B_ELPD, B_OTHER_METRICS = B_OTHER_METRICS)) # 查看明确的拟合与重抽样种子和次数。
print(output_dir) # 确认所有正式结果和日志将写到哪里。

# 2．读取资料并执行原有准备检查。
state <- interactive_step("prepare", root, output_dir, prepare_stage(root, output_dir)) # 读取两张原始表与四张冻结折表，检查身份并保存准备状态；尚未拟合。
observations <- state$observations # 取出已检查并生成High/Low标签的观测表。
sites <- state$sites # 取出365物种的六位点表。
fold_tables <- state$fold_tables # 取出binary和joint_bb各自的五折、十折分组名单。
print(dim(observations)) # 原始观测应有153行。
print(table(observations$Type)) # 查看count、exact、interval三类记录数。
print(length(unique(observations$Species))) # 定量资料应覆盖51个物种。
print(length(state$binary_species)) # 可用于分类的物种应为50个。
print(length(state$joint_species)) # 可用于联合定量建模的物种应为51个。
print(head(fold_tables$fivefold$binary)) # 查看分类五折的物种与折号对应关系。
print(table(fold_tables$fivefold$binary$Fold)) # 查看分类五折中每折分配的物种数。
print(table(fold_tables$tenfold$joint_bb$Fold)) # 查看定量十折中每折分配的物种数。

# 3．查看High/Low分类、位点编码和正式任务清单。
print(table(observations$High, useNA = "ifany")) # 1为HIGH，0为LOW，NA表示该记录不进入分类路线。
print(observations[is.na(observations$High), c("RecordID", "Species", "Type", "Lower", "Upper")]) # 查看因区间跨0.5而不能分类的记录。
point_rows <- observations$Type %in% c("count", "exact") # 只有这两种记录进入MAE、RMSE、Bias和点值PI评价。
print(c(PointRecords = sum(point_rows), PointSpecies = length(unique(observations$Species[point_rows])))) # 应为145条点值记录、48物种。
print(PREDICTOR_SITES) # 查看实际建模位点：3、20、117、196、315。
stopifnot(!"Site151" %in% PREDICTOR_SITES) # 再明确确认Site151没有进入预测矩阵。
encoded_columns <- c("Species", paste0("M1_", PREDICTOR_SITES), paste0("M2_", PREDICTOR_SITES), paste0("M3_", PREDICTOR_SITES)) # 选出三种模型的编码列。
print(head(state$encoded[, encoded_columns])) # 对照查看M1、M2、M3怎样表示同一批位点。
print(lapply(state$blueprints, function(x) dim(x$X))) # 查看各路线/模型的设计矩阵大小；Null没有位点列。
run_plan <- task_plan(state) # 用原有函数生成正式任务清单，不改变种子或分折。
print(table(run_plan$Design)) # 应为full=8、fivefold=40、tenfold=80。
stopifnot(nrow(run_plan) == 128L, !anyDuplicated(run_plan$FitID)) # 确认正式拟合任务恰有128个且身份不重复。

# 4．展开一个代表性CV任务：本段中的示例是正式128项之一，不是额外新增的第129项。
route <- "binary" # 默认展示分类路线；如要看定量输入，可将本行改为joint_bb并重做完整第4段。
model <- "M1" # 默认展示M1；选择其他候选时仍必须来自MODELS。
design <- "fivefold" # 默认查看五折验证；正式程序仍保留五折和十折两套。
fold_id <- 1L # 默认查看第一折。
state <- interactive_step("example_state", root, output_dir, interactive_refresh_state(root, output_dir)) # 恢复磁盘参数并核对准备内容，避免使用临时改动对象。
run_plan <- task_plan(state) # 根据已核对的状态重新取得任务清单。
example_task <- run_plan[run_plan$Route == route & run_plan$Model == model & run_plan$Design == design & run_plan$Fold == fold_id & !is.na(run_plan$Fold), ] # 定位该模型、路线和折的唯一正式任务。
stopifnot(nrow(example_task) == 1L) # 如果选错路线、模型、设计或折号，就在拟合前停止。
print(example_task) # 查看任务ID和该任务实际使用的固定种子。
active_species <- if (route == "binary") state$binary_species else state$joint_species # 取得该路线全部合格物种。
this_fold_table <- state$fold_tables[[design]][[route]] # 读取此路线、此CV设计的冻结分组表。
held_species <- this_fold_table$Species[this_fold_table$Fold == fold_id] # 这些物种是本次留出的测试物种。
train_species <- setdiff(active_species, held_species) # 其余合格物种是本次训练物种。
print(held_species) # 查看本次测试物种名单。
print(train_species) # 查看本次训练物种名单。
stopifnot(length(intersect(train_species, held_species)) == 0L) # 确认同一物种没有同时进入训练和测试。
eligible_rows <- if (route == "binary") !is.na(state$observations$High) else state$observations$Informative # 分类剔除不可分类记录，定量按原Informative规则选择。
train_rows <- which(state$observations$Species %in% train_species & eligible_rows) # 找到本次实际训练记录的行号。
held_rows <- which(state$observations$Species %in% held_species & eligible_rows) # 找到本次实际留出评分记录的行号。
print(head(state$observations[train_rows, ])) # 查看将参与拟合的观测记录。
print(head(state$observations[held_rows, ])) # 查看本次留出的记录，确认它们不进入训练目标。
stan_path <- file.path(root, "stan", "joint_bb.stan") # 指向原有稳定联合模型；分类路线仍使用原brms接口。
spec <- interactive_step("example_spec", root, output_dir, fit_spec(state, route, model, train_species, stan_path, seed = example_task$Seed)) # 生成实际数据、蓝图、先验和模型代码，尚未采样。
print(spec$blueprint$columns) # 查看实际设计矩阵的列及对应类别。
print(spec$blueprint$X[match(train_species, state$encoded$Species), , drop = FALSE]) # 查看本折训练物种使用的完整位点矩阵。
print(PRIORS) # 查看原有先验数值。
print(spec$formula) # 分类路线可查看brms公式；定量路线在此显示NULL，模型由Stan文件定义。
str(spec$data, max.level = 1L) # 分类为训练记录表；定量为Stan数据列表，其中非训练记录train_weight为0。
print(spec$request$seed) # 确认实际采样种子来自example_task，不依赖控制台此前的随机操作。
example_fit_path <- file.path(output_dir, "fits", paste0(example_task$FitID, ".rds")) # 使用与自动阶段完全相同的缓存路径。
bundle <- interactive_step("example_fit", root, output_dir, { # 请选中整个花括号块执行；这一块会真正开始该任务的拟合或核验已有缓存。
  check_interactive_example(root, output_dir, example_task, spec) # 拟合前再次确认展开的规格没有被临时修改。
  fitted <- fit_from_spec(spec, example_fit_path) # 调用原采样/缓存函数；首次拟合需要等待完成，已有同身份缓存可直接复用。
  write_csv_atomic(cbind(example_task, fitted$diagnostics), file.path(output_dir, "interactive_example_diagnostics.csv")) # 即使诊断失败，也先保存此示例的诊断表。
  print(fitted$diagnostics) # 查看R-hat、ESS、发散、树深度和E-BFMI。
  if (!identical(as.character(fitted$diagnostics$Status), "PASS")) stop("示例拟合未通过原有诊断门槛；先查看日志。") # 诊断不通过时停止，不放宽门槛继续。
  validate_fit_cache(fitted, spec) # 核对实际模型、训练资料、采样参数和原生载荷。
  fitted # 将经过检查的拟合对象交给外层bundle变量。
}) # 示例拟合代码块结束。
print(bundle$diagnostics) # 之后可以随时再次查看此对象的诊断。
example_predictions <- interactive_step("example_predictions", root, output_dir, { # 生成该折预测并保存，仍调用原有评分函数。
  scored <- if (route == "binary") binary_record_scores(bundle, state, held_rows) else joint_record_scores(bundle, state, held_rows) # 按对应观测模型预测测试记录并计算原始log score。
  scored$Route <- route # 标记预测路线。
  scored$Model <- model # 标记模型。
  scored$Design <- design # 标记五折或十折设计。
  scored$Fold <- fold_id # 标记本次测试折号。
  scored$TrainWeighting <- TRAIN_WEIGHTING # 明确记录等权训练口径。
  scored$FitKey <- bundle$key # 将这些预测关联到具体拟合缓存身份。
  scored$RunPurpose <- "interactive_example_of_one_formal_CV_task" # 标记它是单任务教学查看表，完整OOF表将在后续自动汇总。
  write_csv_atomic(scored, file.path(output_dir, "interactive_example_predictions.csv")) # 保存这一步的中间预测，不覆盖完整CV输出。
  scored # 返回预测表供控制台查看。
}) # 单折预测代码块结束。
print(head(example_predictions)) # 查看留出预测概率或比例、PI以及原始log score。
example_metrics <- evaluate_evidence(example_predictions) # 只计算本折描述指标，不把一个折的结果当成完整设计的P值。
print(example_metrics) # 查看本折AUC或MAE等，理解该任务的输出。

# 5．完成全部正式任务：原fit_stage循环仍负责完整128项，前面的示例缓存会在相同任务处复用。
evidence <- interactive_step("fit", root, output_dir, { # 请把这一完整代码块作为后续长时间拟合步骤执行。
  state <- interactive_refresh_state(root, output_dir) # 恢复唯一设置并核对输入，避免使用控制台临时改动的资料。
  fit_stage(root, state, output_dir) # 完成全数据及CV任务，逐项写诊断、预测、PPC和拟合文件清单。
}) # 全部拟合步骤结束；若报错或中断，查看interactive_logs/fit.log后按说明恢复。
diagnostics <- read.csv(file.path(output_dir, "fit_diagnostics.csv"), stringsAsFactors = FALSE) # 读取全部任务的诊断汇总。
print(table(diagnostics$Design, diagnostics$Status)) # 查看三类任务是否都通过诊断。
stopifnot(nrow(diagnostics) == 128L, all(diagnostics$Status == "PASS")) # 所有正式任务通过后才能继续评价。

# 6．评价与检验：完整设计的AUC、ELPD/MeanLogScore、MAE、RMSE以及三项BH。
results <- interactive_step("evaluate", root, output_dir, { # 将评价过程和重抽样进度保存在同名日志中。
  state <- interactive_refresh_state(root, output_dir) # 使用已核对的准备状态。
  check_stage_receipt("fit", state, output_dir) # 核对拟合阶段规定的输出文件，没有缺失或被改动。
  evidence <- read.csv(file.path(output_dir, "cv_record_predictions.csv"), stringsAsFactors = FALSE) # 读取完整2440行OOF证据，确保不是仅有示例折。
  check_cv_evidence(state, evidence) # 核对每条记录的物种、折、模型、真值与完整覆盖。
  evaluated <- evaluate_stage(state, evidence, output_dir) # 调用同一套指标、bootstrap和每组三项BH算法。
  stage_receipt("evaluate", state, output_dir) # 保存原流程要求的十个评价产物的身份记录。
  evaluated # 把指标表和检验表返回控制台。
}) # 评价与检验步骤结束。
print(results$cv_fold_metrics) # 查看120行逐折描述指标。
print(results$cv_metrics_summary) # 查看16行完整设计汇总，分类AUC仍是各折等权平均。
test_columns <- c("Route", "Metric", "Design", "Model", "Difference", "SE_approx", "P_approx", "P_BH3") # 选出便于阅读的检验字段。
print(results$hypothesis_tests[, test_columns]) # 查看30项检验的差值、原始P和每组三项BH结果。
print(table(results$hypothesis_tests$FamilyID)) # 应有10个家族，每个恰好3项；Null不参与这些检验。
stopifnot(nrow(results$hypothesis_tests) == 30L, all(table(results$hypothesis_tests$FamilyID) == 3L)) # 核对当前规定的检验数量和家族规模。
print(results$auc_fold_species_support) # 查看各折的HIGH/LOW物种支持，特别注意十折的小样本限制。

# 7．查看365物种预测、PPC并绘制原有七份图件。
predictions <- read.csv(file.path(output_dir, "full_panel_predictions.csv"), stringsAsFactors = FALSE) # 读取第5段完成的8套全数据模型预测。
print(head(predictions)) # 查看Point、CrI、PI和适用范围警告字段。
stopifnot(nrow(predictions) == 2920L) # 核对8个路线/模型组合乘365物种。
ppc <- read.csv(file.path(output_dir, "training_ppc_summary.csv"), stringsAsFactors = FALSE) # 读取训练内模型检查，不能把它当作CV准确度。
print(ppc[ppc$Status == "REVIEW_REQUIRED", ]) # 查看需解释的PPC提示，不删除这些结果。
figure_files <- interactive_step("plot", root, output_dir, { # 生成ROC、校准、指标、检验、预测—观测和物种预测图。
  state <- interactive_refresh_state(root, output_dir) # 确认当前源代码、设置和准备资料仍一致。
  check_stage_receipt("fit", state, output_dir) # 再核对拟合阶段文件。
  check_stage_receipt("evaluate", state, output_dir) # 核对评价阶段文件及其身份。
  plot_stage(state, output_dir) # 调用同一套绘图函数；图文件写入figures，不需要重拟合。
}) # 绘图步骤结束。
print(figure_files) # 列出已生成图件的路径，可以在Ubuntu文件管理器中打开PDF。

# 8．最后保存会话信息并执行完整验收。
capture.output(sessionInfo(), file = file.path(output_dir, "interactive_sessionInfo.txt")) # 保存完成时实际加载的软件版本。
completion <- interactive_finish(root, output_dir) # 只有128拟合对象、完整结果及全部阶段记录通过检查后，才写最终完成状态。
print(completion) # 显示COMPLETE或COMPLETE_WITH_REVIEW_FLAGS；后者保留PPC需复核提示。
print(jsonlite::read_json(file.path(output_dir, "status.json"), simplifyVector = TRUE)) # 读回磁盘中的最终状态，确认写出成功。
list.files(output_dir) # 最后查看输出文件清单，所有中间文件和日志都留在同一运行目录。

# 中断后的恢复方法：重新打开干净R会话，执行第1段；再按INTERACTIVE_zh.md中的恢复代码加载已有状态。
# 从第5段重试时，已有且身份一致的拟合缓存会被检查并复用；不会因为恢复而随机重新生成折表。
# 花括号内多行代码应作为完整表达式执行；不要只执行开头或结尾的一行括号。
