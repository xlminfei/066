# STING 跨物种响应比率模型：v1 与 v2 可复现项目

这是一个把同一蛋白的六个位点序列特征与实验响应资料联系起来的研究计算项目。项目同时保留原始的 **v1** 工作流和当前采用的 **v2** 工作流。v2 是正式推荐版本；v1 作为历史版本、结果对照和方法演变记录保留。

## 研究问题

对 365 个物种的蛋白序列，在固定多重比对中提取 Site3、Site20、Site117、Site151、Site196、Site315 六个位点。实验资料包含三种形式：有真实分母的 count、报告精确比例但未知分母的 exact，以及只给上下界的 interval。目标有两条：

1. 预测一个物种属于 High/Low 的概率，并用分组留出 ROC/AUC 与逐条留出 ELPD 评价分类路线。
2. 预测一个物种的 expected exact-report ratio，同时给出 95% 后验可信区间（CrI）和一个未来 exact 报告的 95% 后验预测区间（PI），并用逐条留出 ELPD、MAE 作为定量路线的主要与辅助评价。

预测新物种时，输入必须已经按照冻结参考比对提取好六个位点。程序不会把新物种加入多重比对，也不会重新统计 M3 的类别频数，因此后来增加物种不会改变已经发布的编码字典和模型参数。

## 从哪里开始

- [v2/README.md](v2/README.md)：当前正式版本的完整方法、参数、公式、输出列和复现步骤。
- [v1/README.md](v1/README.md)：历史版本的模型网格、进化树路线、手册执行顺序和已知限制。
- [docs/v1_vs_v2_改进说明_zh.md](docs/v1_vs_v2_改进说明_zh.md)：逐项解释 v2 改了什么以及为什么改。
- [docs/algorithm_details_zh.md](docs/algorithm_details_zh.md)：用不依赖编程背景的语言说明模型、区间和评价指标。
- [docs/reproduction_ubuntu.md](docs/reproduction_ubuntu.md)：Ubuntu/Docker 的可复制命令和检查点。
- [docs/limitations_zh.md](docs/limitations_zh.md)：结果可以支持什么、不能支持什么。
- [v3/README.md](v3/README.md)：独立的 v3 重构代码包，包含两种训练权重 × 两种评价权重、binary/joint_bb 两条路线和完整测试入口。
- [v3/docs/reproduction_ubuntu.md](v3/docs/reproduction_ubuntu.md)：v3 的 Docker 构建、预检、测试和正式运行命令。

## 目录结构

```text
v2/
  data/          输入 CSV 与输入合同
  src/           v2 R 源码，包括拟合、留出、审计、后处理和绘图
  results/       全面板预测、留出分数、折表和编码结果
  results/derived/  AUC、ELPD、MAE、校准、状态和配对比较表
  figures/       PDF/PNG 结果图；F06 使用 corrected 版本
  reports/       中文结果、图注、ELPD 配对 SE 和修正说明
  review/        preflight、smoke、十折门控和最终状态 JSON
  examples/      新物种外部预测输入与宽表输出示例
  provenance/    正式运行日志和输入追踪
v1/
  data/          v1 的 observations.csv、sites.csv、tree.nwk
  src/           原始 v1 分段脚本（含状态辅助脚本）
  docs/          原始 v1 操作手册、验证证据、demo/blank/validation 输入
  results/       v1 全面板/预处理结果
  archive/       v1 图件、全部非 RDS 衍生结果和运行产物压缩包
  provenance/    v1 图注、清单、完整日志和省略大文件说明
docs/            版本差异、算法解释、复现和限制
v3/
  config/        v3 固定分析网格与输入合同配置
  input/         v3 冻结输入 CSV 与合同
  R/             输入、权重、拟合、评分、CV、预测和绘图模块
  stan/          joint beta-binomial/endpoint-mixture Stan 模型
  src/           v3 阶段调度、审计、后处理和报告入口
  tests/         解析、契约、预备数据、外部投影和 smoke 评分检查
  provenance/    v3 文件清单和运行环境说明
```

## v2 已完成的正式运行

