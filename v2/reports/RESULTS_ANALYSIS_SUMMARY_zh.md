# v2 结果、分析和汇总

分析版本：ratio_analysis_v2_joint_bb_vs_schemeA_site151_excluded_20260918。最终状态：COMPLETE_WITH_REVIEW_FLAGS。正式运行采用无树设计；Site151 保留在输入表中，但从 M1/M2/M3 预测变量中排除。

## 运行与验证状态

- 全数据拟合：15 个（5 个模型 × 3 条路线），全部通过抽样诊断。
- 留出拟合：225 个（5 个模型 × 3 条路线 × 5/10 折结构）。逐文件审计共核对 240 个拟合，失败数为 0。
- 最大 R-hat：1.0043；最小 bulk ESS：1800.5；最小 tail ESS：1456.3；divergence：0；treedepth 命中：0。
- 365 个面板物种共输出 5475 行预测；点值和适用区间端点均为有限数：是。
- 训练内后验预测检查有 20 个 REVIEW_REQUIRED 行，另有 10 个 interval 描述性行。这不是抽样诊断失败，也不是独立外部验证。

## High/Low 路线

AUC 只用于 High/Low 路线。它描述模型把真实 HIGH 排在 LOW 前面的能力；Null 的 AUC 约为 0.5 是随机排序基线。下面的 AUC 是各测试折 AUC 的不加权平均，ROC 曲线本身为留出记录的合并可视化，因此两者不应混称为同一个数。

| 折分 | 模型 | AUC | ELPD | ELPD-Null |
| --- | --- | --- | --- | --- |
| 五折 | M1 | 0.726 | -81.36 | 12.13 |
| 五折 | M2 | 0.694 | -79.37 | 14.12 |
| 五折 | M3 | 0.736 | -78.48 | 15.01 |
| 五折 | Null | 0.500 | -93.49 | 0.00 |
| 五折 | Site315 | 0.719 | -77.18 | 16.31 |
| 十折 | M1 | 0.808 | -68.90 | 16.74 |
| 十折 | M2 | 0.751 | -70.78 | 14.86 |
| 十折 | M3 | 0.738 | -67.70 | 17.94 |
| 十折 | Null | 0.500 | -85.64 | 0.00 |
| 十折 | Site315 | 0.749 | -71.72 | 13.92 |

五折中，M1 的 AUC 为 0.726，Site315 为 0.719，M2 为 0.694，M3 为 0.736。
十折中，M1 的 AUC 为 0.808，Site315 为 0.749，M2 为 0.751，M3 为 0.738。
M1 相对 Site315 的优势在五折和十折中都保持；M2 的 AUC 在五折低于 Site315、十折接近 Site315，不能据此宣称 M2 稳定优于 Site315。M3 在五折略高于 Site315，但十折低于 Site315，应继续作为拓展参考而不是主要结论。

## 定量路线

定量路线不使用 AUC。主要评分是逐条留出记录的 ELPD；MAE 只对 count 和 exact 这类有明确点值的记录作辅助解释，interval 记录仍进入 ELPD，但没有被伪造为一个点。

| 路线 | 折分 | 模型 | ELPD | ELPD-Null | MAE | 点记录数 |
| --- | --- | --- | --- | --- | --- | --- |
| 联合 beta-binomial | 五折 | M1 | -190.07 | 6.39 | 0.292 | 145 |
| 联合 beta-binomial | 五折 | M2 | -187.11 | 9.35 | 0.288 | 145 |
| 联合 beta-binomial | 五折 | M3 | -179.04 | 17.42 | 0.262 | 145 |
| 联合 beta-binomial | 五折 | Null | -196.46 | 0.00 | 0.318 | 145 |
| 联合 beta-binomial | 五折 | Site315 | -190.75 | 5.71 | 0.296 | 145 |
| Scheme A | 五折 | M1 | -151.82 | 10.47 | 0.267 | 145 |
| Scheme A | 五折 | M2 | -147.11 | 15.19 | 0.257 | 145 |
| Scheme A | 五折 | M3 | -139.12 | 23.18 | 0.235 | 145 |
| Scheme A | 五折 | Null | -162.30 | 0.00 | 0.330 | 145 |
| Scheme A | 五折 | Site315 | -150.09 | 12.21 | 0.282 | 145 |
| 联合 beta-binomial | 十折 | M1 | -189.38 | 8.34 | 0.290 | 145 |
| 联合 beta-binomial | 十折 | M2 | -184.67 | 13.05 | 0.283 | 145 |
| 联合 beta-binomial | 十折 | M3 | -180.00 | 17.72 | 0.265 | 145 |
| 联合 beta-binomial | 十折 | Null | -197.71 | 0.00 | 0.320 | 145 |
| 联合 beta-binomial | 十折 | Site315 | -188.54 | 9.18 | 0.293 | 145 |
| Scheme A | 十折 | M1 | -139.34 | 23.41 | 0.241 | 145 |
| Scheme A | 十折 | M2 | -132.69 | 30.07 | 0.234 | 145 |
| Scheme A | 十折 | M3 | -130.86 | 31.89 | 0.222 | 145 |
| Scheme A | 十折 | Null | -162.76 | 0.00 | 0.331 | 145 |
| Scheme A | 十折 | Site315 | -144.43 | 18.32 | 0.273 | 145 |

