# 比例预测建模 v3.2

本版仅落实用户指定的审查3.1—3.5与7.3：稳定Beta区间似然、修正权重校验、分开报告指标物种数、后验到原始预测复算审计、不等记录数的M2/M3/joint真实合成测试，以及定量OOF预测—观测图与带符号Bias。

**本次不启动真实研究数据计算。** 16全拟合+240CV正式任务保持未运行。所有新拟合/图件验收使用合成数据，输入表只做合同/计数静态核对。

- [当前流程、模型编码与代码职责](docs/PIPELINE_v3_2_zh.md)
- [修改范围](docs/REQUEST_SCOPE_zh.md)
- [修改前问题、位置、理由与测试](docs/V3_2_CHANGE_DETAILS_zh.md)
- [Beta数值/梯度方法与证据](docs/BETA_NUMERICS.md)
- [后验复算审计链](docs/AUDIT_CHAIN.md)
- [全部资料与原始RDS交付](docs/COMPLETE_ARCHIVE_zh.md)
- [文件级修改索引](docs/FILE_CHANGE_INDEX.csv)
- [测试结果与边界](review/VALIDATION_v3_2.md)
- [Ubuntu/Docker使用](docs/reproduction_ubuntu.md)

模型范围仍为Null/M1/M2/M3 × binary/joint_bb × 两种训练，复用两种评价；五折为主、十折为敏感性分析，各一套固定物种划分。Site151只作元数据，Site315留在多位点模型中；不新增其他模型、7.1分类型独立评价或7.2额外不确定性分析。

Bias=加权平均(预测−观测)，正为高估、负为低估，与MAE共用count/exact集合；interval不变成点值。LogScoreSpeciesUsed/PointSpeciesUsed/PISpeciesUsed分别指出使用的物种集合；真实冻结输入对应51/48/48，binary为50物种。

代码可用性与正式科学结果是不同结论。完整发布证据包括失败尝试、成功日志、数值表及原始合成fit.rds，并以逐文件SHA-256及GitHub服务器摘要校验交付。
