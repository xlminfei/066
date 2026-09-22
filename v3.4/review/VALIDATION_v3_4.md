# v3.4 验收报告

日期2026-09-22；基线3692f07840807c8abfcac58dd87d1218a68c1149的v3.3。仅修复完整折表与joint点值输入防护，合法分析方法不变。没有执行MCMC或真实研究数据模型计算。

|检查|实际结果|证据|
|---|---|---|
|旧版直接复现|151项中90项符合预期、61项暴露未拒绝的坏输入/入口；缺十折、NA折号、1.2点值均实际通过旧防护|input_guards_before/assertions.csv、status.json及log|
|新版防护|151/151通过；有限/整数/范围/唯一性/缺失设计检查、0/1边界和interval-only行为得到覆盖|input_guards_after/、final_test_v34_input_guards.log|
|拟合前阻止坏折表|旧版触达只报错的测试哨兵1次，新版0次；均未启动实际采样，新版不创建CV输出目录|before/after状态收据|
|自查补缺|初始148项通过后，追加3项暴露缺点列/重复点列绕过；保存失败后补齐合同并再次全部通过|point_column_gap_self_review.log、status/断言表；最终151项|
|合法输入结果不变|对1472条旧真实合成OOF与2944条本轮合成替身OOF，逐折/总体共640组、全部评分字段identical；默认两路线五折/十折表也identical|legal_equivalence/status.json、scoring_equivalence_receipts.csv及折表|
|原有确定性测试|52项通过|final_run_tests.log|
|权重/支持数/Bias回归|15项通过|final_test_v32_metrics.log|
|后验/比较/图源篡改审计夹具|35项通过，纯参数夹具；不是加载原生fit|final_run_audit_deterministic.log、audit_deterministic/|
|模板缓存/定量图源回归|通过；既有修复保留|final_test_binary_template_key.log、final_test_quantitative_diagnostics.log|
|完整任务编排|240项合成替身、480逐折/64总体、48模型比较/32训练比较通过；没有240次MCMC|fullgrid_synthetic/test_status.json|
|报告生成|5项口径/路径检查通过，REPORT_v3_4.md正确生成，固定评价目标说明保留|report_wording_fixture/|
|范围保护|23项通过：14核心R模块、5入口、Stan、除版本号外的完整配置、两原始输入不变|scope_preservation_checks.csv|
|解析|65个R/src/tests文件通过|final_parse_all.log|
|新Docker与环境|构建退出0；R4.6.1/79包锁检查、错误R版本/缺BH拒绝及干净临时库恢复通过|environment_build_v34.log、environment_test_v34.log及exit.json|

## 对结果的准确解释

两轮检查的实际初始问题和失败均保留。151是输入合同测试数，不是拟合数。旧版61个未达预期的组合来自两类缺口及相邻点列合同，不能称为61个独立模型错误。正常默认折表本来合法，已保存合法合成结果未被改写。

所有range检查先拒绝坏输入，不clip、不默默丢行、不重设权重、不改变MAE/Bias/ELPD或PI公式。interval ObservedPoint不是评分点值，NA继续有效；本轮不新增对它的点值指标。设计校验依据当前V3_DESIGNS，因此明确配置的两折集成测试仍可通过；正式配置仍只允许五/十折。

首轮在已验证v3.3镜像中运行，新建v3.4镜像后执行最终before和整个runner。最后针对点列自查补丁再执行一次完整回归，退出0。环境检查不受这项R输入合同修改影响，结果可复用。

## 没有执行的内容

- 没有真实数据smoke、全数据拟合、CV、预测或评分；原表仅静态哈希/合同/记录数量检查。
- 没有新合成MCMC，没有读取原生fit.rds。合法结果对照读取的是原32个合成拟合已保存的OOF CSV，其诊断失败状态未被改变。
- 未变的Beta/Stan生产实现与v3.3字节相同，本轮不重跑312组高精度/Stan测试，也不把旧收据当作新执行。
- 未完成正式16全拟合+240CV、长链收敛或真实性能验收。此次PASS限定于两处修复、相关回归与交付。
- 继承测试文件不表示本轮全部执行；本次清单为regression_runner.csv、before/after及环境收据。旧测试若需原生对象，可使用对应旧Release，不能误以为v3.4新增了那些拟合。

本轮现存源码、说明、中间轮次、测试输入/输出、日志、图件和来源文件全部归档读回并上传；本轮无原生RDS文件。最终上传/公开下载状态由releases/v3.4/中的实际收据记录。
