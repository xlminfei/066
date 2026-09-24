# 输入、输出与验收数量

## 冻结输入

只读取 data/ 中六张 CSV。两张原输入与四张分折表均从已验证正式结果逐字节复制，SHA-256 固定在 settings.R。

observations.csv 必须有 RecordID、ExperimentID、Species、Type、Events、Total、Exact、Lower、Upper、SourceID。RecordID/ExperimentID 唯一，物种在 sites.csv 中存在。count 填 Events/Total，其余观测字段留空；exact 填 Exact；interval 填 Lower/Upper 且0≤Lower<Upper≤1。

sites.csv 包含 Species 及 Site3、Site20、Site117、Site151、Site196、Site315，365个物种各一行。缺失标记按原约定进入 MISSING。

四张 folds_*_species_5/10.csv 均只需 Species 和 Fold。binary 覆盖50物种，joint_bb 覆盖51物种；Fold 为1..K的整数、每个物种恰有一行。缺折、额外路线、重复物种、非整数或NA折号均拒绝。程序不重新生成折表。

分类规则：count/exact 比例≥0.5为HIGH；interval 的 Upper≤0.5为LOW、Lower≥0.5为HIGH，严格跨越0.5者不进入binary。joint_bb保留合格三类型记录。

| 支持集合 | 记录 | 物种 |
|---|---:|---:|
| 原始观测及定量 log score | 153 | 51 |
| binary | 152 | 50 |
| count/exact 点误差和PI | 145 | 48 |
| 全部预测面板 | — | 365 |

## 主要输出

所有文件写入 output/ 或 --output 指定目录。

| 文件 | 正式预期 |
|---|---|
| run_plan.csv | 128个不同任务：8 full、40 fivefold、80 tenfold |
| fit_diagnostics.csv、fit_manifest.csv | 各128行；诊断、缓存路径、大小及SHA |
| fits/*.rds | 128个真实拟合对象，本地保留以便续跑和复核 |
| cv_record_predictions.csv | 2440行，每条记录在每个模型和CV设计下恰好留出一次 |
| cv_fold_metrics.csv | 120行 |
| cv_metrics_summary.csv | 16行，Null/M1/M2/M3均保留 |
| full_panel_predictions.csv | 2920行，8个模型/路线组合×365物种 |
| hypothesis_tests.csv | 30行，10个家族，各3项；P_approx和P_BH3分列 |
| training_ppc_summary.csv | 64行训练内检查，保留REVIEW_REQUIRED |
| auc_fold_species_support.csv | 15行，五折＋十折的类别/物种支持 |
| calibration_bins.csv | 每个非空箱一行，含支持度和区间状态 |
| quantitative_plot_source.csv、quantitative_bias_summary.csv | count/exact图源和8组Bias摘要 |
| bootstrap_draws.rds、bootstrap_multiplicities.rds | 30组差值、抽样次数/索引与分组，完整保留 |
| analysis_manifest.json、settings_used.R、sessionInfo.txt | 运行来源、参数及环境 |
| status.json、*_receipt.rds | 阶段状态与固定输出清单身份 |

figures/ 包含 ROC_curves.pdf、calibration.pdf、cv_metrics.pdf、hypothesis_tests.pdf、quantitative_predicted_observed.pdf、两条路线各一份分页 species_predictions_*.pdf，以及物种图源CSV。ELPD、MAE、RMSE 都有图；PPC保留摘要表而不再默认生成冗长图册。

## 完成判据

MCMC门槛沿用：R-hat<1.01，bulk/tail ESS≥400，无发散、无树深度命中，各链E-BFMI>0.3，采样参数及相关输出有限。任一正式拟合失败即停止，诊断记录保留。

最终核对128个拟合文件的SHA/大小、诊断任务身份、全部结果表完整主键以及三阶段固定文件集合，拒绝仅行数正确而缺字段/缺模型的表。分步运行会将 prepared 内容与冻结CSV重建结果比较；修改 prepared 中的观测、编码或合法但不同的折分仍会报错。

COMPLETE 表示程序与基础完整性检查完成；存在PPC提示时为 COMPLETE_WITH_REVIEW_FLAGS。它们都不表示模型科学有效性已经确证。新v4正式128项拟合尚未在本次重构任务中执行，验证档案清楚区分旧后验复算、替身调度和新的合成数据拟合。
