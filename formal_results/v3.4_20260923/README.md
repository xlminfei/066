# v3.4 正式运行结果与完整证据

> **P 值解释与补充检验已整理（2026-09-23）**：[完整补充目录](pvalue_supplement_20260923/README.md)、[ELPD P 值及旧版对照](pvalue_supplement_20260923/ELPD_P_VALUES_zh.md)、[AUC 对 0.5 / MAE / RMSE 的方法与结果](pvalue_supplement_20260923/AUC_MAE_RMSE_P_VALUES_zh.md)、[完整 ZIP](pvalue_supplement_20260923/archive/v3.4-pvalue-supplement-20260923.zip)。含全部 88 个分析原始文件、50,000 次 bootstrap 的两份完整 RDS、代码、日志和验证。使用原 OOF 结果，无新增拟合；条件近似推断和两种 BH 范围的限制均保留。原正式归档保持发布时身份，新增材料单独打包。

**正式计算已完成：16个全数据拟合＋240个CV拟合，全部256项采样诊断和最终审计通过。最终状态为 COMPLETE_WITH_REVIEW_FLAGS，保留18项训练内PPC提示。**

- [中文结果解读与ELPD/MAE/RMSE补图](ANALYSIS_zh.md)
- [运行退出、全部诊断和图件复核](RUN_REVIEW_zh.md)
- [程序生成的完整报告](snapshot/v3.4/reports/REPORT_v3_4.md)
- [结果CSV目录](snapshot/v3.4/results/) · [原始PDF图件](snapshot/v3.4/figures/)
- [新增PNG/SVG图件、解读、绘图源数据及脚本](snapshot/quantitative_metric_supplement_20260923/)
- [正式运行日志与检查记录](snapshot/run_logs_v34_20260922204324/)
- [最终审计](snapshot/v3.4/review/audit_v3.json) · [全部256项诊断](snapshot/run_logs_v34_20260922204324/postrun_check_20260923/all_256_saved_diagnostics.csv)
- [778文件逐项清单](files.csv) · [完整归档身份与分卷清单](archive-manifest.json)
- [GitHub完整结果发布页](https://github.com/xlminfei/066/releases/tag/v3.4-formal-results)

## 正式运行身份

代码固定在 c9ec1c58e173dd5209bbbe5e89b2213553fc0630，版本 ratio_analysis_v3_4_weighted_20260922。运行从北京时间2026-09-22 20:48:17至2026-09-23 12:42:16，约15小时54分钟，容器和正式进程退出码均为0。

输入为365物种冻结六位点表和51物种153条观测；Site151不进入预测矩阵。binary使用50物种152条可分类记录；joint_bb使用51物种153条记录；MAE/RMSE/Bias使用48物种145条count/exact点值记录。

Null/M1/M2/M3，两条路线，两种训练，每套预测接受两种评价。五折和十折各一套固定物种划分。正式设置为4链、每链4000次迭代、2000次预热，adapt_delta=0.99，max_treedepth=12。

## 包含什么

三个目录完整保留，共 **778个源文件、11,406,427,751字节**：

| 目录 | 文件数 | 内容 |
|---|---:|---|
| v3.4 | 524 | 原代码、配置、输入、测试和历史验证；本次prepared状态、计划、256个原生拟合对象、结果、PDF、报告和正式审计 |
| run_logs_v34_20260922204324 | 214 | 构建、环境、回归、预检、正式日志，启动/退出记录，诊断汇总，PDF渲染、复核脚本及说明 |
| quantitative_metric_supplement_20260923 | 40 | 三项定量指标及独立binary ELPD图，高清PNG、SVG、预览、图源、中文解读、脚本、校验及首轮中间文件 |

**完整归档没有按大小或扩展名省略源文件。** 256个fit.rds合计11,350,681,431字节，全部在完整分卷中；其余522个文件同时逐字节放入snapshot，便于网页浏览。旧v1至v3.4目录和标签不覆盖。

两篇中文网页导读仅转换本地链接；原始说明及其路径仍在snapshot及归档中保留。GitHub自动生成的“Source code”ZIP不含原生拟合对象，完整资料应按下面的Release附件恢复。

## 下载全部资料，或先查看结果

完整ZIP为11364497982字节，拆成 **170个分卷**，每卷最多64 MiB。

完整ZIP SHA-256：

~~~text
98f7c9157d87b8389b7934d8eef061c92262c557cc02dd11b6dffae98fd718eb
~~~

结果浏览包 v3.4-formal-results-light.zip 为13758438字节，包含全部522个非fit.rds文件；需要原生后验对象时必须下载完整包。

使用Python 3.10或更高版本运行[恢复脚本](restore_v3_4_formal.py)，只用标准库，不安装依赖、不启动模型：

~~~bash
# 下载结果浏览包、校验并解压
python restore_v3_4_formal.py --mode light --directory download-light --extract-to results-light

# 下载全部分卷、合并ZIP、校验778文件，再解压
python restore_v3_4_formal.py --mode full --directory download-full --extract-to results-full
~~~

脚本支持重复运行，已匹配SHA的分卷会复用。手动下载后可加 --offline 只验证本地文件；未指定 --extract-to 时只下载、合并和校验。解压目录必须为空，避免覆盖既有文件。完整下载、合并和解压合计需要约35 GB空间。

每卷和完整ZIP均有SHA-256，恢复后验证每个源文件大小、SHA及ZIP CRC。分卷遵循[GitHub Release附件规则](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。

## 结果边界

- 最终审计重开256项拟合，复算4880条OOF＋5840行面板预测，共10720行，全部通过。
- 21份结果CSV完整；原始8份PDF共76页完整渲染。新增4张指标图均逐项核对正式数值。
- 18项PPC提示均来自joint_bb的物种等权评价；校准箱和物种外推状态亦保留。
- M3在主评价中的点估计较好，但相对Null的log-score差异区间仍跨0；不能把执行成功或点估计排名写成显著优势或科学有效性已确证。
- 历史合成测试FAILED_DIAGNOSTICS和发布前NOT_RUN快照是历史证据。本次状态应查看snapshot/v3.4/review/final_v3_status.json与audit_v3.json。

## 打包与上传证据

本地完整包读回778文件、结果浏览包读回522文件，SHA与CRC全部通过，见[归档构建验证](archive_build_validation.json)。上传、服务器SHA/大小及公开下载最终收据在delivery目录补充。

首次打包发现的ZIP索引复用问题已由独立反例复现并修正，错误归档未上传；失败日志、修正脚本与回归证据保留在交付记录中。

## 最终交付核验（2026-09-23）

**已完整发布，181个Release附件全部核对服务器大小和SHA-256，零遗漏、零不一致。**

- 本地实际合并170分卷，778个源文件逐项SHA和CRC全部通过。
- 匿名公开下载结果浏览包，解压并核验全部522个文件；匿名下载完整包首/中/末分卷（0001、0086、0170）与恢复脚本，校验均通过。没有将抽样下载描述为重新下载全部11.36 GB。
- 交付执行证据ZIP公开下载并读回399个文件，通过全部校验；其中包括打包、恢复、上传日志和178项主附件收据。证据ZIP自身及两个配套清单的最后上传收据保存在delivery/final_upload_receipts，避免递归打包。
- Git网页镜像522个源文件与原件逐字节相同，旧版本目录改动0。

[最终交付状态](DELIVERY_STATUS.json) · [181附件远端核验](delivery/remote_delivery_verification.json) · [公开下载记录](delivery/public_download_validation.json) · [交付证据公开读回](delivery/final_delivery_public_readback.json)

[直接下载结果浏览包](https://github.com/xlminfei/066/releases/download/v3.4-formal-results/v3.4-formal-results-light.zip) · [下载完整恢复脚本](https://github.com/xlminfei/066/releases/download/v3.4-formal-results/restore_v3_4_formal.py)
