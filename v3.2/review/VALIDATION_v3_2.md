# v3.2 验收报告

本次验收对象为独立v3.2目录，基线是提交2dcb4795712674cf793098049ab206fdb4ed8cee的v3.1。用户限定的审查3.1—3.5与7.3均有对应实现与测试；7.1、7.2未增加。真实研究输入只做合同及记录集合静态核查，没有启动真实数据smoke、全拟合、CV、预测或评分。

## 结果

|检查|实际结果|原始证据|
|---|---|---|
|原有确定性回归|52项断言通过|final_run_tests.log|
|权重、指标支持集合、Bias|15项通过，保留旧权重校验失败反例|final_test_v32_metrics.log、v32_metrics_before.log、v32_metric_checks.json|
|后验审计与篡改负例|35项通过；含Bias、权重、误差、物种数及键篡改|final_run_audit_deterministic.log、audit_deterministic/|
|M1/M2 brms模板冲突|旧同Stan不同公式碰撞复现，新key通过|unequal_binary_prepare.log、template_key_before.log、final_test_binary_template_key.log|
|源码解析|54个R/src/tests文件通过|final_parse_all.log|
|Beta旧反例|目标RStan实际复现两个错误的-Inf；before测试按预期结束|beta_before/|
|Beta最终数值与自动微分|289值、583梯度通过；值最大绝对误差9.0949e-13，最大尺度梯度误差3.9863e-8|beta_after/status.json及完整CSV|
|Beta分支阈值追加复验|24值、48梯度、12对跨界变化通过；最大尺度值误差3.1924e-12，小于1e-10标准|beta_switches/|
|五折/十折全任务编排|240个合成替身任务，2944OOF行、480逐折、64总体、48模型比较、32训练比较、32Bias组|fullgrid_synthetic/test_status.json、test_v32_fullgrid_synthetic.log|
|实际不等记录数合成拟合|最终32项CV网格完成；四模型、两路线、两训练、两折；1472OOF、64逐折、32总体|unequal_integration/integration_status.json、unequal_integration_final.log|
|实际合成后验复算|32拟合对象重开；1472OOF与192面板投影全部复算，最大绝对差8.4377e-15；48预测/32原始分数篡改拒绝|unequal_integration/posterior_audit_status.json、posterior_recompute_receipts.csv|
|新增两表与主CV一致性|真实合成与替身全网格两套结果均通过；Bias及图源逐键复算|quantitative_artifact_audit.log、quantitative_artifact_receipts.csv|
|真实输入支持数静态核对|153行/51joint物种，152行/50binary物种，145行/48点指标物种；未拟合|input_support_counts.json|
|Docker构建与环境|新镜像构建成功，R4.6.1、79包完整锁验证通过；错误R版本/缺传递依赖拒绝；干净临时库恢复通过|environment_build_retry.log、environment_test_final.log及exit.json|

## 合成采样诊断必须如实解释

32项是最终保留的真实合成拟合网格，不包含旧源码上的中间尝试；中间对象和日志仍归档。binary用2链、600迭代/300预热；joint用2链、300迭代/150预热、adapt_delta=.9、max_treedepth=8。正式参数仍为4链、4000/2000、.99、12，没有放宽正式阈值。

**这32项短链拟合全部未通过正式诊断门槛（FAILED_DIAGNOSTICS=32）。** 接口测试显式允许继续，以检验模型/记录/权重传递和后验复算；每项Rhat、ESS、发散、树深、EBFMI保存在unequal_integration/fit_diagnostics.csv。不能把PASS_INTERFACE_ONLY解释为收敛通过、区间校准或预测有效。正式流程的诊断门仍然会拒绝这些对象；它们也标为INTEGRATION_TEST_ONLY。

实际拟合证明M2/M3/joint的接口和不等权数据处理可执行，不证明真实研究表现。合成全面板投影来自16个fold1拟合，没有额外假称完成16个全数据拟合。

## 重复检查发现与处理

1. Beta初版窄尾触发阈值1e-7在附加边界例误差达2.48e-7，不能满足1e-10审计容差。扩展直接积分路径至1e-4，重新编译测试并重跑受影响的joint合成拟合；没有放宽审计容差。历史源码、对象和原始结果保存在beta_switches_before_threshold_fix/与intermediate_joint_before_threshold_fix/。
2. 实际M2合成拟合发现brms模板只按通用Stan码缓存会误用M1公式；加入模型与设计列身份后全部网格通过接口验收。
3. 独立范围复核发现新Bias/图源只检查哈希，主审计已补独立重建比较和篡改负例；再次回归通过。
4. 目视检查新增四页合成定量图的首尾页；四页页眉、坐标、模型/权重标签、Bias符号与支持数可辨识。改为方形绘图区避免等比例坐标自动扩张造成空白。CSV记录值不因绘图改变。

## 保留的限制和未运行内容

- 正式16全拟合+240CV为NOT_RUN_BY_USER_INSTRUCTION；无真实研究AUC、ELPD、MAE/Bias或365物种新预测可报告。
- 没有实际执行由全部正式256项拟合通过诊断构成的成功验收路径；当前证据覆盖确定性、编排、实际合成接口和后验复算。
- Beta检验是已列参数与边界域的数值证据，不是任意双精度参数的保证；Lentz分母保护实际激活的极端情形未专项验收。
- 物种平衡权重仍是既定的加权似然尺度；原有固定OOF条件bootstrap、探索性P值等限制保持。未增加7.1分类型评价或7.2额外不确定性分析。
- 保留的旧版兼容测试文件并不等于本轮全部执行；本轮实际命令、脚本、退出码和输出以此报告和regression_runner.csv为准。

源码、文档、成功/失败日志、中间数值、全部原生合成RDS和图件共同归档。Git存可审阅的文本/图件；RDS保存在完整GitHub Release分片归档，可逐文件SHA-256验证。归档与远端上传验收另见交付清单。
