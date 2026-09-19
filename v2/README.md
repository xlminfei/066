# v2 正式分析包

## 研究对象和最终目标

本版本把蛋白序列的五个可变预测位点与跨物种实验响应联系起来。输入仍保存六个位点（3、20、117、151、196、315），但 51 个有响应物种在 Site151 都是 C，Site151 因此只用于输入完整性检查，不进入 M1/M2/M3 的设计矩阵。模型没有进化树随机效应。

最终给每个物种输出两类结果：

- High/Low 路线：`PrHigh` 及 95% 后验可信区间；
- 定量路线：expected exact-report ratio、95% 后验可信区间和一个未来 exact 报告的 95% 后验预测区间。定量路线不要求预先知道未来实验分母。

M1 和 M2 是主要模型，M3 是更细类别的拓展参考。Null 和 Site315 是基线。Null 在 ELPD 差值中固定为 0；它的实际后验 High 概率不会被强行设成 0，也不计算 ΔAUC。

## 输入文件

`data/observations.csv` 是实验记录，`data/sites.csv` 是固定 365 物种面板的六个位点字符，`data/contract.json` 记录输入合同和哈希。记录至少需要 `RecordID`、`ExperimentID`、`Species`、`Type`；count 还需要 `Events`、`Total`，exact 需要 `Exact`，interval 需要 `Lower`、`Upper`。

High/Low 的操作性规则是：点值或 count 比例 `<0.5` 为 LOW、`>=0.5` 为 HIGH；区间 `Upper<=0.5` 为 LOW，`Lower>=0.5` 为 HIGH；严格跨越 0.5 的区间不分类。因而 40–50% 是 LOW，精确 50% 是 HIGH，40–100% 不进入 High/Low。

## 固定编码

- M1：五个位点各保留预设参考类别、`other`、`MISSING`；Site315 使用 `K_or_T`、`other`、`MISSING`。
- M2：五个位点使用 `CKST`、`other`、`MISSING`。
- M3：从 365 物种面板逐位点统计类别；出现至少 4 次的氨基酸保留，出现 1–3 次的类别合并为 `OTHER`，`MISSING` 单独保留。频数字典冻结在 `data/sites.csv`，加入新的物种不会改变它。

所有 dummy 列在训练和预测时都保留。新物种类别在有响应训练物种中从未出现时仍给出数值，`Status` 标记为 `unseen_category_extrapolation`；输入缺失标记为 `missing_input_extrapolation`。这些状态是预测可信度信息，不是错误码。

## 三条输出路线

### binary

使用现成 `brms`/Stan 二项 logit 模型：

`HighCount ~ Binomial(Trials, PrHigh)`。

训练使用 50 个有至少一条可分类记录的物种；同一物种的所有记录永远在同一折。`Point` 是后验均值，`CrI_lower/upper` 是 95% 后验可信区间。

### joint_bb

以同一个物种期望比率 `m` 联系 count、exact、interval：

```text
q ~ Beta(phi*m, phi*(1-m))
Events ~ Binomial(Total, q)
```

exact 记录使用连续 beta 部分和 1 端点质量，interval 记录使用相同报告分布的区间概率。计数的 beta-binomial 参数是 `alpha=phi*m`、`beta=phi*(1-m)`。训练使用 51 个有定量资料的物种。

### schemeA_tobit

使用 `brms::cens` 的删失正态报告级模型。它把比例报告当作删失/点观测，作为定量敏感性路线；分子分母保留在输入和审计中，但不把未来未知分母当作似然输入。其输出与 joint_bb 分开解释。

## 参数和运行设置

```text
R                 4.6.1
brms              2.23.0
rstan             2.32.7
loo               2.10.1
posterior         1.7.0
pROC              1.19.1
crch              0.6.39
seed              20260918
chains            4
cores             4
iter              4000
warmup            2000
adapt_delta       0.99
max_treedepth     12
Intercept prior   Normal(0, 1.5)
coefficient prior Normal(0, 0.5)
rho prior         Beta(1, 1)
log(phi) prior    Normal(log(10), 1)
```

这套先验是预先固定的工作假设；它们不是为追求某个结果而根据结果反复调整的参数。

## 五折、十折和评价

五折是主评价，十折在每一折都同时含 HIGH 和 LOW 时才运行；本数据满足十折门控，所以两者都保留。分类折表有 50 个物种，定量折表有 51 个物种。每个模型/路线/折分重新拟合，不把同一物种拆到训练与测试两边。

- High/Low：折内 ROC/AUC；主表报告折 AUC 的平均；Null 的每折 AUC 为 0.5。
- 两条定量路线和 High/Low：逐条留出记录的 ELPD；`cv_record_scores_v2.csv` 是最细粒度证据，`cv_fold_scores_v2.csv` 是折汇总。
- 定量路线：MAE 只作辅助，并对 count/exact 等可定义点值的记录单独统计；interval 不被伪造为中点。
- 配对 ELPD：按物种把记录分数求和，给出 paired SE、正态近似 95% 区间和未校正/BH 辅助 p 值。它们不能单独支持“统计学显著优于”的确认性结论。

## 正式结果和图

- `results/full_panel_predictions_v2.csv`：365 物种 × 5 模型 × 3 路线的长表；所有 Point/CrI/PI 应为有限数。
- `results/cv_comparisons_v2.csv`、`results/cv_fold_scores_v2.csv`、`results/cv_record_scores_v2.csv`：留出评价。
- `results/derived/roc_auc_summary.csv`、`quantitative_elpd_mae_summary.csv`、`paired_elpd_comparisons.csv`：分析表。
- `figures/F01`–`F08`：ROC、校准、ELPD、预测/观测、全物种热图、区间宽度、PPC、配对 ELPD。
- `figures/F06_*_corrected`：每页 42 个物种、5 个模型的最终物种图；High/Low 显示点和 CrI，joint_bb/Scheme A 显示点、CrI 和 PI。没有 `corrected` 后缀的 F06 图不属于最终交付。
- `reports/FIGURE_CAPTIONS_zh.md`、`reports/RESULTS_ANALYSIS_SUMMARY_zh.md`：图注和结果解读。
- `provenance/v2_run_logs.tar.gz`：正式 preflight、smoke 和 full-run 日志；`provenance/postprocess_omissions.csv`：被 corrected F06 替代的旧图件清单。

最终状态见 `review/final_v2_status.json`。当前状态 `COMPLETE_WITH_REVIEW_FLAGS` 的含义是 HMC 和留出计算完成，但 Scheme A 训练内 PPC 有 20 项需人工结合原始资料查看；不能把它简化成所有路线都已被数据充分证明。

## 运行命令

在容器中从本目录运行：

```bash
Rscript src/v2_pipeline.R --stage preflight --root /project/work/066/v2
Rscript src/encoding_v2_tests.R
Rscript src/v2_pipeline.R --stage smoke --root /project/work/066/v2
Rscript src/v2_pipeline.R --stage all --root /project/work/066/v2
Rscript src/audit_completed_run_20260919.R
Rscript src/postprocess_v2_results.R
Rscript src/paired_elpd_analysis.R
Rscript src/plot_species_F06_v2.R
Rscript src/write_v2_reports.R
```

完整 Docker、包安装和外部预测命令见仓库根目录 [docs/reproduction_ubuntu.md](../docs/reproduction_ubuntu.md)。
