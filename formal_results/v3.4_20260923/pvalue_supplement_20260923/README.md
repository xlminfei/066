# v3.4：ELPD P 值解释与 AUC / MAE / RMSE 补充检验

本包汇集 2026-09-23 完成的两次分析：ELPD/MeanLogScore 的 P 值与旧版差异复核，以及 AUC 对 0.5、MAE/RMSE 对同训练方式 Null 的新增检验。使用已完成正式运行保存的 OOF 预测，新增 MCMC 拟合数为 0。

- [ELPD P 值解释、v1/v2/v3.4 对照及证据](ELPD_P_VALUES_zh.md)
- [AUC、MAE、RMSE 计算方法、完整结果与解释](AUC_MAE_RMSE_P_VALUES_zh.md)
- [全部 80 行新增检验结果](source/additional_metrics/supplementary_metric_tests.csv)
- [AUC 32 行](source/additional_metrics/auc_tests.csv) · [MAE 24 行](source/additional_metrics/mae_tests.csv) · [RMSE 24 行](source/additional_metrics/rmse_tests.csv)
- [一次下载完整补充包 ZIP](archive/v3.4-pvalue-supplement-20260923.zip)（GitHub 文件页点击 Download raw file；也可使用下方直接下载链接）
- [直接下载 ZIP](https://raw.githubusercontent.com/xlminfei/066/main/formal_results/v3.4_20260923/pvalue_supplement_20260923/archive/v3.4-pvalue-supplement-20260923.zip)
- [文件清单与 SHA-256](PAYLOAD_FILES.csv) · [归档大小及 SHA-256](archive_manifest.json) · [复现说明](REPRODUCE_zh.md)

## 不同 P 值回答的问题

| 部分 | 原假设/比较 | 抽样与校正 |
|---|---|---|
| 原正式 ELPD / MeanLogScore | 模型对 Null，或物种等权训练对记录等权训练的平均留出 log-score 差为 0 | 原生产设置 2,000 次物种配对 bootstrap；双侧正态近似；保持原 BH 家族 |
| 新增 AUC | 各折加权 AUC 的等权均值为 0.5；采用双侧检验 | 50,000 次 Fold × 物种类别组成分层的整物种重抽样 |
| 新增 MAE / RMSE | 模型减相同训练权重 Null 的误差差为 0；负值为改善 | 50,000 次物种配对重抽样；MAE/RMSE 使用 145 条 count/exact 记录、48 个物种 |

同一批记录、同一评价权重下，ELPD 总和与 MeanLogScore 只差一个共同尺度，差值和标准误一起缩放不会改变 Z/P。物种等权与记录等权则改变评价目标，不能把两者当成同一结论。

新增检验报告两列 BH：同一设计/评价下每个指标 6 项，以及三指标合计 18 项。18 项是本补充计算前指定的联合范围；两列均完整保留，不在看到结果后挑选更小的一列。原正式 ELPD P 值保持其原比较家族，未与新增指标重新混合校正。

## 结果如何阅读

五折、物种等权评价下，六个非 Null 的 AUC 比较在两种 BH 范围均低于 0.05；RMSE 的 M2 记录等权训练和 M3 两种训练亦如此。MAE 的结论依赖校正家族：按本指标六项 BH，没有一项低于 0.05；按三指标十八项 BH，M3 两种训练分别为 0.0342 和 0.0309。完整原始 P、两列校正 P、效应量和区间见 CSV，不能只挑显著行。

M3 主评价 MAE 仍约 28.6–28.9 个百分点。小 P 不等于误差已足够小，也不等于模型在所有指标上都有确证优势。AUC、点误差和完整预测分布的 log score 衡量不同方面，新增检验不会改写 ELPD 原结论。

所有这些推断均条件于现有已拟合的 OOF 预测；新增 AUC 还条件于原折号与物种类别组成。未重拟合，未纳入全部训练集重叠、分折/模型选择不确定性。极小 P 来自正态尾部近似，并非 50,000 次 bootstrap 直接测得同等稀有概率。十折部分折只有一个携带 LOW 记录的物种，限制已在结果中标记。

![主评价效应量与条件区间](source/additional_metrics/primary_supplementary_tests.png)

## 本包包含的文件

| 目录 | 数量 | 内容 |
|---|---:|---|
| source/elpd_audit | 53 | ELPD 解释、复核代码、旧版摘录、按物种贡献、方法/权重交叉对照、日志、测试及原清单 |
| source/additional_metrics | 35 | 预先固定的补充计算方案、计算与绘图代码、80 行结果、两份完整 RDS、图、解释及核验 |
| context/v3.4 | 63 | 冻结生产 R 模块/配置/输入/环境说明，以及原正式清单中的 31 个派生输出与清单 |
| context/repository | 12 | ELPD 数值复核所用 v2 表和相关 v1/v2 方法/输入文件 |

合计 88 个本轮分析原始文件，另附 75 个冻结依赖文件。全部逐字节复制；网页解读文件仅将本地链接改成可浏览的相对路径。两份原生中间对象完整保留：

- [80 组、每组 50,000 次 bootstrap 差值](source/additional_metrics/bootstrap_difference_draws.rds)：26,045,524 字节。
- [物种抽样次数矩阵、物种分组及支持数据](source/additional_metrics/bootstrap_species_multiplicities.rds)：3,884,804 字节。

本补充包不再次复制 256 个拟合对象，因为这些检验直接使用保存的 OOF 表即可复算。原生拟合对象和最初正式计算的全量材料仍在[原完整正式结果 Release](https://github.com/xlminfei/066/releases/tag/v3.4-formal-results)。原 11.36 GB 归档及标签保持历史身份；本次新增材料由这里的独立 ZIP 提供。

## 已有数值验证与本次交付验证

既有检验记录完整保留：18 项确定性检查、96 个原正式指标点值对照、80 组完整抽样分布检查、240 次逐记录展开的抽样复核，以及独立 Python 正态 P/BH 复算。ELPD 审计重现 v2 的 42 项比较、v3.4 的 48 项模型对 Null 和 32 项训练方式比较。

本次发布仅整理资料：重新检查源清单、逐文件字节复制、31 个原正式派生输出哈希、网页链接、ZIP 全量 SHA/CRC 读回与远端文件身份。交付过程记录保存在 delivery/。统计计算、科学结论和生产代码均未变。