正式版本标识为 `ratio_analysis_v2_joint_bb_vs_schemeA_site151_excluded_20260918`，随机种子为 `20260918`。共完成 15 个全资料模型（5 个模型 × 3 条输出路线）和 225 个分组留出重拟合（5 个模型 × 3 条路线 × 5/10 折设置）。每个拟合使用 4 链、每链 4000 次迭代、2000 次预热、`adapt_delta=0.99`、`max_treedepth=12`。所有全模型和留出模型的 HMC 诊断通过：无发散、无树深度上限命中，R-hat、bulk/tail ESS 均达到门槛。

最终状态是 `COMPLETE_WITH_REVIEW_FLAGS`。这表示计算完成且抽样诊断通过；训练资料的 Scheme A 后验预测检查有 20 项需要结合原始资料人工复核，另有 10 项只作描述性记录。这些标志不是程序崩溃，也不是独立测试集失败。

## 版本和公开内容

用户明确要求把项目推送到公开 GitHub 仓库。仓库中包括本项目提供的输入表、代码、结果表、图件和方法说明；发布前没有把原始输入悄悄替换为模拟数据。后验 RDS 和编译缓存总量很大，不适合放入普通 Git 历史，已在两个版本的 `provenance/omitted_large_artifacts.md` 中列明省略原则；它们可以由相同代码、输入、随机种子和参数重新生成。

本仓库没有替代用户或期刊指定的数据/代码许可。若要把代码用于商业用途、重新分发原始实验表或把预测作为新的生物学结论，需先按项目作者和数据来源的许可要求处理。

根目录的 `MANIFEST.csv` 给出每个交付文件的相对路径、字节数和 SHA256；`MANIFEST.sha256` 校验清单本身。它们不包含省略的后验 RDS，不能替代方法和诊断报告。

v2 postprocess 中唯一未直接放入 `figures/`、`reports/` 或 `results/derived/` 的文件，是没有 `corrected` 后缀的旧 F06 图件；它们与分页标签错配的旧版本对应，已经被 corrected F06 替代，完整清单在 `v2/provenance/postprocess_omissions.csv`。

## v3 重构代码包

v3 是在保留 v1/v2 的独立目录中新增的代码版本。它固定比较 `Null`、`M1`、`M2`、`M3` 四个模型，使用 `binary` 和 `joint_bb` 两条路线，并分别拟合 `record_equal` 与 `species_equal` 两种训练权重。每套拟合从同一张折外记录证据表接受 `record_equal` 与 `species_equal` 两种评价，因此计划包含 16 个全数据拟合和 240 个五折/十折交叉验证拟合。

v3 保留 Site151 输入但不把它放入预测矩阵，保留 Site315 作为 M1/M2/M3 的预测位点，删除 Site315 单位点模型、Scheme A 和系统发育路线。40–50% 区间按约定归 LOW，M3 频数小于 4 的类别归入 `OTHER`。v3 的输入合同、运行环境、测试和 Docker 命令都在 `v3/` 内。

本次发布时 v3 已完成 Docker 预检、静态解析、契约测试、smoke 拟合、smoke 评分和外部投影检查。正式 16 个全数据 MCMC 拟合及 240 个 CV 拟合尚未启动，因此 v3 目录中的正式结果表和正式图件仍需执行 `v3/src/v3_pipeline.R --stage all` 后生成。smoke 的低迭代诊断记录明确标为 `PASS_WITH_DIAGNOSTIC_WARNINGS`，不能当作正式研究结果。


## v3.1 修订与发布验证

v3.1 位于 [v3.1/](v3.1/README.md)，保留原 v1/v2/v3 历史文件。旧 v3 自检覆盖不足，其 PASS 不能作为完整流程正确性的证明；本版修复原审查问题及复核中新发现的接口、观测机制、缓存和状态问题。

- [当前流程与模块说明](v3.1/docs/V3_1_WORKFLOW_zh.md)
- [逐项修复理由与审查矩阵](v3.1/docs/REVIEW_MATRIX_zh.md)
- [测试结果、范围和限制](v3.1/review/RELEASE_VALIDATION_zh.md)
- [Ubuntu/Docker运行](v3.1/docs/reproduction_ubuntu.md)

18个实际拟合都是合成测试（16个短链接口拟合+2个加权后验数值对照），正式研究数据的16+240项拟合未执行。测试指标、日志、图源和数值抽样快照随包保存；平台相关编译缓存保留本地，其大小与SHA-256列于逐项清单。

[下载 v3.1 源码与测试包](releases/ratio-analysis-v3.1.zip) · [ZIP SHA-256](releases/ratio-analysis-v3.1.zip.sha256)
