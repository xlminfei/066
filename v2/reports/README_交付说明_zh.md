# v2 最终结果与图件交付说明

本目录来自正式版本 `ratio_analysis_v2_joint_bb_vs_schemeA_site151_excluded_20260918`。模型不使用进化树；六个位点仍保留在输入表中，但 Site151 因有响应物种全部为 C 而不进入 M1/M2/M3 预测变量。

正式运行已经完成：15 个全数据模型和 225 个物种分组留出拟合全部通过抽样诊断，240 个 RDS 的输入集合、设计矩阵、代码哈希和诊断审计全部通过。最终状态是 `COMPLETE_WITH_REVIEW_FLAGS`，原因是训练内 PPC 有 20 个需要人工查看的摘要，不是链诊断失败，也不是独立外部验证失败。

## 主要结果文件

- `../results/cv_comparisons_v2.csv`：每条路线、每种折分和每个模型的 ELPD、相对 Null 的 ELPD 差值、High/Low AUC 或定量 MAE。
- `../results/cv_fold_scores_v2.csv`：逐折汇总。
- `../results/cv_record_scores_v2.csv`：逐条留出记录的 log predictive score 和点值预测信息。
- `../results/full_panel_predictions_v2.csv`：365 个物种、5 个模型和 3 条路线的长表预测。
- `../review/final_v2_status.json`：正式运行状态和输出清单。
- `fit_audit_summary.json`、`fit_audit_all_240.csv`：240 个拟合的完整审计。

High/Low 的 `binary` 行中，`Point` 是 High 概率，`CrI_lower/upper` 是其 95% 后验可信区间。`joint_bb` 和 `schemeA_tobit` 行中，`Point` 是 expected exact-report ratio，`CrI` 是期望比率的 95% 后验可信区间，`PI` 是一个未来 exact 报告的 95% 后验预测区间。

## 图件

`figures/` 中同时保存 PDF 和 300 dpi PNG：

- `F01_ROC_AUC_HighLow`：High/Low ROC/AUC；
- `F02_HighLow_calibration`：High 概率校准；
- `F03_ELPD_delta_Null`：相对 Null 的 ELPD 差值；
- `F04_quantitative_predicted_observed`：定量点记录的预测-观测对照；
- `F05A_full_panel_High_heatmap`：365 个物种 High 概率热图；
- `F05B_full_panel_ratio_heatmap`：365 个物种联合路线 expected ratio 热图；
- `F06_prediction_interval_widths`：全物种可信区间/预测区间宽度；
- `F07_training_PPC_checks`：训练资料后验预测检查。
- `F06_species_binary_p01–p09`：High/Low 每个物种/模型的 High 概率和 95% 可信区间；
- `F06_species_joint_bb_p01–p09`：联合定量每个物种/模型的点值、95% 可信区间和 95% 预测区间；
- `F06_species_schemeA_tobit_p01–p09`：Scheme A 每个物种/模型的点值、95% 可信区间和 95% 预测区间；
- `F08_paired_ELPD_comparisons`：按物种聚合后的 paired SE、95% 近似区间和模型对 Null/Site315 的比较。

图注在 `FIGURE_CAPTIONS_zh.md`，结果和中文分析在 `RESULTS_ANALYSIS_SUMMARY_zh.md`。F01 的曲线为留出记录合并可视化，图例中的 AUC 是不加权折均值；F03 没有 paired SE，因此不能从图中宣称统计学显著差异；F07 的橙色检查必须结合原始资料复核。

ELPD 配对比较的具体方法和完整数值在 `ELPD_PAIRED_SE_ANALYSIS_zh.md` 与 `paired_elpd_comparisons.csv`。

## 新物种预测

新增物种输入必须是已经按照冻结参考比对提取的六个位点表：`Species`、`Site3`、`Site20`、`Site117`、`Site151`、`Site196`、`Site315`。运行：

```bash
Rscript scripts/v2_pipeline.R --stage external \
  --root /project/work/ratio_analysis_20260914_v2_site151_excluded \
  --new-data /project/work/new_species_sites.csv \
  --out /project/work/ratio_analysis_20260914_v2_site151_excluded/results/external_predictions_v2.csv
```

程序会同时生成长表和 `_wide.csv` 宽表。宽表每个物种/模型一行，包含 `PrHigh`、联合路线比率及其可信/预测区间、Scheme A 敏感性路线结果和三个状态列。未见类别仍输出数值，并标记 `unseen_category_extrapolation`；缺失位点标记 `missing_input_extrapolation`。

`external_example_complete_predictions_wide.csv` 是两个无缺失测试物种的示例，其中一个包含 M3 未见类别，已通过本地 Docker 预测测试。
