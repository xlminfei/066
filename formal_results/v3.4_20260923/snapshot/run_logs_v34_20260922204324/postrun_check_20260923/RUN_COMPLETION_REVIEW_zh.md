# v3.4 本次正式运行完成情况复核

复核日期：2026-09-23；审查提交：c9ec1c58e173dd5209bbbe5e89b2213553fc0630。

**本次正式流程已正常完成，256项拟合的既定采样诊断及最终审计均通过。当前主流程要求的结果、报告和全部8份PDF（76页）已输出且完整。最终状态为 COMPLETE_WITH_REVIEW_FLAGS，应保留18项训练内PPC提示，并结合校准与外推适用性标志解释模型结果。**

## 运行退出

- 容器：ratio-v34-formal-20260922204324。
- Docker状态 exited、ExitCode=0、OOMKilled=false、Error为空；宿主正式进程退出记录也为0。
- 北京时间：2026-09-22 20:48:17启动，2026-09-23 12:42:16结束，约15小时53分59秒。
- last_stage_status：STAGE_COMPLETE；stage=all。
- final_v3_status：COMPLETE_WITH_REVIEW_FLAGS。
- 运行命令：Rscript /project/v34/src/v3_pipeline.R --stage all。

## 拟合与诊断

本次重新以只读方式打开全部256个正式拟合对象，核对保存的诊断、拟合身份及4链/4000迭代/2000预热设置。最终主程序审计在退出前已逐项重算诊断并检查真实后验。本次补充检查没有重新拟合或重新运行MCMC。

| 指标 | 全256项的最不利值/总数 | 原门槛 | 结论 |
|---|---:|---:|---|
| Max Rhat | 1.0041 | <1.01 | PASS |
| 最小Bulk ESS | 1567.1251 | >=400 | PASS |
| 最小Tail ESS+ | 1349.4951 | >=400 | PASS |
| 发散总数 | 0 | 0 | PASS |
| 最大树深度命中总数 | 0 | 0 | PASS |
| 最小E-BFMI | 0.7842 | >0.3 | PASS |

正式对象共256个、均非空，总字节11350681431；16个全数据拟合和240个CV拟合身份集合与任务计划完全一致。详见 [全部256项保存诊断汇总](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/run_logs_v34_20260922204324/postrun_check_20260923/all_256_saved_diagnostics.csv)。

## 最终审计及当前文件完整性

- audit_v3.json：PASS，expected_tasks=fits_checked=fits_passed=256，issues为空。
- 后验复算600个记录类型/拟合分组，共10720行：4880条OOF记录和5840行全物种预测；全部PASS，最大绝对差1.24344978758018e-14。
- 模型比较48组、训练方法比较32组、定量Bias32组、定量图源4640行的正式复算记录均PASS。
- 本次再次验证32个冻结代码/配置/输入文件的SHA-256，均与启动快照相同。
- 正式输出清单中31个文件的SHA-256全部匹配，且results/figures/reports实际文件集合与清单完全相同，无缺失、无未登记文件。
- 独立结构检查35项全部通过，并额外核对7份模型图PDF的模型标签和4份物种图中的365个物种标签，均通过。
- 主正式日志记录256次FIT_START、256次FIT_END PASS、256次AUDIT_FIT PASS；检查的Warning/Exception/Error/FAILED等日志模式没有命中。

## 结果表

results目录共21份CSV。下列行数之外，主要输出还核对了模型、训练、评价、CV设计、折号/记录/物种组合的完整性，避免仅凭总行数作结论。

| 文件 | 数据行数 |
|---|---:|
| [calibration_bins.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/calibration_bins.csv) | 110 |
| [cv_fold_metrics.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/cv_fold_metrics.csv) | 480 |
| [cv_metrics_summary.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/cv_metrics_summary.csv) | 64 |
| [cv_record_predictions.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/cv_record_predictions.csv) | 4880 |
| [folds_binary_species_10.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/folds_binary_species_10.csv) | 50 |
| [folds_binary_species_5.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/folds_binary_species_5.csv) | 50 |
| [folds_joint_bb_species_10.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/folds_joint_bb_species_10.csv) | 51 |
| [folds_joint_bb_species_5.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/folds_joint_bb_species_5.csv) | 51 |
| [full_diagnostics.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/full_diagnostics.csv) | 16 |
| [full_panel_predictions.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/full_panel_predictions.csv) | 5840 |
| [model_vs_null.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/model_vs_null.csv) | 48 |
| [model_vs_null_by_fold.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/model_vs_null_by_fold.csv) | 360 |
| [quantitative_bias_summary.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/quantitative_bias_summary.csv) | 32 |
| [quantitative_plot_source.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/quantitative_plot_source.csv) | 4640 |
| [roc_coordinates.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/roc_coordinates.csv) | 1144 |
| [training_method_comparisons.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/training_method_comparisons.csv) | 32 |
| [training_method_comparisons_by_fold.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/training_method_comparisons_by_fold.csv) | 240 |
| [training_ppc_summary.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/training_ppc_summary.csv) | 256 |
| [training_weights.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/training_weights.csv) | 34160 |
| [training_weights_cv.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/training_weights_cv.csv) | 31720 |
| [training_weights_full.csv](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/training_weights_full.csv) | 2440 |

总体48+32组比较的P_approx及P_BH均已生成且在[0,1]范围内。这些值保留原有“固定OOF预测下物种bootstrap近似”的解释。逐折比较中少于10物种或退化时可有预先约定的不适用P值，不将其当作漏算。binary表中的定量专属指标NA、joint_bb表中的AUC/Brier等不适用项也不属于漏输出。

## 图片与报告

