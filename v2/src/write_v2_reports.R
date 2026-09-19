root <- normalizePath(Sys.getenv("V2_ROOT", getwd()), winslash = "/", mustWork = TRUE)
out <- file.path(root, "postprocess_20260919")
cmp <- read.csv(file.path(root, "results", "cv_comparisons_v2.csv"), stringsAsFactors=FALSE)
ppc <- read.csv(file.path(root, "results", "model_fit_checks_v2.csv"), stringsAsFactors=FALSE)
full <- read.csv(file.path(root, "results", "full_panel_predictions_v2.csv"), stringsAsFactors=FALSE)
audit <- jsonlite::read_json(file.path(out, "fit_audit_summary.json"), simplifyVector=TRUE)
final <- jsonlite::read_json(file.path(root, "review", "final_v2_status.json"), simplifyVector=TRUE)
status <- read.csv(file.path(out, "full_prediction_status_summary.csv"), stringsAsFactors=FALSE)
external <- read.csv(file.path(out, "external_example_complete_predictions_wide.csv"), stringsAsFactors=FALSE)

fmt <- function(x,d=3) ifelse(is.na(x),"NA",formatC(as.numeric(x),format="f",digits=d))
md_table <- function(df) {
  if(!nrow(df)) return("_没有记录。_")
  cols <- names(df)
  out <- c(paste0("| ",paste(cols,collapse=" | ")," |"),
           paste0("| ",paste(rep("---",length(cols)),collapse=" | ")," |"))
  for(i in seq_len(nrow(df))) out <- c(out,paste0("| ",paste(as.character(df[i,cols]),collapse=" | ")," |"))
  paste(out,collapse="\n")
}

high <- cmp[cmp$Route=="binary",c("Design","Model","AUC","ELPD","DeltaELPD_Null")]
high$Design <- ifelse(high$Design=="species5","五折","十折")
high$AUC <- fmt(high$AUC); high$ELPD <- fmt(high$ELPD,2); high[["DeltaELPD_Null"]] <- fmt(high[["DeltaELPD_Null"]],2)
names(high) <- c("折分","模型","AUC","ELPD","ELPD-Null")
quant <- cmp[cmp$Route!="binary",c("Route","Design","Model","ELPD","DeltaELPD_Null","MAE","PointRecords")]
quant$Route <- ifelse(quant$Route=="joint_bb","联合 beta-binomial","Scheme A")
quant$Design <- ifelse(quant$Design=="species5","五折","十折")
quant$ELPD <- fmt(quant$ELPD,2); quant[["DeltaELPD_Null"]] <- fmt(quant[["DeltaELPD_Null"]],2)
quant$MAE <- fmt(quant$MAE); quant$PointRecords <- as.character(quant$PointRecords)
names(quant) <- c("路线","折分","模型","ELPD","ELPD-Null","MAE","点记录数")
flag <- ppc[ppc$Status=="REVIEW_REQUIRED",c("Route","Model","Subset","Statistic")]
flag$Route <- ifelse(flag$Route=="joint_bb","联合 beta-binomial","Scheme A")
names(flag) <- c("路线","模型","资料子集","检查统计量")
status_summary <- aggregate(Rows~Route+Model+Status,status,sum)
status_summary$Route <- ifelse(status_summary$Route=="binary","High/Low",ifelse(status_summary$Route=="joint_bb","联合 beta-binomial","Scheme A"))
names(status_summary) <- c("路线","模型","状态","物种行数")
finite_full <- all(is.finite(full$Point)) && all(is.finite(full$CrI_lower)) && all(is.finite(full$CrI_upper)) &&
  all(is.finite(full$PI_lower[full$Route!="binary"])) && all(is.finite(full$PI_upper[full$Route!="binary"]))
high5 <- high[high$折分=="五折",]; high10 <- high[high$折分=="十折",]
get_auc <- function(tab,m) as.numeric(tab$AUC[tab$模型==m][1L])
qget <- function(route,design,model,col) as.numeric(cmp[cmp$Route==route & cmp$Design==design & cmp$Model==model,col][1L])

