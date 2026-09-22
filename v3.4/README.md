# 比例预测建模 v3.4

基于v3.3，修复两类公共输入校验：完整合法的物种折表，以及joint点值列/比例范围。默认分析方法和所有合法输入的评分公式不变。

**本轮没有MCMC，没有真实研究数据拟合、预测或评分。** 只运行确定性/合成测试和已保存合成OOF的合法输入对照；旧拟合诊断状态没有改变。

- [本轮范围](docs/REQUEST_SCOPE_zh.md)
- [改了哪里、原错误、理由与测试](docs/CHANGE_DETAILS_v3_4_zh.md)
- [逐文件修改索引](docs/FILE_CHANGE_INDEX.csv)
- [当前流程](docs/PIPELINE_v3_4_zh.md)
- [完整验收结果与限制](review/VALIDATION_v3_4.md)
- [复验命令](docs/reproduction_ubuntu.md)
- [完整资料交付说明](docs/COMPLETE_ARCHIVE_zh.md)

缺少五折/十折之一、非法折号/重复物种等在拟合前拒绝。joint预测和count/exact观测点必须在[0,1]，0和1保留；interval不造点值。自查补齐缺失/重复点列的真空校验问题。

版本身份ratio_analysis_v3_4_weighted_20260922，报告REPORT_v3_4.md；内部_v3/_v32兼容函数名保留。正式16全拟合+240CV仍未运行。