每份PDF已完整解析，76页全部用Poppler渲染为PNG，无渲染报错且无空白页。查看全部13张逐页联系表，并放大检查物种标签、定量图轴/图例与PPC纵向标签。未发现明显绘制中断、缺页或缺失模型。

| PDF文件 | 页数 | 检查结果 |
|---|---:|---|
| [ROC_curves.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/ROC_curves.pdf) | 8 | 完整解析、全部渲染、目视检查通过 |
| [calibration_bins.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/calibration_bins.pdf) | 8 | 完整解析、全部渲染、目视检查通过 |
| [quantitative_predicted_observed.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/quantitative_predicted_observed.pdf) | 8 | 完整解析、全部渲染、目视检查通过 |
| [training_ppc_summary.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/training_ppc_summary.pdf) | 16 | 完整解析、全部渲染、目视检查通过 |
| [species_predictions_binary_record_equal.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/species_predictions_binary_record_equal.pdf) | 9 | 完整解析、全部渲染、目视检查通过 |
| [species_predictions_binary_species_equal.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/species_predictions_binary_species_equal.pdf) | 9 | 完整解析、全部渲染、目视检查通过 |
| [species_predictions_joint_bb_record_equal.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/species_predictions_joint_bb_record_equal.pdf) | 9 | 完整解析、全部渲染、目视检查通过 |
| [species_predictions_joint_bb_species_equal.pdf](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/figures/species_predictions_joint_bb_species_equal.pdf) | 9 | 完整解析、全部渲染、目视检查通过 |

4份物种预测PDF分别覆盖完整365个物种，每页均包含Null/M1/M2/M3。绘图源表5840行的点值/区间/状态与全预测表逐字段一致。M1/M2/M3分别具有27/37/157种点预测取值，随编码组合变化；Null每套拟合产生一个共同点预测值，符合无位点模型定义。

正式报告已生成：[REPORT_v3_4.md](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/reports/REPORT_v3_4.md)。这次检查的范围是既定all流程输出完整性和图件可用性，不等于对模型科学效能作最终判断。

## 必须保留的结果提示

训练内PPC总计256项统计量检查，238项OK、18项REVIEW_REQUIRED。这18项均为joint_bb、EvalWeighting=species_equal。它们表示真实观测的某个统计量落在模型重复生成数据的95%范围之外，是原流程设计的模型检查提示。

| Model | TrainWeighting | 数据子集 | 统计量 | 观测值 | PPC 2.5% | PPC 97.5% |
|---|---|---|---|---:|---:|---:|
| Null | record_equal | count | Mean | 0.542232 | 0.614066 | 0.835358 |
| Null | record_equal | count | SD | 0.448806 | 0.319290 | 0.448649 |
| Null | record_equal | count | ZeroFraction | 0.284483 | 0.056336 | 0.260293 |
| Null | record_equal | count | OneFraction | 0.400657 | 0.443111 | 0.725886 |
| Null | record_equal | all_point | Mean | 0.614479 | 0.646498 | 0.808567 |
| Null | record_equal | all_point | SD | 0.389160 | 0.274252 | 0.369849 |
| Null | record_equal | all_point | ZeroFraction | 0.166667 | 0.032350 | 0.147403 |
| Null | species_equal | count | Mean | 0.542232 | 0.552492 | 0.789378 |
| Null | species_equal | all_point | SD | 0.389160 | 0.302899 | 0.383658 |
| M1 | record_equal | count | Mean | 0.542232 | 0.551009 | 0.785142 |
| M1 | record_equal | all_point | SD | 0.389160 | 0.299193 | 0.386872 |
| M1 | species_equal | all_point | SD | 0.389160 | 0.308114 | 0.386605 |
| M2 | record_equal | count | Mean | 0.542232 | 0.550267 | 0.777387 |
| M2 | record_equal | all_point | SD | 0.389160 | 0.300717 | 0.386035 |
| M2 | species_equal | all_point | SD | 0.389160 | 0.314043 | 0.386406 |
| M3 | record_equal | count | Mean | 0.542232 | 0.544786 | 0.757568 |
| M3 | record_equal | all_point | SD | 0.389160 | 0.307771 | 0.384554 |
| M3 | species_equal | all_point | SD | 0.389160 | 0.318560 | 0.385581 |

例如，count子集在物种等权下的观测均值为0.542232，而Null记录等权训练对应PPC范围为[0.614066,0.835358]；另外所有8套定量拟合在all_point子集的物种等权SD均有提示，观测SD为0.389160，PPC上界约0.369849至0.386872。部分差距较小，不能仅凭越界便推断程序错误或所有模型失效，后续应结合CV误差、Bias与预测区间评价。

校准表110箱中，56箱OK、40箱LIMITED_SPECIES、10箱DEGENERATE_INTERVAL、4箱INSUFFICIENT_SUPPORT。4个支持不足箱均只有1个物种，区间端点为0不应解读成高度确定；对应状态已经明确保存在表中。物种预测表还保留适用性/外推警告，应随结果一并解读。

## 本次核查的操作边界与证据

只读挂载正式v3.4目录；没有更改代码、输入、模型参数或正式结果，也没有重新训练。仅在本次postrun_check_20260923目录新增诊断汇总、结构检查、PDF渲染、目视记录与这份说明。没有在本次检查中执行远端上传。

关键证据：formal_container_exit_state.json、fresh_receipt_and_diagnostic_check.json、all_256_saved_diagnostics.csv、structural_output_check.json、pdf_check.json、pdf_page_label_check.json、visual_review.json、PPC_review_flags.csv，以及各核验脚本和日志。历史发布包里的NOT_RUN或启动时RUNNING快照不代表当前状态；应以本次正式review/final_v3_status.json和audit_v3.json为准。
