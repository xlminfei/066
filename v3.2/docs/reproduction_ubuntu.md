# v3.2 Ubuntu / Docker 运行说明

从仓库根目录构建。依赖锁仍为R4.6.1及79个必需R包；本次Docker构建和环境检查收据在review/。下面只有明确标注的合成测试会启动Stan采样，不拟合真实研究输入。

~~~bash
# 构建上下文必须是版本目录。
docker build --progress=plain -t ratio-analysis-v3-2:local ./v3.2

# 确定性回归与输入记录集合静态核对：不生成真实预测/分数。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-2:local Rscript /project/v3.2/tests/run_v32_regressions.R

# Beta概率与梯度合成参数测试；before要求复现旧错误，after检查当前源码。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-2:local Rscript /project/v3.2/tests/test_beta_intervals.R before
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-2:local Rscript /project/v3.2/tests/test_beta_intervals.R after

# 不等记录数真实合成MCMC集成：四模型、两路线、两训练、两折，共32拟合。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-2:local Rscript /project/v3.2/tests/test_unequal_integration.R

# 从上一步的实际合成后验独立复算OOF及全合成面板投影，不重新采样。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-2:local Rscript /project/v3.2/tests/test_unequal_posterior_audit.R

# 全五折/十折任务结构只用合成资料及采样替身，不产生真实MCMC结果。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-2:local Rscript /project/v3.2/tests/test_v32_fullgrid_synthetic.R
~~~

新测试输出放在review/下，与正式runs/results分开。二分类接口拟合采用2链、600迭代、300 warmup；最终joint接口测试采用2链、300迭代、150 warmup、adapt_delta=.9、max_treedepth=8，以控制接口测试成本。它们仍按正式诊断阈值记录结果，允许警告只限显式测试路径，不能流入正式审计。

真实研究的正式配置保持4链、4000迭代、2000 warmup、adapt_delta=.99、max_treedepth=12。未来用户明确决定启动时，先运行preflight，再调用src/v3_pipeline.R --stage all；**本轮没有运行该命令，也没有运行基于真实研究数据的smoke/fit/cv/predict**。

运行配置在config/analysis.json；--iter/--warmup/--chains/--cores/--seed覆盖仍拒绝，防止文档与实际设置分叉。种子、两条路线/四模型/两权重/固定五十折范围保留。

内部函数名保留_v3和V3_*作为兼容名称，但root确定当前v3.2目录且版本身份已更新。后验缓存代码、蓝图、输入、权重和采样信息必须匹配；旧v3.1缓存不能冒充当前结果。

完整Beta边界方法、测试模式及附加分支阈值检查命令见BETA_NUMERICS.md；审计范围和负例见AUDIT_CHAIN.md。7.1/7.2没有加入；7.3只增加count/exact点记录的带符号Bias及散点图。
