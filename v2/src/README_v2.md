# v2：无树、Site151排除、联合计数比率与方案A比较

本目录是独立的新版本运行目录，保留六个位点的原始输入，但主模型只使用五个位点：

```text
建模位点：Site3、Site20、Site117、Site196、Site315
保留但不进模型：Site151
```

Site151 在当前 51 个有响应物种中全部为 C，因此没有可估计的响应效应。它仍保留在输入、编码表、缺失检查和审计记录中；新物种输入也仍要求提供六个位点，但 Site151 不改变预测值。

模型路线如下：

- `binary`：High/Low 的标准 brms 二项模型，包含 Null、Site315、M1、M2、M3。
- `joint_bb`：保留 count 的真实 `Events/Total`，用 beta-binomial 计数分布，并与 exact、interval 共用期望比率 `m`。
- `schemeA_tobit`：把每条报告转换为报告比率，使用标准 brms 删失正态报告级模型；分子、分母仍保存在输入和追溯文件中，但这条路线不把分母当作似然精度。

M1 将各建模位点按预先规定的参考氨基酸、`other`、`MISSING` 编码；Site315 使用 `K_or_T`、`other`、`MISSING`。M2 使用 `CKST`、`other`、`MISSING`。M3 使用冻结的 365 物种字典：某个位点出现至少 4 次的氨基酸保留，出现 1–3 次的合并为 `OTHER`，`MISSING` 单独保留。新增物种不会重新统计频数。

训练、评分和预测都保留完整设计列。若新物种出现有响应训练物种中没有见过的编码类别，模型仍计算数值；结果的 `Status` 会标为 `unseen_category_extrapolation`。缺失位点标为 `missing_input_extrapolation`。这些数值可能主要由先验外推，不能解释为该类别已经被实验学习。

运行主流程：

```bash
Rscript scripts/v2_pipeline.R --stage preflight --root /project/work/ratio_analysis_20260914_v2_site151_excluded
Rscript scripts/v2_pipeline.R --stage smoke --root /project/work/ratio_analysis_20260914_v2_site151_excluded
Rscript scripts/v2_pipeline.R --stage all --root /project/work/ratio_analysis_20260914_v2_site151_excluded
```

五折物种分组验证是主结果。分类路线只使用有至少一条可分类记录的 50 个物种；联合比率和 Scheme A 路线使用有定量资料的 51 个物种。两套折表独立生成，不能混用。十折先检查每个分类测试折同时含 HIGH 和 LOW；若任一折缺少一类，整套十折不运行。Null 只作为 ELPD 差值的零点，Null 的实际预测概率不会被改成 0；不输出 ΔAUC。MAE 只作为定量路线的辅助解释。`cv_fold_scores_v2.csv` 保存逐折汇总，`cv_record_scores_v2.csv` 保存每条留出记录的 log predictive score。

新增物种预测要求一个 CSV，列为 `Species` 和六个位点列。六个位点必须已经按冻结参考比对提取，程序不会把新序列加入多重比对，也不会重新统计 M3 频数。示例命令：

```bash
Rscript scripts/v2_pipeline.R --stage external \
  --root /project/work/ratio_analysis_20260914_v2_site151_excluded \
  --new-data /project/work/new_species_sites.csv \
  --out /project/work/ratio_analysis_20260914_v2_site151_excluded/results/external_predictions_v2.csv
```

定量路线输出整体 expected exact-report ratio、95% 后验可信区间和一个未来 exact-type 报告的 95% 后验预测区间；调用者不需要提供未来实验的分母。区间和点值均应落在 `[0,1]`。

`--stage external` 默认写出长表 `external_predictions_v2.csv` 和同一批结果的宽表 `external_predictions_v2_wide.csv`。宽表把同一个物种/模型的 High 概率、联合比率及其两个区间、Scheme A 敏感性结果放在同一行。
