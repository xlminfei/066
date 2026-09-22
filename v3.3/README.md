# 比例预测建模 v3.3

本版在v3.2基础上完成限定收尾：修复独立R审计参考函数“结果有限但尾差不够精确”的风险，并更正MeanLogScore比较解释。生产Stan、模型编码、权重、Bias、数据和CV设计保持不变。

**本轮未运行真实研究数据计算，也未启动新的合成MCMC。** 复用的32个原短链拟合保留v3.2身份与FAILED_DIAGNOSTICS状态，仅用于新版审计回归。

- [修改范围](docs/REQUEST_SCOPE_zh.md)
- [逐项修改、原错误、理由与验收](docs/CHANGE_DETAILS_v3_3_zh.md)
- [文件级修改索引](docs/FILE_CHANGE_INDEX.csv)
- [当前流程与代码职责](docs/PIPELINE_v3_3_zh.md)
- [测试结果与边界](review/VALIDATION_v3_3.md)
- [复验命令](docs/reproduction_ubuntu.md)
- [全部资料与原生对象的交付](docs/COMPLETE_ARCHIVE_zh.md)

新R参考与100位精度独立计算在312例中均满足原审计门槛；原函数有8例超差。旧32个实际合成后验经原身份核验，新审计复算1472条OOF及192条面板预测，最大绝对差8.4377e-15。报告明确比较训练方式或模型时固定同一路线、CV设计和评价权重；不同目标的分数不直接排优劣。

内部_v3与少量_v32函数名保留为兼容API，不表示调用旧版生产目录。新运行版本身份为ratio_analysis_v3_3_weighted_20260922，报告名为REPORT_v3_3.md。
