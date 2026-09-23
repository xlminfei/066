# v1、v2与v3.4：P值变化的证据审查

审查日期：2026-09-23。仓库快照161c3fb780fd2d937f4c6823a912feedf8226a47；v3.4实际运行代码c9ec1c58e173dd5209bbbe5e89b2213553fc0630。

**核心结论：本次并没有失去全部P<0.05结果。分类路线仍有22/24项模型对Null比较的BH P<0.05；定量M3在记录等权训练/评价下的原始P仍约0.040和0.047。之前解释的是定量、物种等权主评价，不能概括成整个v3.4“没有显著结果”。**

v2曾有小于0.05的原始P值和特定校正口径下的P值，这一记忆可由文件证实。将v2的同一批预测按当前物种等权口径重评后，M3五折P约0.120，与本次0.103同属未达到0.05；这不是新版把一个同定义的显著结论凭空算没了。

本轮仅核查和重算已保存的OOF分数，未改生产代码、输入、参数、正式结果或既定比较家族，未进行任何新MCMC拟合。方法交叉对照和bootstrap数值稳定性只用于解释差异，不替换原始分析。

## 1. 首先确认当前究竟有哪些P值

| 路线 | 模型对Null比较数 | 原始P<0.05 | BH P<0.05 |
|---|---:|---:|---:|
| binary | 24 | 23 | 22 |
| joint_bb | 24 | 2 | 0 |

另外32项两种训练方式的比较，原始P及BH P均未小于0.05。它们与模型对Null的检验不是同一个问题：它们检验物种等权训练与记录等权训练的预测差异，而v1/v2并没有这套两训练方式对照，不能把这32项P直接拿去对应旧版模型对Null的P。

例如五折、物种等权评价、记录等权训练时，分类M3对Null：P=0.008120，BH P=0.012531。本项目这些P值针对留出log score差，不能改称AUC对0.5的检验、位点系数检验或MAE/RMSE检验。

## 2. 能直接核对的旧版与新版例子

下面均是joint_bb中M3对Null，并固定记录等权训练；仅明确改变CV设计、评价口径及版本。v2采用其按折数分开的M1/M2/M3对Null九项BH文件，不能把这列与其全42项BH列混用。

| 版本 | CV | 训练 | 评价 | 原始近似P | BH校正P | BH家族 |
|---|---|---|---|---:|---:|---|
| v2 | 五折 | 记录等权 | 记录等权 | 0.026938 | 0.134946 | 每折数9项、含三条路线 |
| v3.4 | 五折 | 记录等权 | 记录等权 | 0.039993 | 0.121385 | 同路线/折数/评价下6项 |
| v3.4 | 五折 | 记录等权 | 物种等权 | 0.102759 | 0.584681 | 同路线/折数/评价下6项 |
| v2 | 十折 | 记录等权 | 记录等权 | 0.024832 | 0.048466 | 每折数9项、含三条路线 |
| v3.4 | 十折 | 记录等权 | 记录等权 | 0.047089 | 0.154422 | 同路线/折数/评价下6项 |
| v3.4 | 十折 | 记录等权 | 物种等权 | 0.201701 | 0.796093 | 同路线/折数/评价下6项 |

由表可见：

- 在同为记录等权训练/评价时，v3.4的原始P仍小于0.05，旧版的弱原始信号并未完全消失。
- v2五折的九项BH P本来就是0.134946，不应说它的主分析校正后已经显著。
- v2十折的0.048466来自特定九项校正家族；其原始比较表全42项校正中，同一联合M3为0.141426。
- 当前重点解释的“定量物种等权评价下未达0.05”是另一评价目标，不能直接与旧版记录等权原始P对照。

## 3. 用完全同一份预测隔离评价权重影响

以下不重新拟合，也不改变任何模型预测；两版都用新版的同一种物种bootstrap算法，比较五折M3与Null。

| 固定的OOF预测 | 评价方式 | 同一新版bootstrap下的平均增益 | 标准误 | 原始近似P |
|---|---|---:|---:|---:|
| v2原预测 | 记录等权 | 0.113864 | 0.045171 | 0.011711 |
| v2原预测 | 物种等权 | 0.117958 | 0.075905 | 0.120182 |
| v3.4原预测 | 记录等权 | 0.092344 | 0.044962 | 0.039993 |
| v3.4原预测 | 物种等权 | 0.120722 | 0.073989 | 0.102759 |


