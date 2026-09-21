# v3.2 Beta 区间似然数值修订与验收

日期：2026-09-21。范围：仅修复联合模型中 Beta 区间质量及上端点混合尾的数值实现；不改变分布、似然定义、均值参数化、先验、训练权重或研究设计。本测试未读取真实研究数据，未启动正式拟合，也没有产生研究结论。

## 原问题及 fail-before 证据

v3.1 的 log_beta_interval() 按 hi<=0.5 选择两个 lower-tail CDF 之差，否则选择两个 survival CDF 之差。0.5 不反映 Beta(a,b) 的位置；所选的两个概率都舍入到 1 时，相减错误变成零，log 概率为 -Inf。反过来，原生概率先下溢后再取 log 也无法保留很小的真实质量。

实际编译旧 Stan 函数，RStan log_prob()/grad_log_prob() 的结果为：

| 合成反例 | 旧 log 概率 | 闭式参考值 | 旧 a/b 梯度 |
|---|---:|---:|---|
| Beta(1,100)，区间 [0.4,0.5] | -Inf | -51.0825623886737 | 两者错误为 0 |
| Beta(200,1)，区间 [0.6,0.7] | -Inf | -71.3349887877465 | 两者错误为 0 |

证据目录 review/beta_before/ 保存参数 CSV、概率/梯度 CSV、status.json 和完整编译运行日志；tests/stan/beta_interval_before.stan 保存原始生产源码。

## 修改位置及理由

仅生产文件 stan/joint_bb.stan 被本数值任务修改。

1. 新增 beta_log_cf_lower()：使用不完全 Beta 的连分式在 log 域计算小尾质量，避免先计算极小浮点概率再取 log。使用 (a+1)/(a+b+2) 作为连分式计算方向的切换条件，并用 I_x(a,b)=1-I_(1-x)(b,a) 对称关系。
2. 新增 beta_log_lower_stable()/beta_log_upper_stable()：统一 lower/upper tail 稳定计算，精确处理 0 和 1。
3. 改写 log_beta_interval()：按参数相关位置选择两个同侧尾质量，并使用 log1m_exp 做差。完整支持 [0,1] 的质量仍精确为 1。
4. 对窄内部区间（宽度 < 1e-5*min(lo,1-hi)）、所选尾的 log 值相差 < 1e-4，或尾差出现非有限结果，调用 beta_log_interval_quadrature()。该函数作 logit 变量替换，包含 Jacobian 后积分核为 exp(a*log(x)+b*log(1-x)-lbeta(a,b))。GL8 节点每轮将分段数翻倍，检查质量及两种形状导数收敛，避免很接近的 CDF 相减以及端点奇异性。
5. record_log_lik() 的 hi==1 分支也改用 beta_log_upper_stable()，然后与端点原子质量 rho*m 取 log_sum_exp。count beta-binomial、exact 内点密度、exact=1 端点质量均保持原定义。
6. 连分式不能只检查概率值：整数形状参数会让概率值提前终止，而其形状导数尚未收敛。新增 beta_cf_product()/beta_cf_inverse() 同时追踪 a,b 的显式一阶导数，仅用于检查迭代是否收敛。最终返回值仍由 Stan 自身自动微分；有限差分参考不使用这两个 helper。

没有给概率加 epsilon。Lentz 分母保护使用 1e-300，仅防止算法除零，不是概率下限。连分式最多 10000 次，要求值及两种形状导数连续三步达到阈值；积分最多 512 个 GL8 分段。不能收敛时明确 reject，不返回伪造的有限概率。

## 独立验收方法

测试入口：tests/test_beta_intervals.R before|after。测试自动提取生产文件的整个 functions 块生成 probe，以确保检查的就是实际生产函数。probe 使用无约束 theta 参数，明确在 target 中调用上述函数，随后执行 RStan log_prob(adjust_transform=FALSE) 和 grad_log_prob(adjust_transform=FALSE)。

Fixed_param 只用于创建可调用 Stan 目标函数的对象，不是 MCMC 后验拟合。参考概率来自 R pbeta(log.p=TRUE)、可用的闭式解，或独立 stats::integrate() 缩放密度积分。参考梯度来自参考函数的五点中心有限差分，未调用 Stan 梯度或生产连分式。

最终检查 289 个 log 概率值和 583 个梯度：

- 18 个定向边界例；包括上述两个反例、log 质量小于 -700 的尾部、靠近 0/1、宽度约 1e-12 的区间、U 形分布、集中分布、完整支持及切换条件左右。
- 7×7×5=245 个固定形状/区间网格；a,b 取 0.05、0.2、1、5、50、200、1000，覆盖左右极端与中部区间。
- 3 个小形状例，最小参数为 1e-8，检查尾差抵消后的直接积分。
- 对 18 个定向例再检查实际 exp(log_a)/exp(log_b) 链式梯度。
- 5 个实际 record_log_lik 链例，检查 logit(m)、logit(rho)、log_phi_ratio 的梯度，包括含端点原子、窄区间及 U 形分布。

| 项目 | 门槛 | 实测最大误差 | 结果 |
|---|---:|---:|---|
| log 概率尺度误差：abs(Stan-ref)/max(1,abs(ref)) | <1e-10，与发布审计一致 | 1.371125e-13（绝对误差最大 9.094947e-13） | PASS |
| 梯度尺度误差：abs(Stan-ref)/max(1,abs(ref)) | <3e-6 | 3.986342e-8 | PASS |
| 所有生产计算值/梯度有限 | 全部 | 全部有限 | PASS |

最大梯度差出现在集中分布的 log 形状有限差分比较；报告保留实际误差，没有把数值参考当作无限精度真值。上述测试覆盖的形状范围为 1e-8 至 2000，并非对任意双精度参数或任意窄于机器分辨率的区间作保证。

