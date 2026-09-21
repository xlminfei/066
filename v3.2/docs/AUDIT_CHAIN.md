# v3.2 后验到指标的审计链

审计按当前输入、拟合身份与后验参数逐级复算，不能仅凭CSV哈希或表格行数宣布预测正确。入口src/audit_run.R，生产实现R/audit_run.R、R/prediction_audit.R。

1. 保留v3.1的任务清单、阶段收据、输入和源码身份检查；重建每个拟合请求，核对真实fit载荷，重新计算正式MCMC诊断。fixture后验与允许诊断警告的接口输出不能通过正式门槛。
2. 对所有CV拟合，从实际fit参数重新提取抽样；不允许bundle中便捷posterior字段替代实际fit。重新编码当前面板并验证与准备态相符；检查物种留出集合与训练集合不重叠。
3. 独立重算所有OOF行的预测均值、原始未加权log预测密度、PI、覆盖/重叠、元数据和适用范围标记。joint原始似然用R/Rmath的pbeta、dbeta、lbeta和必要的缩放密度积分，避免只和生产Stan同一表达式自我比较。随机预测区间复用规定种子和抽样顺序。
4. 对16个全数据拟合重算整个面板的Point、PosteriorMedian、CrI、joint PI与标记。当前真实研究16个全拟合尚未运行；测试用32个真实合成CV后验中的16个fold1后验投影整个12物种合成面板，这不是新增全数据拟合。
5. 在后验到OOF通过后重新计算逐折与总体指标。期望字段动态来自evaluate_evidence，因此新增Bias或支持物种数不能被旧硬编码字段清单遗漏。
6. 比较表使用完整主键，默认正式网格为48项model-vs-Null、32项training_method。核对Scope/Design/Route/Model/TrainWeighting/EvalWeighting、参考方向、重复/缺失键；重算全部已有比较数值。
7. 第7.3新增的quantitative_bias_summary.csv和quantitative_plot_source.csv也由已验证OOF重建，逐键核对Bias、有效物种数、EvaluationWeight、SignedError、坐标和身份；不能只看文件存在或哈希。

数值比较使用abs(actual-expected)<=1e-10*max(1,abs(expected))；逻辑值、主键和NA掩码严格匹配。CSV读回的integer/double差异、行序和空字符串元数据可按明确规则归一；NaN不能冒充NA。Beta函数的验收容差最终也与此要求一致，没有放宽后验审计来接受数值不准。

## 收据

正式审计输出audit_prediction_recompute.csv、audit_comparison_recompute.csv、audit_quantitative_recompute.csv及fit_audit.csv、audit_v3.json。开始时清空本次收据，失败留下FAILED状态和原因，不能残留旧成功表冒充本次通过。

本轮确定性审计在review/audit_deterministic/，包括35项参数夹具/篡改检查；这组检查不启动采样。负例包括：篡改OOF预测并重算下游指标、错折/记录键、篡改全表均值或PI、比较表缺项/重复/方向错误、NaN或缺新增字段，以及Bias/EvaluationWeight/SignedError/支持物种数篡改。

真实合成后验检查在review/unequal_integration/posterior_recompute_receipts.csv、posterior_audit_status.json：32个实际fit重开、1472行OOF及192行面板投影重算，48个预测篡改和32个原始分数篡改均拒绝。最终数值以这些机器收据及VALIDATION_v3_2.md为准。

新增定量两表另用tests/test_quantitative_artifacts.R同时检查真实合成运行和240任务合成替身运行，且Bias与主CV表必须一致。

## 仍然不能据此声称的内容

没有启动真实研究数据计算，因此正式256项真实数据拟合的成功路径未执行，正式诊断与科学性能仍未验收。短链合成拟合全部保存实际诊断失败状态，测试只证明数值/接口/身份可复算。当前复算共享编码、参数提取和适用性辅助函数；它能查出所测篡改与数值不一致，不能作为对全部模型假设或任意程序错误的数学证明。