联合 beta-binomial 路线保留了 count 记录中的真实 Events/Total；Scheme A 将报告比率作为报告级删失正态敏感性路线。两条路线的 ELPD-Null 均为正，说明相对于 Null，位点模型在这些留出记录上的预测密度更高。paired SE 和正态近似检验见后文；它们用于辅助比较，不能直接写成生物学效应的统计学显著性。
联合路线中，M2 的 ELPD-Null 为五折 9.35、十折 13.05; M3 数值更高，但 M3 是拓展模型。M1 五折为 6.39、十折为 8.34。
联合路线中 M2 的五折/十折 MAE 为 0.288 / 0.283；Scheme A 中为 0.257 / 0.234。

## ELPD 的 paired SE 与近似比较

同一折分、同一路线、同一物种内，先把多条留出记录的 log score 求和，再以物种为配对单位比较模型与 Null 或 Site315。paired SE 按物种差值计算，95% 区间和 p 值采用正态近似；这是模型比较的辅助推断，不是生物学效应的显著性检验。完整 42 项比较和 Benjamini-Hochberg 校正结果见 ELPD_PAIRED_SE_ANALYSIS_zh.md。

High/Low 中，M1 相对 Site315 的差值为五折 -4.18（SE 4.69，p=0.373），十折 2.82（SE 3.09，p=0.362）；AUC 和 ELPD 都不支持 M1 稳定地显著优于 Site315。联合 beta-binomial 中，M2 相对 Site315 的差值为五折 3.65（SE 3.22，p=0.258），十折 3.87（SE 3.16，p=0.221）；方向一致，但近似区间仍跨过 0。整张比较表的 BH 校正 p 值没有低于 0.05。

## 全面板预测与新物种复用

全物种预测表保留三条路线。High/Low 行的 Point 是 High 概率，CrI_lower/upper 是 High 概率的 95% 后验可信区间；联合和 Scheme A 行的 Point 是 expected exact-report ratio，CrI 是期望比率的 95% 后验可信区间，PI 是一个未来 exact 类型报告的 95% 后验预测区间。调用者不需要提供未来分母。

外部预测入口已经用无缺失示例测试：一个普通固定类别输入和一个 M3 未见类别输入。宽表把 High 概率、联合路线比率和两个区间、Scheme A 敏感性路线结果放到同一行；未见类别会输出数值并在状态列标为 unseen_category_extrapolation。

## 资料拟合检查的限制

| 路线 | 模型 | 资料子集 | 检查统计量 |
| --- | --- | --- | --- |
| Scheme A | Null | count | OneFraction |
| Scheme A | Null | count | SD |
| Scheme A | Null | exact | SD |
| Scheme A | Null | exact | OneFraction |
| Scheme A | Site315 | count | OneFraction |
| Scheme A | Site315 | count | SD |
| Scheme A | Site315 | exact | SD |
| Scheme A | Site315 | exact | OneFraction |
| Scheme A | M1 | count | OneFraction |
| Scheme A | M1 | count | SD |
| Scheme A | M1 | exact | SD |
| Scheme A | M1 | exact | OneFraction |
| Scheme A | M2 | count | OneFraction |
| Scheme A | M2 | count | SD |
| Scheme A | M2 | exact | SD |
| Scheme A | M2 | exact | OneFraction |
| Scheme A | M3 | count | OneFraction |
| Scheme A | M3 | count | SD |
| Scheme A | M3 | exact | SD |
| Scheme A | M3 | exact | OneFraction |

PPC 标记主要反映 Scheme A 对端点频率/波动的描述不足，以及部分联合模型统计量落在训练内后验预测范围外。它们需要结合原始实验记录、报告方式和区间定义复核。PPC 是训练资料上的模型检查，不是独立验证；最终预测结论仍应以物种分组留出 ELPD/AUC 和计划中的新物种实验验证为主。

## 输出文件

- 拟合审计摘要：fit_audit_summary.json
- 模型比较表：../results/cv_comparisons_v2.csv
- 逐折评分：../results/cv_fold_scores_v2.csv
- 逐条留出记录评分：../results/cv_record_scores_v2.csv
- 全物种预测：../results/full_panel_predictions_v2.csv
- 新物种宽表示例：external_example_complete_predictions_wide.csv
- ELPD 配对比较：ELPD_PAIRED_SE_ANALYSIS_zh.md 和 paired_elpd_comparisons.csv
- 图注：FIGURE_CAPTIONS_zh.md
