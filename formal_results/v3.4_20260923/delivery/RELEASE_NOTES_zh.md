# v3.4 正式运行结果（2026-09-23）

正式运行完成：16个全数据拟合、240个CV拟合，256项采样诊断及最终审计均通过。最终状态为 **COMPLETE_WITH_REVIEW_FLAGS**，18项训练内PPC提示原样保留。

## 直接查看

- [结果总入口和下载说明](https://github.com/xlminfei/066/blob/main/formal_results/v3.4_20260923/README.md)
- [中文ELPD、MAE、RMSE解读与图件](https://github.com/xlminfei/066/blob/main/formal_results/v3.4_20260923/ANALYSIS_zh.md)
- [运行退出、诊断、完整性及全部PDF复核](https://github.com/xlminfei/066/blob/main/formal_results/v3.4_20260923/RUN_REVIEW_zh.md)
- [正式结果表](https://github.com/xlminfei/066/tree/main/formal_results/v3.4_20260923/snapshot/v3.4/results)
- [原8份PDF图件](https://github.com/xlminfei/066/tree/main/formal_results/v3.4_20260923/snapshot/v3.4/figures)

## 完整内容

共778个源文件、11,406,427,751字节，包括全部256个原生fit.rds、运行源代码/输入/配置、所有中间文件、日志、结果CSV、8份76页PDF、后续复核渲染，以及4张指标比较图和中文分析。

完整ZIP拆为170个64 MiB以内分卷，附件名从v3.4-formal-complete.zip.part0001到part0170。另有13,758,438字节的v3.4-formal-results-light.zip，含全部522个非fit.rds文件，便于先查看结果。**完整资料无遗漏，原生拟合对象在完整分卷中。GitHub自动生成的Source code压缩包不含这些对象。**

下载restore_v3_4_formal.py后运行：

~~~bash
python restore_v3_4_formal.py --mode full --directory download-full --extract-to results-full
~~~

只看结果可用 --mode light。脚本支持重复运行和校验，默认不运行任何建模计算。

完整ZIP SHA-256：98f7c9157d87b8389b7934d8eef061c92262c557cc02dd11b6dffae98fd718eb

本地完整分卷恢复已核对778文件，全部SHA和CRC一致。源代码固定在c9ec1c58e173dd5209bbbe5e89b2213553fc0630；本结果快照标签固定在896d7d5e3f48e61c93d4f6e0fad88cd79d2afeef。旧版本及标签保持不变。服务器附件及公开下载最终验证收据将在交付目录中保存。

采样/审计通过仅证明约定计算完成。PPC、校准支持和外推标志仍需解释，M3相对Null的主要log-score差异区间仍跨0。