**即使仍用v2的预测，只将评价切换为物种等权，P也从0.011711变为0.120182。** v3.4的物种等权P为0.102759，甚至略小于这一同口径下的v2值。因此不能用“旧版显著、新版不显著”推断代码把模型性能算坏。

对于同一份v3.4预测，记录等权到物种等权时，平均增益从0.092344升至0.120722，但标准误从0.044962升至0.073989。平均增益约增加30.7%，标准误约增加64.6%，于是增益/标准误从2.054降至1.632。

这次P变大并不是因为物种平均增益更小，而是其不确定性相对于增益更大。

令d_sr为一条留出记录的log-score差，R_s为该物种记录数。记录等权看sum(d_sr)/N；物种等权看mean_s[sum_r(d_sr)/R_s]。两者目标不同。以当前模型为例，51物种中32个平均改善、19个变差；19物种只有1条记录，31物种至多2条，最多的物种有23条。稀疏物种既有明显改善，也有明显变差，等权后这种差异在总体不确定性中更充分体现。

| 物种 | 记录数 | 物种内平均log-score差：M3−Null |
|---|---:|---:|
| Poecilia_latipinna | 1 | +1.6232 |
| Xiphophorus_maculatus | 1 | +1.5507 |
| Carassius_carassius | 1 | +1.2202 |
| Cirrhinus_molitorella | 1 | +1.2202 |
| Pygocentrus_nattereri | 1 | -1.1449 |
| Ctenopharyngodon_idella | 1 | +0.9593 |
| Trichopodus_trichopterus | 1 | -0.8793 |
| Carassius_auratus | 4 | +0.8116 |

这些物种全部保留，没有删去负差值或异常记录。

## 4. 标准误算法变了，但不能简单解释成“新版更保守”

v2原本也按物种聚类：先求每物种总差D_s，再用sqrt(S × var(D_s))估计总ELPD差的SE。它不是把所有153条记录一律当成独立单位计算标准误。两版也都采用双侧正态近似尾概率2*pnorm(-abs(z))，没有从单侧改双侧。

v3.4同样按物种重抽样。记录等权时，每次重抽样用sum(D_s*)/sum(R_s*)；物种等权时，用mean(D_s*/R_s*)。这相对于旧版解析SE既改变了估计方式，也明确了平均指标的分母处理。不能笼统说bootstrap一定放大SE。

事实上，固定v2五折M3的OOF和记录等权目标，仅将旧解析SE换为当前bootstrap，原始P从0.026938变为0.011711，反而更小。这否定了“因为新版用了bootstrap，所以P全部变大”的解释。

ELPD总和与MeanLogScore若只相差同一个常数，差值和SE一起缩放，Z/P不变。导致此处变化的是相对评价权重、抽样单位和分母处理，不是把总和写成均值这一单位变化本身。

## 5. BH校正家族也发生了变化

BH取决于同一校正家族内的全部原始P值、数量和排序。[R官方p.adjust文档](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/p.adjust.html)说明其输入是一组P值，BH控制假发现率，不能只看单个P值解释校正结果。

v2被引用的十折家族有9项：三模型×三路线。其5个较小P值来自binary的M1/M2/M3、joint_bb的M3、Scheme A的M2。排序第五的原始P约0.026925，因此BH候选值为0.026925×9/5≈0.048466。

v3.4的模型对Null家族固定在同一Family、Scope、EvalWeighting、Route、Design内，每组6项＝3模型×2训练。不同路线及评价权重不在同一家族中。因此，不能把旧9项家族的0.0485和新joint_bb六项家族的0.1544当作同一校正条件下的比较。

为了核查是否只是新增训练数量使校正不通过，我另算了“仅单一训练的三模型”诊断口径。当前M3记录等权训练/评价的BH P仍为五折0.107771、十折0.141268。这个诊断没有替换正式六项家族，也未给出新的显著结论。

家族如何界定应依据研究问题与预先方案，而非事后选择更小的校正值。这里也不能将v2的跨路线家族一概说成数学错误；它与本次家族的定义不同，必须明确区分。

## 6. 数据、编码、模型设置与分折是否被改坏

已确认：

