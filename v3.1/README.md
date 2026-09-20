# 比例预测建模 v3.1

本版修复 v3 的统计口径、模块接口、缓存与审计问题，保留原研究设计。它是代码与测试交付，不含正式研究数据的256项拟合结果。

研究目标：从预定蛋白位点编码预测新物种的比例/HIGH–LOW，评价编码整体相对于Null的预测价值；不据此推断单个位点因果效应。主要口径为五折物种分组CV的物种等权评价，十折与记录等权为补充。

固定范围为 Null/M1/M2/M3 × binary/joint_bb × 两种训练权重，每个拟合复用两种评价权重。16项全拟合+240项CV，共256项正式任务。Site151仅作输入和适用范围元数据；Site315仍在M1/M2/M3中；无Site315单位点模型、Scheme A或新增随机/系统发育结构。

- [完整流程、模型与模块职责](docs/V3_1_WORKFLOW_zh.md)
- [逐项审查、修复与证据矩阵](docs/REVIEW_MATRIX_zh.md)
- [Ubuntu/Docker运行命令](docs/reproduction_ubuntu.md)
- [固定R依赖环境](scripts/ENVIRONMENT.md)
- [测试结果与限制](review/RELEASE_VALIDATION_zh.md)

Point为后验均值，CrI描述期望量的后验不确定性。joint全面板/外部PI针对未来exact报告；CV的count PI按该条Total使用Beta-binomial，exact/interval报告机制另行处理。PPC用同一记录子集和观测机制，属于训练内检查。

N/(S R_s)是似然权重及尺度约定，并不等于N个独立观测。物种簇bootstrap比较区间条件于固定OOF预测，不包含重新拟合、分折或模型选择的不确定性。训练资料及冻结365物种面板不能自动代表所有新物种或所有实验条件。

正式运行从 src/v3_pipeline.R --stage all 开始。预检或接口测试PASS不能自动授权发布正式科学结论；严格拟合诊断与完整产物审计仍须通过。
