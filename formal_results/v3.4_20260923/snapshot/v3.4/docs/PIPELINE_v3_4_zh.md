# 当前流程与v3.4防护的位置

模型定义沿用v3.3。冻结365物种六位点输入（Site151仅元数据）、51/50响应物种的逐记录count/exact/interval资料进入原流程；本轮只做静态合同/哈希检查，没有执行真实数据模型计算。

1. bootstrap/config/data_encoding读取当前版本配置和输入、分类High/Low、冻结M1/M2/M3编码。Site315继续建模，Site151不进入预测矩阵。
2. weights分别生成训练与各指标有效集合的评价权重。保留所有合格记录；species_equal仍为N/(S R_s)。
3. fitting和joint_bb.stan拟合binary与joint_bb，共16全数据拟合。count使用真实分母，exact不补分母，interval不插补点值。
4. workflow/cross_validation生成固定五折/十折，各模型与两训练共用对应物种划分，共240CV拟合。**v3.4在run_cv入口要求折表完整、每行折号与物种身份合法，坏输入在fit回调之前停止。**
5. prediction、metrics、comparison计算原始OOF分数和两种评价，四组合复用两种拟合而非四独立实验。**v3.4的joint评分器先检查比例范围，再计算既有ELPD/MAE/RMSE/Bias/PI等，公式不变。**
6. ppc、plotting、quantitative_diagnostics、reporting生成既有检查、图件及REPORT_v3_4.md。模型/训练比较固定路线、CV设计与评价权重。
7. prediction_audit与audit_run从后验复算预测/原始分数，再检查指标、比较表、图源及完整输出。v3.3数值保护保持不变。

--stage all仍按准备→全拟合→PPC→CV/评价→面板预测→图表/报告→正式审计运行；它不会自动运行测试套件。此次未调用真实数据的all/smoke/fit/cv/predict。

本轮验收入口为tests/run_v34_regressions.R，测试结果在review/，正式计算状态在provenance/formal_status.json。实验可用性、采样质量与预测性能是不同验收层次；本次防护修复不产生新的收敛或性能结论。
