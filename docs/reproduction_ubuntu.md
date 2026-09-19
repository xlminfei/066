# Ubuntu/Docker 复现说明

本项目推荐在 Ubuntu 24.04 与 R 4.6.1 环境运行。正式运行使用 `rocker/r2u:24.04`，并在容器内安装/固定 `brms 2.23.0`、`rstan 2.32.7`、`posterior 1.7.0`、`loo 2.10.1`、`pROC 1.19.1`、`crch 0.6.39` 等包。也可以使用已有等价环境，但应把 `sessionInfo()` 和包版本写入运行记录。

## 目录和容器

```bash
git clone https://github.com/xlminfei/066.git
cd 066
docker run --name ratio-066-v2 --mount type=bind,src="$PWD",dst=/project/work -w /project/work/066/v2 -d rocker/r2u:24.04 sleep infinity
docker exec -it ratio-066-v2 bash
```

容器内检查：

```bash
R --version
Rscript -e 'print(R.version.string); print(packageVersion("brms")); print(packageVersion("rstan")); print(packageVersion("loo")); print(packageVersion("posterior"))'
```

若缺包，使用 R 的正式安装命令；不要改变模型代码中的包调用：

```bash
Rscript -e 'install.packages(c("brms","rstan","StanHeaders","loo","posterior","pROC","crch","jsonlite","digest","ggplot2","dplyr","readr","bayesplot"), repos="https://cloud.r-project.org")'
```

## v2 从输入到结果

以下命令使用仓库内的 `v2` 目录。`preflight` 只检查输入和软件，`smoke` 是小规模接口检查，`all` 才会进行正式 HMC 和 225 个分组留出重拟合。正式拟合完成后再运行审计、后处理和图形脚本。

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

如果只想用已经发布的结果，不需要运行 `all`；结果表、corrected 图和报告已在仓库中。由于 RStan 并行抽样和底层 BLAS 可能不同，重新抽样应比较诊断、区间和汇总表，不能要求每一条后验抽样字节完全相同。

## 新物种预测

新物种 CSV 必须有 `Species,Site3,Site20,Site117,Site151,Site196,Site315` 七列，位点字符来自冻结参考比对。Site151 仍须提供，但只用于输入合同和审计。

```bash
Rscript src/v2_pipeline.R --stage external \
  --root /project/work/066/v2 \
  --new-data /project/work/new_species_sites.csv \
  --out /project/work/066/v2/results/external_predictions_v2.csv
```

同时查看 `external_predictions_v2.csv` 和 `external_predictions_v2_wide.csv`。宽表每个物种/模型一行，包含 High 概率、联合比率、两个区间以及状态列。

## v1 复现

v1 是原始的分段 R 控制台工作流，不是一个单独的命令行脚本。请先阅读 `v1/docs/README_先读这里.md`，随后严格按 `00_开始与使用顺序.md`、`01_输入与编码.md`、`02_独立分类模型.md`、`03_联合比率模型.md`、`05_诊断与模型比较.md`、`04_模型检查与敏感性.md`、`06_留出验证.md`、`06A_HighLow_ROC_AUC.md`、`07_物种预测与区间.md` 的顺序，在 R 控制台逐块执行。v1 需要 `v1/data/tree.nwk`，包含 U/P 两组进化树模型；v2 不需要树。

## 复现后检查点

至少核对以下文件：

```text
v2/review/preflight_v2.json
v2/review/encoding_v2_tests.json
v2/review/tenfold_gate_v2.json
v2/review/final_v2_status.json
v2/results/full_panel_predictions_v2.csv
v2/results/cv_comparisons_v2.csv
v2/figures/F06_full_species_predictions_binary_corrected.pdf
```

`final_v2_status.json` 应为 `COMPLETE_WITH_REVIEW_FLAGS`；这表示抽样诊断完成，但 Scheme A 训练内 PPC 有需要人工复核的旗标。它不应被改写成“所有模型都适合”或“模型显著优于 Null”。