- v1/v2/v3.4的153条原始观测字节相同；365物种位点表内容相同，其字节差异可完全由换行符解释。
- 实际计算v2与v3.4的Null/M1/M2/M3设计矩阵，按等价类别名对齐后，365物种全部元素差为0；列数分别0、10、10、50。
- 两版共同的先验及4链/4000迭代/2000预热、adapt_delta和树深度设置一致。
- 记录等权下，旧聚合binomial与新逐记录Bernoulli关于参数的似然等价，差别只是常数；独立固定概率检查误差约1.24e-14。
- joint_bb的count/exact/interval数学观测模型保留，数值算法更稳定；记录等权训练时每条训练权重为1。
- Site315仍在M1/M2/M3中；删除独立Site315候选模型不等于删除该预测位点。删除Scheme A也未改写joint_bb的观测模型。

**分折确实不同。** v2基础种子20260918，v3.4为20260920，实际CV分折生成规则也不完全相同；旧十折分类按混合/全HIGH/全LOW物种分配，新版采用每折均含两类的受控随机划分。下表以同折物种对核对，排除了只更换折号名称的可能。

| 路线 | 折数 | 同一物种集合 | 分组仅是改名吗 | 旧版同折物种对 | 新旧仍同折物种对 |
|---|---:|---|---|---:|---:|
| binary | 5 | 是 | 否，分组确实改变 | 225 | 42 |
| binary | 10 | 是 | 否，分组确实改变 | 104 | 7 |
| joint_bb | 5 | 是 | 否，分组确实改变 | 235 | 50 |
| joint_bb | 10 | 是 | 否，分组确实改变 | 105 | 14 |

因此，即使记录训练、记录评价和SE算法对齐，两版的预测增益仍会不同。v2五折M3联合路线的平均增益0.113864，本次为0.092344，数值下降约18.9%；采用同一新版SE算法时SE几乎相同，P从0.011711升至0.039993。

本轮没有做“完全相同旧折表、两套实现”的配对重拟合，因此不能将这部分差异百分之百归因于折表，或给不同修复分配精确贡献。已确认的变化包括实际训练/留出物种组合及重新抽样；数值实现更新也存在。当前证据不支持把P变化解释成数据丢失、位点编码改变或P值公式算错。

## 7. 是否只是bootstrap随机种子波动

正式分析仍为预先配置的2000次bootstrap。为检查其计算波动，我只对现有五折M3记录训练的51个物种配对差值，使用5个明确列出的种子各做20000次重抽样；没有新CV、没有重拟合，也没有修改正式P值。

- 记录等权评价：近似P范围0.03502—0.03807，均小于0.05。
- 物种等权评价：近似P范围0.10002—0.10608，均大于0.05。

这支持“评价口径的差异不是这一次bootstrap种子偶然造成”的判断。它不能校准模型选择或重复拟合的不确定性，也不是额外独立实验证据。

## 8. v1的证据边界