summary_lines <- c(
"# v2 结果、分析和汇总","",
paste0("分析版本：",final$version,"。最终状态：",final$status,"。正式运行采用无树设计；Site151 保留在输入表中，但从 M1/M2/M3 预测变量中排除。"),"",
"## 运行与验证状态","",
paste0("- 全数据拟合：15 个（5 个模型 × 3 条路线），全部通过抽样诊断。"),
paste0("- 留出拟合：225 个（5 个模型 × 3 条路线 × 5/10 折结构）。逐文件审计共核对 240 个拟合，失败数为 ",audit$failures,"。"),
paste0("- 最大 R-hat：",fmt(audit$maximum_Rhat,4),"；最小 bulk ESS：",fmt(audit$minimum_bulk_ESS,1),"；最小 tail ESS：",fmt(audit$minimum_tail_ESS,1),"；divergence：",audit$divergences,"；treedepth 命中：",audit$treedepth_hits,"。"),
paste0("- 365 个面板物种共输出 ",nrow(full)," 行预测；点值和适用区间端点均为有限数：",ifelse(finite_full,"是","否"),"。"),
paste0("- 训练内后验预测检查有 ",nrow(flag)," 个 REVIEW_REQUIRED 行，另有 10 个 interval 描述性行。这不是抽样诊断失败，也不是独立外部验证。"),"",
"## High/Low 路线","",
"AUC 只用于 High/Low 路线。它描述模型把真实 HIGH 排在 LOW 前面的能力；Null 的 AUC 约为 0.5 是随机排序基线。下面的 AUC 是各测试折 AUC 的不加权平均，ROC 曲线本身为留出记录的合并可视化，因此两者不应混称为同一个数。","",
md_table(high),"",
paste0("五折中，M1 的 AUC 为 ",fmt(get_auc(high5,"M1")),"，Site315 为 ",fmt(get_auc(high5,"Site315")),"，M2 为 ",fmt(get_auc(high5,"M2")),"，M3 为 ",fmt(get_auc(high5,"M3")),"。"),
paste0("十折中，M1 的 AUC 为 ",fmt(get_auc(high10,"M1")),"，Site315 为 ",fmt(get_auc(high10,"Site315")),"，M2 为 ",fmt(get_auc(high10,"M2")),"，M3 为 ",fmt(get_auc(high10,"M3")),"。"),
"M1 相对 Site315 的优势在五折和十折中都保持；M2 的 AUC 在五折低于 Site315、十折接近 Site315，不能据此宣称 M2 稳定优于 Site315。M3 在五折略高于 Site315，但十折低于 Site315，应继续作为拓展参考而不是主要结论。","",
"## 定量路线","",
"定量路线不使用 AUC。主要评分是逐条留出记录的 ELPD；MAE 只对 count 和 exact 这类有明确点值的记录作辅助解释，interval 记录仍进入 ELPD，但没有被伪造为一个点。","",
md_table(quant),"",
"联合 beta-binomial 路线保留了 count 记录中的真实 Events/Total；Scheme A 将报告比率作为报告级删失正态敏感性路线。两条路线的 ELPD-Null 均为正，说明相对于 Null，位点模型在这些留出记录上的预测密度更高。paired SE 和正态近似检验见后文；它们用于辅助比较，不能直接写成生物学效应的统计学显著性。",
paste0("联合路线中，M2 的 ELPD-Null 为五折 ",fmt(qget("joint_bb","species5","M2","DeltaELPD_Null"),2),"、十折 ",fmt(qget("joint_bb","species10","M2","DeltaELPD_Null"),2),"; M3 数值更高，但 M3 是拓展模型。M1 五折为 ",fmt(qget("joint_bb","species5","M1","DeltaELPD_Null"),2),"、十折为 ",fmt(qget("joint_bb","species10","M1","DeltaELPD_Null"),2),"。"),
paste0("联合路线中 M2 的五折/十折 MAE 为 ",fmt(qget("joint_bb","species5","M2","MAE"))," / ",fmt(qget("joint_bb","species10","M2","MAE")),"；Scheme A 中为 ",fmt(qget("schemeA_tobit","species5","M2","MAE"))," / ",fmt(qget("schemeA_tobit","species10","M2","MAE")),"。"),"",
"## ELPD 的 paired SE 与近似比较","",
"同一折分、同一路线、同一物种内，先把多条留出记录的 log score 求和，再以物种为配对单位比较模型与 Null 或 Site315。paired SE 按物种差值计算，95% 区间和 p 值采用正态近似；这是模型比较的辅助推断，不是生物学效应的显著性检验。完整 42 项比较和 Benjamini-Hochberg 校正结果见 ELPD_PAIRED_SE_ANALYSIS_zh.md。","",
"High/Low 中，M1 相对 Site315 的差值为五折 -4.18（SE 4.69，p=0.373），十折 2.82（SE 3.09，p=0.362）；AUC 和 ELPD 都不支持 M1 稳定地显著优于 Site315。联合 beta-binomial 中，M2 相对 Site315 的差值为五折 3.65（SE 3.22，p=0.258），十折 3.87（SE 3.16，p=0.221）；方向一致，但近似区间仍跨过 0。整张比较表的 BH 校正 p 值没有低于 0.05。","",
"## 全面板预测与新物种复用","",
"全物种预测表保留三条路线。High/Low 行的 Point 是 High 概率，CrI_lower/upper 是 High 概率的 95% 后验可信区间；联合和 Scheme A 行的 Point 是 expected exact-report ratio，CrI 是期望比率的 95% 后验可信区间，PI 是一个未来 exact 类型报告的 95% 后验预测区间。调用者不需要提供未来分母。","",
"外部预测入口已经用无缺失示例测试：一个普通固定类别输入和一个 M3 未见类别输入。宽表把 High 概率、联合路线比率和两个区间、Scheme A 敏感性路线结果放到同一行；未见类别会输出数值并在状态列标为 unseen_category_extrapolation。","",
"## 资料拟合检查的限制","",
md_table(flag),"",
"PPC 标记主要反映 Scheme A 对端点频率/波动的描述不足，以及部分联合模型统计量落在训练内后验预测范围外。它们需要结合原始实验记录、报告方式和区间定义复核。PPC 是训练资料上的模型检查，不是独立验证；最终预测结论仍应以物种分组留出 ELPD/AUC 和计划中的新物种实验验证为主。","",
"## 输出文件","",
"- 拟合审计摘要：fit_audit_summary.json",
"- 模型比较表：../results/cv_comparisons_v2.csv",
"- 逐折评分：../results/cv_fold_scores_v2.csv",
"- 逐条留出记录评分：../results/cv_record_scores_v2.csv",
"- 全物种预测：../results/full_panel_predictions_v2.csv",
"- 新物种宽表示例：external_example_complete_predictions_wide.csv",
"- ELPD 配对比较：ELPD_PAIRED_SE_ANALYSIS_zh.md 和 paired_elpd_comparisons.csv",
"- 图注：FIGURE_CAPTIONS_zh.md")
writeLines(summary_lines,file.path(out,"RESULTS_ANALYSIS_SUMMARY_zh.md"),useBytes=TRUE)

