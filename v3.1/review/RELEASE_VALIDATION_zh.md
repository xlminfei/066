# v3.1 发布验证记录

结论：本版代码、统计合同、代表性真实拟合接口和发布环境完成了下列验证。正式研究数据的16个全拟合和240个CV拟合未启动，没有正式研究性能、正式PPC或科学结论。

本次复核没有照单采纳全部意见。保留了逐记录加权Bernoulli、joint共同均值、一套拟合接受两种评价和N/(S R_s)尺度约定；明确其适用条件。修复了原审查指出的实现错误，也纠正了上一轮修改新引入的count PI、PPC、跨路线列数、诊断放行、ROC聚合/浮点末端、缓存实际载荷和JSON收据问题。所有修复对应证据及解释见 docs/REVIEW_MATRIX_zh.md。

|验证层级|结果|证据及边界|
|---|---|---|
|完整Docker构建|PASS|review/environment_build.log；R4.6.1，79个必需R包完整闭包锁定与加载验证；系统apt层不承诺按位重建|
|确定性合同/回归|PASS|review/verified_run_tests.log；分类边界、缺失/OTHER、权重、非有限值、bootstrap、行空间、ROC端点和PI机制|
|R解析|PASS|review/verified_parse_all.log；运行入口、模块和测试脚本|
|冻结真实输入与256任务计划|PASS|review/preflight_v3.json；365面板物种、153记录、50 binary/51 joint物种；输入未改变|
|完整240 CV任务编排|PASS（替身）|review/orchestration_test.json；4,880条记录、480逐折、64汇总；替换采样/评分边界，不能冒充实际拟合|
|真实合成两折集成|PASS_INTERFACE_ONLY|review/integration/integration_status.json；16真实拟合，216条合成OOF、32逐折、16汇总；确实留出物种|
|短链抽样诊断|16项未达正式门槛|review/integration/fit_diagnostics.csv；最大R-hat约1.0451，无divergence/树深命中。没有将这些拟合改称正式收敛|
|不等记录数的加权后验|PASS（独立数值对照）|review/weighted_posterior/quadrature_comparison.csv；2个合成binary Null拟合均通过严格诊断。记录等权期望0.131609、MCMC0.132741；物种等权期望0.5、MCMC0.502278；最大误差0.002278|
|Stan/R原始似然一致性|PASS|review/integration/stan_r_likelihood_agreement.json；600值，最大绝对误差1.065814e-14|
|真实Null/M1外部预测|PASS|review/verified_check_external.log；单独/批量/重排与新缺失类别；仍是合成数据接口测试|
|缓存/状态/产物负例|PASS|review/verified_test_artifact_guards.log；坏RDS、交换实际fit、伪造诊断、错误配置/任务网格、RDS往返、旧状态和修改产物拒绝|
|完整365物种分页图|PASS（布局夹具）|review/visual_fixture/visual_status.json；5,840行标签与数据逐主键匹配，4份各9页PDF，首尾页渲染核对；全部标明SYNTHETIC TEST FIXTURE|

18个真实拟合均为合成测试（16接口短链+2独立积分对照），不属于正式研究的256个任务。正式M2/M3等全网格MCMC、正式完整模型包导出和研究数据收敛/校准仍需要用户另行启动正式流程，不能从代表性接口测试自动推断。

## 保存与省略

- 保存全部当前源码、配置、锁文件、两张冻结输入表、重现脚本、说明、测试日志、CSV/JSON指标、布局图源和数值后验快照。
- review/validation_snapshots.rds 保存18个合成拟合的参数抽样、原始joint log_lik、训练数据、身份、蓝图和诊断，可核对测试数值；它明确是验证快照，不能作为生产模型或恢复拟合的缓存。
- 约300MB以上的原始fit.rds主要含平台相关的编译载荷，保留在本地测试目录，不重复上传。review/compiled_fit_inventory.csv逐项列出大小、SHA-256、FitKey和载荷摘要；测试脚本可重新生成。没有删除本地文件。
- 早期中断或失败尝试的日志作为调试证据保留，不用其旧PASS代替本表的终态验证。首次执行存在内核重置中断；之后真实集成发现并修复了NULL beta提取和R数据/附加属性校验问题。
- 本轮是验证与回归驱动的复核，部分检查在实现后补充，不声称所有代码都遵循了严格的测试先行顺序。

## 可支持的结论

复核范围内没有留下已确认而未修复的实现缺陷，代码与测试包可以发布。不能由此声称研究模型已收敛、优于Null、已具有足够外部泛化能力，或所有可能数据/环境组合都已被证明正确。正式流程仍会严格检查诊断、输入身份、逐项任务、输出覆盖与来源，失败时写FAILED并停止。

发布目录迁移检查：在仓库根挂载后，从容器 /tmp 工作目录调用 /project/v3.1/tests 的解析、52项断言和真实输入准备检查，全部通过。验证不依赖原先 /project/v3 路径。完整源码和产物清单位于 provenance/MANIFEST.csv。
