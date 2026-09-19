# v1 历史分析包

v1 是本研究最初的完整工作流。它保留六个位点、365 物种面板、进化树以及 U/P 两种结构，用于说明早期模型如何建立、检查和产生物种预测。v1 的结果不能直接替代当前 v2；发表和新物种预测请优先引用 v2。

## v1 的研究对象

v1 使用 `data/observations.csv`、`data/sites.csv` 和 `data/tree.nwk`。输入记录同样分为 count、exact 和 interval，High/Low 边界为点值/计数比率 `<0.5` LOW、`>=0.5` HIGH；区间 `Upper<=0.5` LOW、`Lower>=0.5` HIGH；跨越 0.5 的区间不分类。M3 按 365 物种参考频数把出现 1–3 次的类别并入 OTHER，至少 4 次保留。

## v1 的模型网格

v1 有两条路线：独立 High/Low 分类和联合比率路线。每条路线包括：

1. Null；
2. Site315；
3. M1、M2、M3 编码；
4. 每个结构的 U（不加树）和 P（加入 `tree.nwk` 的物种相关矩阵）版本。

因此是十个候选结构/路线，主拟合总计二十个。P 结构将同一物种的预测通过树的相关矩阵联系起来；U 结构不使用这一物种随机效应。Site151 在响应物种中是常数 C，所以旧版实际没有可估计的 Site151 变化效应，但 v1 没有像 v2 一样把“保留输入、排除预测矩阵”写成明确合同。

## 主要算法

v1 的分类模型使用 `brms` 的二项/ beta-binomial 接口，以 `HighCount/Trials` 估计 High 倾向；联合路线使用 Stan 代码把 count、exact、interval 联系到物种期望比率，并可增加进化树随机结构。具体的模型字符串、先验、数据检查、抽样诊断、敏感性拟合和留出验证都保存在 `docs/` 的逐段手册中；不要跳过手册中关于对象读取、输入哈希和抽样诊断的顺序。

## v1 手册执行顺序

从 `docs/README_先读这里.md` 开始，再按以下顺序在 Ubuntu 的 R 控制台逐块执行：

```text
00_开始与使用顺序.md
01_输入与编码.md
02_独立分类模型.md
03_联合比率模型.md
05_诊断与模型比较.md       # 先读取并诊断拟合
04_模型检查与敏感性.md
06_留出验证.md
06A_HighLow_ROC_AUC.md
07_物种预测与区间.md
08_可选矩阵核查.md
```

`src/` 中保留了 v1 的原始 R 代码和检查脚本；手册是理解每个代码块的主入口，而不是把所有代码拼成一个未经审查的一键脚本。重新运行时应使用一个新的 `RUN_TAG`，不要把 v2 的结果目录混入 v1 的缓存。

## v1 结果包

`results/` 保存预处理和物种预测表。`docs/` 现在包含原始手册下的验证证据、`blank_input`、`demo_input` 和 `validation_input`，因此 v1 的小规模接口验证材料也能随仓库复现。图件和衍生结果分别压缩到 `archive/v1_figures_model_descriptive.tar.gz`、`archive/v1_derived_key.tar.gz`、`archive/v1_derived_all_nonrds.tar.gz` 和 `archive/v1_runs_nonrds.tar.gz`，解压后包含 PDF/SVG/PNG、图注、来源 CSV、非 RDS 结果和运行产物。v1 的全部运行日志在 `provenance/v1_run_logs.tar.gz`。图件清单与 SHA256 在 `provenance/` 中。后验 RDS、编译对象、运行时缓存和重复的视觉审查文件没有进入压缩包，省略原因见 `provenance/omitted_large_artifacts.md`。

## 与 v2 的关系

v1 的 U/P 树模型是历史参考。v2 去掉进化树，固定完整类别列，明确排除 Site151，修复 beta-binomial 计数精度公式和 F06 分页标签问题，并让未见类别仍有数值输出。逐项差异和修改原因见仓库根目录 [docs/v1_vs_v2_改进说明_zh.md](../docs/v1_vs_v2_改进说明_zh.md)。
