# 复现与文件身份

本包的 source/ 为两次分析原件，含原始日志、中间文件和本地绝对路径；顶层两篇解读只转换网页链接。context/ 为已发布正式结果和必要历史依赖的字节副本。首先使用 Python 3 运行以下只读校验：

~~~bash
python scripts/verify_package.py .
~~~

检验逐文件大小/SHA、原始两个清单、冻结 OOF 身份、原正式 31 个派生输出，以及本包三篇导读的相对链接。不执行 R、拟合或抽样。

## 使用原 R 环境复算已保存统计

R 4.6.1、rstan 2.32.7；完整锁文件见 context/v3.4/renv.lock。原已验证 Docker 镜像 ID：sha256:c67aade078ec1510b1b036a1a34c6ad0aad66534296b9e6587cd9f283093ca58，原本地标签 ratio-analysis-v3-4:formal-20260922204324。镜像未在本次公开上传；可按已有环境说明恢复同一依赖版本。已有数值结果可直接读取，不要求先安装该环境。

复算应先把 source/additional_metrics 和 source/elpd_audit 复制到另一个全新的工作目录，保留本包原件。例如工作目录内有 additional_metrics/ 与 elpd_audit/ 两个副本。以下 PACKAGE 是解压后的本包绝对路径，WORK 是工作副本目录绝对路径。命令面向 Ubuntu shell，每行可独立执行：

~~~bash
Rscript "$WORK/additional_metrics/test_supplement_functions.R" "$WORK/additional_metrics" "$PACKAGE/context/v3.4"
Rscript "$WORK/additional_metrics/verify_bootstrap_results.R" "$PACKAGE/context/v3.4" "$WORK/additional_metrics"
python "$WORK/additional_metrics/verify_pvalues_independently.py" "$PACKAGE/context/v3.4" "$WORK/additional_metrics"
python "$WORK/elpd_audit/independent_pvalue_checks.py" "$PACKAGE/context/v3.4" "$WORK/elpd_audit"
~~~

上述命令核验已保存结果。如果需要按冻结种子重新计算 bootstrap，另执行：

~~~bash
Rscript "$WORK/additional_metrics/calculate_supplement_tests.R" "$PACKAGE/context/v3.4" "$WORK/additional_metrics"
Rscript "$WORK/elpd_audit/recompute_pvalue_attribution.R" "$PACKAGE/context/repository" "$PACKAGE/context/v3.4" "$WORK/elpd_audit"
Rscript "$WORK/elpd_audit/check_model_contracts.R" "$PACKAGE/context/repository" "$PACKAGE/context/v3.4" "$WORK/elpd_audit"
~~~

这些脚本没有模型拟合入口。重新计算后再执行上面的验证。MAE/RMSE 是各次抽样上重算的全局加权指标，RMSE 先算加权 MSE 再开方；不要替换成物种内 RMSE 的简单平均。

绘图脚本 plot_supplement_tests.R 接受工作 additional_metrics 目录作为单个参数，使用 Microsoft YaHei 字体；缺少该字体时需先提供同一字体或明确记录替换。原 PNG/SVG 已随包保留。报告生成脚本和 check_v2_bh.py 保留其原始本地路径，属于执行来源证据；正式的可移植数值复核入口是上面接收路径参数的脚本。

v1_archive_inventory.json、v1_pvalue_search.json 与 v1_selected/v1_evidence 保存了此前扫描及摘录。若要重新扫描 v1 全部四个历史归档，inventory_pvalues.py / compare_version_contracts.py 还需要同仓库完整 v1/archive（此补充包未重复装入这些原归档）；不能在仅有 context 的目录运行后，把空归档扫描误称复现成功。重新扫描并非读取或复核本次新增 P 值所必需。

## 推断参数

- 原正式 ELPD 比较：生产 bootstrap 2,000 次、原种子及分组由冻结配置/代码控制；数值稳定性审计另用 20,000 次 × 5 个种子，未替换正式结果。
- 新增指标：50,000 次，seed_base=20260923，各折/设计种子规则见 ANALYSIS_PLAN.json 与代码。
- P=2×Phi(-|差值/SE_bootstrap|)，SE 是 bootstrap 分布标准差，不除以 sqrt(50,000)。95% 区间是未经多重校正的百分位区间，不是正态 P 的严格反演。
- AUC 的 Null 恒为 0.5，P=1 是结构性标记，排除在 BH 校正家族外；非 Null 零方差不允许自动得到 P=0。
- 这是固定 OOF 的探索性条件近似，不是重新训练全流程置换检验，也不是外部验证。

## ZIP 范围

ZIP 包含 PAYLOAD_FILES.csv 列明的每个文件，以及该清单本身。ZIP 不把自己再次打包；archive_manifest.json 与之后产生的 delivery 收据留在结果目录，避免自包含递归。可用 archive_manifest.json 中 SHA-256 核对下载完整性。GitHub 所有 source/context 文件均为实际文件，两个 RDS 没有换成占位链接。
