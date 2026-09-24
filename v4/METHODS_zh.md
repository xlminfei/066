# 模型、评价和 P 值

## 模型与输入处理

训练仅采用记录等权：每条合格训练记录权重为 1。binary 是逐记录 Bernoulli，分类规则与此前一致；joint_bb 联合使用 count、exact、interval 三种观测。

- count：已知真实分母，使用 beta-binomial。0/Total 和 Total/Total 都合法。
- exact：未知分母的精确比例，使用在 1 处含概率质量的 Beta 报告模型。支持 (0,1]，没有凭空增加 exact=0 的质量。
- interval：对相同报告分布在给定上下界上的概率积分。区间包含 1 时保留 1 处质量；[0,1] 不提供训练信息。
- 未知分母的 exact 不伪造 Total；区间不替换成中点；同物种全部合格记录保留。

五个预测位点为 Site3、Site20、Site117、Site196、Site315。Site151 仅保留输入与提示。M1 对 Site3/20/117/196 分别区分 C/K/K/C 验证类别与 other，对 Site315 区分 K或T 与 other；M2 区分 CKST 与 non_CKST；M3 依冻结365物种面板的频数，将出现至少4次的残基分别编码，其余归 OTHER。MISSING 有独立类别；参考类别及列顺序沿用原实现。

Null 只有截距，因此同一折内所有物种预测相同；不同折训练数据不同，跨折预测可以不同。M1/M2/M3 的未见类别、未见组合、不可估计方向和位点缺失保留明确提示，不因为产生了有限预测值就称为有充分训练支持。

所有模型沿用原先验：截距 normal(0,1.5)，系数 normal(0,0.5)，rho 的 Beta(1,1)，两个 log(phi) 的 normal(log(10),1)。正式采样为4链、4000迭代、2000预热、adapt_delta=0.99、max_treedepth=12。

## 分组交叉验证和指标

四张物种折表直接读取，不在运行中重新抽签。一个物种的全部记录在同一测试折；测试物种响应的训练权重为0。五折为主要评价，十折为敏感性评价，每套各一次，没有十次随机重复。

每个评价集合内，记录的物种权重为 N/(S×R_s)，其中 R_s 是该集合内该物种的记录数。物种总权重相同，全部权重和为 N。MAE、RMSE、Bias 和点值 PI 指标只使用 count/exact 子集，并在该子集重新计算权重。

- ELPD 是逐记录留出 log predictive density 的物种加权总和，越高越好；MeanLogScore=ELPD/N。联合路线中离散质量、密度和区间概率来自不同观测类型，绝对数值须在相同数据与定义下比较。
- 分类 AUC 使用每折物种加权 AUC，再对所有折等权平均；并列分数计半分。PooledAUC 单独保留为描述值，不用于本次检验，也不替代主要折均 AUC。
- Brier 是 HIGH 概率的加权平方误差，越低越好；校准图展示预测概率和观测频率，并保留低支持/退化区间提示。
- MAE 是平均绝对比例误差；RMSE 是加权平方误差平均后再开方。二者越低越好，乘100后为百分点。
- Bias=加权平均(预测−观测)，正值表示平均高估。
- PI coverage 与宽度联合阅读。count 的 PI 对应其观测 Total 下的未来 count 比例；exact 对应未来报告比例。区间数据不被当作点值验证 PI coverage。
- 全365物种表的 Point 是后验均值，PosteriorMedian 单列；CrI 表达均值不确定性，joint_bb 的全面板 PI 对应未来 exact 报告。训练内 PPC 单独保存，不能充当留出准确度。

## 30 项检验

| 路线 | Metric | Reference | 差值方向 |
|---|---|---|---|
| binary | AUC | 0.5 | 正值表明区分较好 |
| binary | MeanLogScore | 同训练 Null | 正值表明预测分布评分改善 |
| joint_bb | MeanLogScore | 同训练 Null | 正值表明评分改善 |
| joint_bb | MAE | 同训练 Null | 负值表明点误差减少 |
| joint_bb | RMSE | 同训练 Null | 负值表明点误差减少 |

每项在五折与十折各产生 M1/M2/M3 三行，共30行。ELPD_Difference 只对 MeanLogScore 差值乘 N，不另增一个检验。

MeanLogScore 使用2000次全设计的物种配对 bootstrap，保持原 SEED=20260920 及抽样顺序。记录等权训练之外没有其他训练分支。

AUC 使用50000次整物种重抽样，固定原 Fold × 物种类别组成（HIGH-only、LOW-only、mixed）各层的物种数，每次重新计算各折 AUC 并平均。MAE/RMSE 使用50000次对有效点值物种的配对重抽样，所有候选模型和 Null 共用物种抽样次数；每个物种被重复抽到时作为独立副本计算。SEED_OTHER=20260923，各设计/折偏移见源码和结果 SeedRule。

SE 为 bootstrap 统计量分布的标准差，不再除以 sqrt(B)。双侧 P=2×Phi(−|Difference/SE|)。95%区间使用 bootstrap 百分位数，不是正态 P 的严格反演；区间未进行多重校正。非常小的 P 是正态尾部外推，不是有限次重抽样直接测得同等罕见概率。

## 每组三项 BH 与解释范围

分组键为 Route、Metric、Design、TrainWeighting、EvalWeighting；每组恰好 M1、M2、M3 各一次。P_approx 为原始近似 P，P_BH3 为 p.adjust(..., method="BH", n=3)。即使有 NA，n 仍为3；Null 不参与。校正不跨路线、指标或CV设计。

原 v3.4 的六项/十八项校正不是算术错误；它们属于不同的分析范围。v4 重新声明三项家族并重算，保留此前资料的原值。本版本是在开发阶段比较后确定，不能把这次选择描述成从未比较过其他方案。

推断条件于固定已拟合的 OOF 预测、原折表及AUC类别组成，没有纳入完整训练重叠、重新拟合、分折/模型选择不确定性。十折每折物种少，部分折只有一个带LOW记录的物种，支持度表保留此限制。P<0.05不是误差满足应用需求或机制成立的充分条件，仍需同时阅读效应量、区间、PPC和适用范围。