caption_lines <- c(
"# 图注（v2，中文）","",
"## F01_ROC_AUC_HighLow","",
"High/Low 路线的物种分组留出 ROC 曲线。每个面板对应五折或十折；曲线把相同留出设计下的记录级预测合并用于可视化，图例中的 AUC 是各测试折 AUC 的不加权平均。灰色虚线表示随机排序。AUC 仅用于 High/Low 路线，不用于定量比率路线。","",
"## F02_HighLow_calibration","",
"High/Low 概率校准图。横轴为留出记录的平均预测 High 概率，纵轴为相应预测秩分箱中的实际 High 比例；误差线为二项比例 Wilson 95% 区间。它用于检查概率是否偏高或偏低，不等同于 ROC/AUC。","",
"## F03_ELPD_delta_Null","",
"逐条留出记录 ELPD 相对 Null 的差值。零线表示 Null；正值表示模型的留出预测密度总和更高。图中没有加入 paired SE 或显著性标记，因此不能把点的高低直接解释为统计学显著性。","",
"## F04_quantitative_predicted_observed","",
"定量路线 count/exact 点记录的留出预测与观测对照。虚线为相等线；颜色区分 count 和 exact。interval 记录不被替换成中点，但仍参与 ELPD 评分，因此不出现在这个点值图中。","",
"## F05A_full_panel_High_heatmap","",
"365 个物种的 High 后验概率热图，物种按 M1 的 High 概率排序。M1、M2、M3 的列用于比较固定五位点编码下的预测差异；Site151 保留在输入审计中但不进入任何主模型预测变量。","",
"## F05B_full_panel_ratio_heatmap","",
"365 个物种的联合 beta-binomial expected exact-report ratio 热图。颜色表示点估计，不代表单个未来实验的全部不确定性；对应 95% 后验可信区间和预测区间保存在全物种预测 CSV 中。","",
"## F06_prediction_interval_widths","",
"全物种预测区间宽度。蓝色为 expected quantity 的 95% 后验可信区间宽度，橙色为一个未来 exact 报告的 95% 后验预测区间宽度。预测区间通常更宽，因为它同时包含参数不确定性和未来报告本身的波动。","",
"## F07_training_PPC_checks","",
"训练资料上的后验预测检查。点为观测摘要，误差线为后验预测重复的 95% 范围；橙色表示该摘要落在范围外，需要人工复核。interval coverage 没有单个观测摘要，因此没有画入该点范围图，而在 CSV 中标为描述性检查。","",
"## F06_species_binary、F06_species_joint_bb、F06_species_schemeA_tobit","",
"三组分页图参照第一版 F06 的布局，按 42 个物种一页展示 365 个面板物种和 5 个模型。High/Low 分区画 High 概率和 95% 后验可信区间；联合定量和 Scheme A 分区分别画 expected exact-report ratio、95% 后验可信区间和 95% 后验预测区间。红色边框或空心点表示外推或缺失状态，但仍保留数值。","",
"## F08_paired_ELPD_comparisons","",
"按物种聚合留出 log predictive score 的配对比较。蓝色为相对 Null，橙色为相对 Site315；点为 ELPD 差值，线为物种聚类 paired SE 的 95% 正态近似区间。图中不使用 AUC，也不把近似 p 值解释成显著优越。","",
"所有图均由冻结输入、正式拟合和逐条留出评分表生成；原始 CSV、转换规则、随机种子和模型诊断保留在 v2 目录。")
writeLines(caption_lines,file.path(out,"FIGURE_CAPTIONS_zh.md"),useBytes=TRUE)
cat("REPORTS_COMPLETE\n")
