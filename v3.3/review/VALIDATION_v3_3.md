# v3.3 验收结果

日期2026-09-22。范围是审查第四节的正式R审计参考精度、第六节的比较口径文案和第八节的有限收尾。不是一次模型重构；没有新后验拟合，也没有真实研究数据计算。

## 已执行结果

|检查|结果|证据|
|---|---|---|
|目标R环境原反例|旧函数有限值-20.016548414999001，独立参考约-20.016548394229577；误差2.07694e-8超过2.00165e-9门槛|tail_difference_before.json/log|
|定向R审计before/after|7例+混合向量：旧版2例失败，向量失败；新版全部通过，最大绝对误差3.55271e-15|audit_beta_before、audit_beta_after|
|独立100位参考|mpmath1.3.0校验wheel，312例生成成功，精确使用实际IEEE双精度输入|audit_beta_three_way/high_precision_reference.csv及status.json|
|三方数值核验|312区间例中旧R有8例超差；新R、实际Stan及两者互比全部满足既定1e-10尺度门槛|audit_beta_three_way/three_way_values.csv、status.json|
|新R精度|最大绝对误差5.15676e-12，最大尺度误差5.00227e-13|同上|
|未变Stan与新R互比|最大尺度差8.18482e-12；5个原始interval/含端点混合似然例最大差7.10543e-15|raw_record_audit_comparison.csv|
|原有确定性测试|52项断言通过|final_run_tests.log|
|权重/指标回归|15项通过，Bias/支持集合未变|final_test_v32_metrics.log|
|后验/表格/篡改审计夹具|35项通过|final_run_audit_deterministic.log、audit_deterministic/|
|brms模板缓存、定量图源|原回归均通过，没有撤回v3.2修复|final_test_binary_template_key.log、final_test_quantitative_diagnostics.log|
|报告实际生成|5项通过，固定route/CV/eval规则出现，旧歧义语句消失|report_wording_fixture/|
|范围保护|19项通过：15核心R模块、Stan、去版本字段后的完整配置、2张输入表均不变|scope_preservation_checks.csv|
|完整CV编排|240个合成替身任务，480逐折、64总体、48模型比较、32训练比较；没有MCMC|fullgrid_synthetic/test_status.json|
|旧后验身份与新版复算|32个v3.2真实合成fit重新验证；1472OOF和192面板行复算，最大绝对差8.4377e-15；32个篡改分数拒绝|saved_fit_reaudit/|
|旧fit不能伪装新正式结果|32对象均保持原版本/FitKey/载荷摘要；v3.3版本门与原正式诊断门拒绝；原诊断FAILED_DIAGNOSTICS=32|source_fit_identity_and_diagnostics.csv|
|源码解析|61个R/src/tests文件通过|final_parse_all.log|
|新Docker与环境|构建退出0；R4.6.1及79包锁通过，错误版本/缺BH拒绝，临时库恢复通过|environment_build_v33.log、environment_test_v33.log及exit.json|

## 复核范围及结果解释

312区间例包含继承的266个参数例、24个生产分支切换例，以及22个新增反例/R保护阈值两侧例。新R独立使用R/Rmath和原始Beta密度积分；高精度参考使用另一实现mpmath不完全Beta及a=1/b=1闭式公式。实际Stan对象的functions块与未变生产源码逐行一致，并核对编译对象源码内容及SHA。没有靠放宽容差、加epsilon或删例使测试通过。

初步定向/三方测试使用已验证v3.2镜像；与其R/79包版本完全一致的新v3.3镜像构建后，最终整个回归和独立归档路径上的32对象复算再次执行成功。必要输入均随归档提供，不依赖其他项目或记忆。

自我复核检查了尾选择与换尾后的gap一致性、多个形状参数向量对应、独立积分的误差门、上下端点/窄区间、未改变Stan/权重/先验/编码，以及生成报告实际文字。没有发现本次范围内仍未修复的问题。测试工具的初始转义错误和下载失败日志原样保留，见CHANGE_DETAILS；它们不被当作生产验收通过。

## 未完成、未执行与限制

- 本轮新增真实研究拟合0、新增合成后验拟合0。Fixed_param只用于调用函数目标，不是MCMC后验收敛试验。
- 被复用的32项短链对象全部仍为FAILED_DIAGNOSTICS；本次没有将它们改称“收敛通过”，也没有完成此前讨论的长链合成收敛验收。
- 正式16全拟合+240CV与真实资料的AUC/ELPD/MAE/Bias、完整正式成功审计路径仍未运行。修复参考函数不能证明模型真实预测有效。
- 数值测试证明列出的有限参数域内满足门槛；独立积分可能在域外失败并停止，不保证任意浮点极端参数均可精确计算。
- 旧兼容测试文件保留不等于本轮都执行。以regression_runner.csv、三方/后验复算和环境收据为实际执行清单。

全部本轮源目录文件会逐项归档读回核对，原始RDS也随Release提供。成功/失败日志和中间文件均保留，旧版生产目录不覆盖。
