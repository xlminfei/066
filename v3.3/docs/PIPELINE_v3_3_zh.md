# 当前研究流程与v3.3的位置

输入仍为冻结六位点表和逐记录观测表。365个物种的六个位点包含Site3/20/117/151/196/315，Site151只作适用范围元数据，其余五位点进入M1/M2/M3。Null仅截距；M1按既定位点参考状态（Site315为K/T组）编码；M2按C/K/S/T与其余状态分组；M3保留冻结面板中出现至少4次的氨基酸，低频归OTHER；MISSING独立表示。代码在R/data_encoding.R，v3.3未修改。

1. R/bootstrap.R、config.R、data_encoding.R加载版本配置，检查输入、编码字典和蓝图。原始count/exact/interval逐条保留。
2. R/weights.R分别建立训练/评价权重。record_equal每条为1；species_equal训练权重N_train/(S_train R_s)，评价按当前指标有效集合计算。
3. R/fitting.R及stan/joint_bb.stan拟合binary/joint_bb。binary对可判定HIGH/LOW记录使用加权Bernoulli；joint中count使用真实分母的Beta-binomial，exact/interval使用报告分布的密度或区间质量及1端点质量。不给exact编造分母，不把interval变成中点。
4. R/workflow.R、cross_validation.R组织固定物种五折/十折各一次，物种全部记录同折。4模型×2路线×2训练=16全数据拟合，CV为240拟合；同一套预测接受两种评价，四组合彼此相关。
5. R/prediction.R、metrics.R、comparison.R计算未乘训练权重的原始log预测密度、AUC/ROC/Brier、ELPD/MeanLogScore、MAE/RMSE/Bias和PI等。各指标支持物种数分别列出；count/exact用于点误差，interval不插补。训练方法和模型的比较必须固定路线、CV设计和评价权重。
6. R/quantitative_diagnostics.R、plotting.R、reporting.R输出Bias与预测—观测图、其他既有图表和REPORT_v3_3.md；本版只更正比较口径文字。
7. R/prediction_audit.R、audit_run.R从实际后验与当前输入复算OOF/全面板，再核对指标、48/32项比较表及图源。v3.3修复此处R参考函数的有限尾差精度风险。

本轮只执行合成/确定性测试、已有合成对象复算和静态输入核查。provenance/formal_status.json明确正式拟合数0；不能将review目录的夹具图表当作研究结果。旧32个短链拟合全部FAILED_DIAGNOSTICS；目前没有新的收敛通过结论。