最终证据：review/beta_after/ 的 parameter_cases.csv、record_parameter_cases.csv、value_comparison.csv、gradient_comparison.csv、status.json、provenance.json、compile_and_test.log。review/beta_after_round1/ 保存第一次较小测试集通过的中间记录。tests/stan/ 中保留 old/new probe 和 RStan 编译对象；最终源码、probe、测试脚本 SHA-256 见 provenance.json。

容器：ratio-analysis-v3-1-local:validated，镜像 sha256:6c1e0e2737e6a03dda651cb8bbe1daaa908b5c852c44106a974345335ebc97be。R 4.6.1；rstan 2.32.7。

## 追加复核：积分触发阈值也必须满足发布审计

第一版实现把尾 log-CDF 差小于 1e-7 的区间转入直接积分。289 点网格虽然通过，追加的阈值两侧检查发现该阈值仍偏小。具体反例为 lo=0.2、hi=0.8、a=1.80354921488859e-08、b=3.60709842977718e-08，恰位于旧阈值外侧：Stan log 概率为 -17.2166076953689，独立积分为 -17.2166079436348，误差 2.4826583455706e-7。

它满足最初的 3e-7 数值检查，却不满足正式审计的 abs(error)<1e-10*max(1,abs(reference_logprob))。因此没有放宽审计容差，而是把直接积分触发阈值由 1e-7 扩展到 1e-4。CDF 相减的舍入损失不一定能靠更多连分式迭代消除；改变计算路径仍然计算同一 Beta 积分，不改变模型，不给概率加 epsilon。

旧源码、probe、约 22 MB 编译对象、289/583 原证据、两侧测试脚本及输出全部保存在 review/beta_switches_before_threshold_fix/。其中历史 status.json 的 PASS 只对应旧门槛，assessment.md 明确解释为什么还需要修正。

最终生产源码重新编译，289/583 检查再次通过，并把值门槛收紧至与发布审计一致。另用 tests/test_beta_switches.R 复用最终编译对象检查 24 个 log 概率、48 个形状梯度及 12 组成对变化：

- 宽度触发阈值 1e-5 两侧，分别取相对偏移 ±0.01、±0.0001、±0.000001；包括 Beta(2.5,7.5) 和 Beta(1,1)。
- 新尾 log-CDF 差阈值 1e-4 两侧，a=b 和 b=2a 两组；根由独立 R pbeta 求得，检查相对偏移 ±0.01、±0.0001。ExpectedBranch 是依据生产触发条件及独立参考量标注的预期计算路径。
- 旧阈值附近的 4 个反例也重新检查，包括上述完全相同的最坏参数；现在它们均进入直接积分。
- 对每一对跨界参数，额外比较“Stan 的两侧变化”与“独立参考函数的两侧变化”，并逐点校验 a,b 梯度。参考函数为独立 R 原始 Beta 密度的缩放自适应积分；参考梯度为五点有限差分。

| 最终追加检查 | 实测最大误差 |
|---|---:|
| log 概率绝对误差 | 3.287859e-11 |
| log 概率尺度误差 | 3.192405e-12，满足 <1e-10 |
| 梯度尺度误差 | 3.818115e-11 |
| 两侧 log 概率变化的尺度残差 | 3.186218e-12 |
| 两侧梯度变化的尺度残差 | 6.550051e-11 |

原最坏反例修订后的 log 概率为 -17.2166079436348，绝对误差 3.552714e-15。全部原始输出在 review/beta_switches/，包括 cases.csv、value_and_gradient_comparison.csv、cross_switch_changes.csv、独立参考根、status.json 和 test.log。

这些结果证明所列有限偏移下的两侧计算与独立参考一致，不证明浮点函数处处严格连续。Lentz 分母保护实际激活的极端情况仍未专项覆盖；也不保证任意双精度参数。最终生产 SHA-256 为 db491633fcadbd940c2e78280660a47cd037f46795c9dce2258f9381c4571430。

## 重跑命令

在 v3.2 目录挂载为容器 /work 后执行：

    docker run --rm -v ABSOLUTE_V3_2_PATH:/work -w /work ratio-analysis-v3-1-local:validated Rscript tests/test_beta_intervals.R before
    docker run --rm -v ABSOLUTE_V3_2_PATH:/work -w /work ratio-analysis-v3-1-local:validated Rscript tests/test_beta_intervals.R after
    docker run --rm -v ABSOLUTE_V3_2_PATH:/work -w /work ratio-analysis-v3-1-local:validated Rscript tests/test_beta_switches.R

before 的正常验收终点是 BETA_BEFORE_FAILURE_REPRODUCED：它要求复现旧错误，并不代表生产代码测试失败。after 要求输出 BETA_AFTER_NUMERICAL_AND_AUTODIFF_PASS。

## 方法依据

- NIST DLMF §8.17，尤其不完全 Beta 定义、对称关系和连分式：[https://dlmf.nist.gov/8.17](https://dlmf.nist.gov/8.17)。
- Boost Math incomplete beta 算法说明，互补尾及不同数值区域的计算：[https://www.boost.org/doc/libs/latest/libs/math/doc/html/math_toolkit/sf_beta/ibeta_function.html](https://www.boost.org/doc/libs/latest/libs/math/doc/html/math_toolkit/sf_beta/ibeta_function.html)。
- RStan 官方 log_prob/grad_log_prob 参数空间及接口说明：[https://mc-stan.org/rstan/reference/stanfit-method-logprob.html](https://mc-stan.org/rstan/reference/stanfit-method-logprob.html)。

这些验收证明具体数值修复在上述测试域内有效；不能代替正式模型的 MCMC 诊断、真实数据的 OOF 评价或研究结果验证。