检查了v1主要代码/手册及四个结果归档，共1720个归档文件条目（归档之间存在重复副本）。其主要CV比较表有ELPD、ELPD_Difference、PairedSE及MC复核字段，未找到与v2/v3.4同定义、可直接复现的频率P值列。存在P_LOO，但它是有效模型复杂度，不是显著性P值；[loo官方术语说明](https://mc-stan.org/loo/reference/loo-glossary.html)明确给出该定义。

而且v1的统计问题不同：包括U/P进化结构和独立Site315；主要CV的参考模型是按分数选出的最佳候选，例如joint/species用M1_P，而非统一Null。v1联合路线以整折联合预测积分log(mean(exp(sum(log_lik))))评分，v2/v3则对逐记录log(mean(exp(log_lik)))相加或加权，两者不能混为一谈。

v1的四个CV比较组都带AnyModelMCReview=TRUE，明确标记有限抽样联合分数需要复核、不作确定排名。因此，本轮能确认v2的旧P<0.05记录，但不能冒称已经确认v1某个同定义P值的变化；也不能从当前存档断言你在其他v1材料中从未看到过小P值。

## 9. 额外发现的v2历史表来源一致性问题

v2的paired_elpd_comparisons.csv可由其当前保存的cv_record_scores_v2.csv重算复现，42项最大误差约4.80e-14。但paired_elpd_M1M2M3_vs_Null_corrections_by_fold.csv里的6项Scheme A原始差值/P值与这张42项表不同。

例如十折Scheme A M2的原始P分别为0.0205028与0.0198473。这两张表各自的校正数学可复现，但不是完全相同的原始比较输入；目前没有足够证据把差异归因于某个具体历史重算步骤。

binary和joint_bb的原始差值/P值在两张表中一致；联合M3的九项家族BH结果仍是五折0.134946、十折0.048466，故该历史问题不改变上面的核心解释。详细逐项差异保存在v2_historical_table_source_discrepancy.csv。

## 10. 实际完成的验证及限制

| 核验 | 结果 |
|---|---|
| v2原42项比较复算 | 通过，最大误差约4.80e-14 |
| v3.4模型对Null的48项比较复算 | 通过，最大误差约7.77e-15 |
| v3.4两种训练的32项比较复算 | 通过，最大误差约3.31e-14 |
| 独立Python正态尾概率及BH复算80项 | 通过，误差约1e-15 |
| v2与v3.4四个设计矩阵 | 365物种全部元素一致 |
| 共同先验和正式抽样设置 | 一致；随机种子与折表另行记录为不同 |
| 96项固定OOF方法交叉对照 | 已完成，仅用于解释差异 |
| 已发布31个正式派生输出SHA | 全部未改变 |
| 新MCMC拟合、代码修改、正式结果替换 | 均未进行 |

当前所有比较P值仍是固定OOF预测条件下的近似推断，不包含完整重拟合、模型选择等不确定性。[loo交叉验证说明](https://mc-stan.org/loo/articles/online-only/faq.html)指出交叉验证分折依赖和模型设定问题会影响SE/正态近似；小样本时尤其不能把0.049与0.051解释成模型质量的断崖式变化。

本轮没有对每个历史拟合重新采样、没有恢复v1/v2全部原生RDS、没有为了匹配旧P值更换本次主评价。已确认本次P值计算可复现，并解释了旧版与新版对比时最主要的口径差异；旧版Scheme A表格来源不一致作为独立未修复发现保留。

## 主要证据文件

- [当前模型对Null比较](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/results/model_vs_null.csv)
- [旧版42项比较](C:/Users/minfei/Documents/ChatGPT/建模/publication/v3_4_formal_results_20260923/repository/v2/results/derived/paired_elpd_comparisons.csv)
- [旧版按折数的九项校正表](C:/Users/minfei/Documents/ChatGPT/建模/publication/v3_4_formal_results_20260923/repository/v2/results/derived/paired_elpd_M1M2M3_vs_Null_corrections_by_fold.csv)
- [M3对照总表](C:/Users/minfei/Documents/ChatGPT/建模/audits/pvalue_version_comparison_20260923/M3_joint_pvalue_reconciliation.csv)
- [同一OOF的方法与权重对照](C:/Users/minfei/Documents/ChatGPT/建模/audits/pvalue_version_comparison_20260923/fixed_OOF_method_weighting_counterfactuals.csv)
- [按物种的配对预测增益](C:/Users/minfei/Documents/ChatGPT/建模/audits/pvalue_version_comparison_20260923/paired_species_logscore_contributions.csv)
- [bootstrap数值稳定性检查](C:/Users/minfei/Documents/ChatGPT/建模/audits/pvalue_version_comparison_20260923/bootstrap_numerical_stability_audit.csv)
- [历史表来源差异](C:/Users/minfei/Documents/ChatGPT/建模/audits/pvalue_version_comparison_20260923/v2_historical_table_source_discrepancy.csv)
- [独立P/BH和源文件完整性验证](C:/Users/minfei/Documents/ChatGPT/建模/audits/pvalue_version_comparison_20260923/independent_P_BH_and_source_integrity.json)

源码定位：

- [paired_elpd_analysis.R](C:/Users/minfei/Documents/ChatGPT/建模/publication/v3_4_formal_results_20260923/repository/v2/src/paired_elpd_analysis.R)
- [ELPD_CORRECTION_BY_FOLD_zh.md](C:/Users/minfei/Documents/ChatGPT/建模/publication/v3_4_formal_results_20260923/repository/v2/reports/ELPD_CORRECTION_BY_FOLD_zh.md)
- [comparison.R](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/R/comparison.R)
- [cross_validation.R](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/R/cross_validation.R)
- [data_encoding.R](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/R/data_encoding.R)
- [analysis.json](C:/Users/minfei/Documents/ChatGPT/建模/runs/v3_4_formal_20260922204324/v3.4/config/analysis.json)
- [06_留出验证.md](C:/Users/minfei/Documents/ChatGPT/建模/publication/v3_4_formal_results_20260923/repository/v1/docs/06_留出验证.md)
- [postfit_cv.R](C:/Users/minfei/Documents/ChatGPT/建模/publication/v3_4_formal_results_20260923/repository/v1/src/postfit_cv.R)
