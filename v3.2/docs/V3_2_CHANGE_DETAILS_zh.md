# v3.2 修改明细与验收边界

基线：2dcb4795712674cf793098049ab206fdb4ed8cee 的 v3.1/。用户指定只处理最新审查3.1—3.5及7.3；不增加7.1分类型独立评价、7.2额外不确定性/物种误差明细，不运行真实研究数据的拟合或评分。

## 逐项修改

|对应审查|文件/函数|修改前的问题或缺口|修改及理由|验证入口与证据|
|---|---|---|---|---|
|3.1|stan/joint_bb.stan：log_beta_interval、稳定尾部helper、record_log_lik|按hi是否超过0.5选择CDF差，与Beta分布位置无关，合法小概率可得到-Inf；原概率尺度下溢后再取log不能恢复；hi=1混合尾也受影响|保留同一Beta似然；使用参数相关的对称小尾log连分式，窄区间/抵消时使用logit变量积分；同时检查迭代值及形状导数收敛，失败明确reject。不加epsilon概率|tests/test_beta_intervals.R before/after；review/beta_before、beta_after、beta_after_round1；详见BETA_NUMERICS.md。旧反例在目标RStan实际复现；新概率/梯度不只与另一份相同公式互证|
|3.2|R/weights.R：check_weight_contract|record_equal也要求物种权重总和相同，A,A,B的1,1,1错误失败；错误权重可能仅凭总和相同通过|必须有单一已知Weighting、有限正权重、有效物种与总尺度；record_equal逐条=1，species_equal逐条=N/(S R_s)，同时覆盖种内权重一致性。训练权重公式不改|tests/test_v32_metrics.R；review/v32_metrics_before.log、v32_metrics_after.log及v32_metric_checks.json|
|3.3|R/metrics.R：evaluate_evidence；R/cross_validation.R字段清单；R/reporting.R|SpeciesUsed来自logscore集合，旁边MAE/RMSE/PI容易被误认为同一物种数|保留旧SpeciesUsed兼容含义并新增LogScoreRecordsUsed、LogScoreSpeciesUsed、PointSpeciesUsed、PISpeciesUsed；点指标集合只count/exact，不给interval插值|合成metric测试区分3/2/2；全网格合成区分12/11/11；只读input_support_counts.json核对真实输入51/50/48，没有产生真实预测或分数|
|3.4|R/prediction_audit.R；R/audit_run.R；R/bootstrap.R|以前主要验证保存OOF表到指标汇总，哈希不能证明最初OOF来自正确后验；全面板预测未从后验复算；比较表主要查文件存在|从验证后的拟合对象提取抽样、重新编码当前输入，复算全部折外记录及全面板物种；joint原始似然独立使用R/Rmath计算。检查48项模型对Null、32项训练比较的完整键及数值；新增图源/Bias表也由已通过复算的OOF重建对齐|tests/test_prediction_audit.R及run_audit_deterministic.R的故意篡改反例；tests/test_unequal_posterior_audit.R使用真实合成拟合。正式256拟合不存在，因此不声称正式审计成功路径已执行|
|3.5|tests/fixtures_v32.R、test_unequal_integration.R、test_unequal_posterior_audit.R|旧真实集成只Null/M1且每物种记录数一样，不能证实不等记录数的joint/M2/M3接口|构造12个纯合成物种，记录数4至15不等，含count/exact/interval及只有interval的物种；两折均不等权，M3有未见类别/缺失/不可估计方向。32次真实合成CV拟合覆盖四模型、两路线、两训练，每套接受两评价|review/unequal_integration：输入、权重对照、每个fit.rds、OOF、逐折/总体表、diagnostics、后验重算收据；只记录接口通过和具体诊断状态，不把短链警告写成正式收敛|
|7.3|R/quantitative_diagnostics.R；metrics.R：weighted_bias；workflow/reporting接线|MAE不能说明高估/低估；缺少定量OOF预测—观测图|Bias=加权平均(预测−观测)，与MAE共用count/exact集合及权重；正值高估、负值低估。导出每记录图源、权重、带符号误差，图含y=x及样本数；测试图醒目标识合成。分箱不改变、没有加7.1/7.2指标|tests/test_quantitative_diagnostics.R手算与行序不变性；test_v32_fullgrid_synthetic.R检查64总体表和32定量Bias组传递；真实合成集成后绘图与数值对齐|

## 不等记录数/M2测试额外暴露的问题

R/fitting.R 原编译模板缓存只用Stan代码哈希作为key。M1和M2可能生成完全相同的通用Stan程序，但brms公式和设计列名不同；复用M1的brms模板更新M2数据会找不到M1列。本轮实际新增M2测试已复现该错误，保留于review/unequal_binary_prepare.log。

新增 binary_template_key_v32，将Stan代码、模型名和设计列纳入brms模板身份。同模型/列的不同训练权重仍可复用已编译程序，但必须用当前数据重新采样。这是实现3.5时发现的必要修复，不改变模型。tests/test_binary_template_key.R记录同Stan代码/不同列名的碰撞，并验证新key区分M1/M2。原始bundle缓存的完整数据/权重身份仍保留。

## 交付与兼容

- v3.2使用独立目录和版本身份ratio_analysis_v3_2_weighted_20260921，旧v1/v2/v3/v3.1不改；训练seed与模型/先验/固定五折十折设计不改。
- 内部V3_*变量和部分_v3函数名保留为兼容API，不表示加载旧源码；各入口通过当前版本root加载。
- REPORT_v3_2.md是新的正式报告路径。旧结果不得复制成当前正式结果。
- R包锁与版本沿用已验证的79包环境；Docker安装路径更新到v3.2。首次新构建发生60秒部分下载超时，增加下载等待时间和同一固定版本镜像来源，摘要验证未取消。失败与重试日志均保存。
- 完整源码差异、文件/哈希清单、日志和完整原始RDS归档都会提供；最终推送/上传状态以实际收据为准。

## 必须保留的边界

原始Beta数值测试证明指定形状/区间域内的数值及梯度，不保证任何浮点极端参数。权重公式是既定带权似然尺度选择，不代表新增独立信息。Bias接近0仍可能存在大的正负抵消误差，须与MAE/RMSE和图一起看。

所有本轮真实采样测试使用合成资料，不能作为真实研究的预测性能或收敛结果。正式256项研究拟合、其实际MCMC诊断/OOF模型优劣及整套正式报告均未执行。已有外部/导出代码保留但不是本轮新增或验收目标。
