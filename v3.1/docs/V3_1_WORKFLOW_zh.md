# v3.1 比例预测分析：目的、实现和使用边界

本说明对应 `config/analysis.json` 中的 `ratio_analysis_v3_1_weighted_20260920`，描述当前代码和已经核实的测试。历史 `review/implementation_self_check.md` 中的 PASS 不替代本版验收；修订与证据对照见 `docs/REVIEW_MATRIX_zh.md`。代码、短链接口测试、正式研究结果分别验收。

## 1. 实验目的与适用范围

在冻结的物种—位点面板上，用五个位点的不同编码方式预测新物种的比例相关响应，并通过按物种分组的交叉验证比较：

1. 位点联合编码是否优于只含截距的 Null。
2. 记录等权与物种等权训练，对新物种预测表现的影响。
3. 同一预测在两种评价权重下的表现是否一致。

M1/M2/M3 是联合编码模型，比较预测能力，不直接给出单个位点的独立作用或因果效应。当前报告的主要口径为五折、物种等权评价；十折与记录等权评价作为补充。四种组合来自同一批物种，相互相关。

joint 的共同均值 m 及报告分布代表训练资料所覆盖条件下的期望比例，不能自动推广到任意刺激强度、实验条件或取样方式。本设计已约定不新增条件协变量、物种随机效应或进化结构；这是一项范围限定，不是这些因素不存在的证明。

输入为 `input/sites.csv`、`input/observations.csv`，由 `input/contract.json` 固定 SHA-256。当前有365个面板物种、153条观测：105条count、40条exact、8条interval；binary有50个可分类响应物种，joint有51个响应物种。保留同物种全部合格记录，不压缩为一个无误差均值。记录、实验及来源标识继续用于配对和追溯。

## 2. 模型、路线与任务网格

六个位点均保留输入：`Site3, Site20, Site117, Site151, Site196, Site315`。预测矩阵只用Site3/20/117/196/315。Site151用于完整性和训练域提示；Site315保留在M1/M2/M3中，但没有单位点模型。不加入Scheme A。

| 模型 | 实际编码 |
|---|---|
| Null | 只含截距，无位点预测列 |
| M1 | Site3=C、Site20=K、Site117=K、Site196=C为各自参考类别，其余非缺失残基为other；Site315将K/T合并为K_or_T，其余为other；缺失单独编码 |
| M2 | 每个预测位点将C/K/S/T合并为CKST，其余非缺失残基为non_CKST；缺失单独编码 |
| M3 | 每个位点在冻结365物种面板中出现至少4次的残基保留类别，其余为OTHER；缺失为MISSING |

词典只使用位点信息，不使用响应。冻结面板允许包含被留出物种的无标签位点信息，因此这是面向既定目标面板的验证，与完全未知目标种群的验证不同。外部物种沿用词典，不重新定义常见/稀有类别。各训练折另行记录训练类别、残基、组合及行空间。

| 名称 | 定义 |
|---|---|
| binary | 对确定的HIGH/LOW拟合逐记录加权Bernoulli，预测Pr(HIGH) |
| joint_bb | count/exact/interval共享期望比例m，各用自己的观测似然 |
| record_equal训练 | 每条合格训练记录权重1 |
| species_equal训练 | 每个物种的总训练权重相同 |
| record_equal评价 | 对指标可用记录等权评分 |
| species_equal评价 | 在指标可用集合中平衡物种贡献 |

评价表同时保留 `TrainWeighting` 和 `EvalWeighting`。RR/RS/SR/SS表示两训练×两评价。改变评价方式不重新拟合、不改变预测；全面板预测只含TrainWeighting。

正式任务为4模型×2路线×2训练=**16个全数据拟合**；CV为4×2×2×(5+10)=**240个拟合**，合计**256**。同一路线/折数下，各模型及两种训练共用折表；同物种全部记录始终在同一折。binary要求每折同时有两类。两路线响应物种集合不同，各保留相应折表。

当前输入不变时，CV证据应有4,880行、逐折评价480行、整体评价64行、365物种预测5,840行。数量检查必须同时核对模型、路线、训练、评价、折和RecordID，不能只看行数。

## 3. 观测机制、编码与权重

HIGH/LOW保持原约定：count的Events/Total及exact的Exact≥0.5为HIGH；interval的Upper≤0.5为LOW、Lower≥0.5为HIGH；严格跨越0.5的区间不进入binary，但保留于joint。`[0,1]`区间不提供joint信息，不进入该路线的训练权重集合。

joint使用 `m=logistic(alpha+X beta)`，分别估计 `phi_count=exp(log_phi_count)`、`phi_ratio=exp(log_phi_ratio)`。

- **count**：`Events ~ BetaBinomial(Total, phi_count*m, phi_count*(1-m))`，期望比例为m。预测时使用每条记录的Total：模拟Beta概率、模拟Binomial计数、除以Total。
- **exact**：未知分母报告比例位于`(0,1]`。1处点质量为`pi=rho*m`；连续部分权重`1-pi`、Beta均值`mu=m*(1-rho)/(1-rho*m)`、精度phi_ratio。混合均值恰为m。exact=1用点质量，内部值用连续密度；未知分母exact=0不在当前契约内，输入会被拒绝。
- **interval**：对同一报告比例分布计算区间概率；Upper=1包含点质量。不用中点代替区间，不虚构点误差或点覆盖率。

count与exact共享均值，不要求共享方差或端点频率。用连续报告分布为count生成PI是错误的，本版已按类型拆分。

species_equal训练权重为 `w_sr=N_train/(S_train*R_s)`，R_s只计算该路线/折的实际训练记录。它平衡物种总权重，并使全部权重和为N_train；属于明确尺度的带权似然更新，不等于N_train个独立观测信息，也不自动保证频率学覆盖率。复制每条记录会增加总似然贡献，不能用权重自动修复重复录入。该尺度是合理的预先约定，不是唯一正确的贝叶斯校准法。

同物种共享预测概率和权重时，逐记录Bernoulli与相应聚合二项模型的参数相关似然部分相容；采用逐记录形式不是错误。它便于保存观测身份和权重，并不把相关记录变成独立生物学重复。

评价权重从每个指标的完整可用集合单独计算。joint的log score用所有informative记录；MAE/RMSE与点PI覆盖率用count/exact。ELPD是总权重等于记录数时的加权log score总和，MeanLogScore是归一化平均。binary与joint对应不同响应目标，不把两者分数直接当作同一个问题比较。

MISSING始终有独立设计方向，M3的OTHER不与缺失混同；无法映射到蓝图的类别报错。外推分别提示缺失输入/预测位点、训练未见编码类别/残基/组合、固定效应行空间不可估性和Site151训练域问题。先验能生成数值预测，不等于该方向由训练数据识别。
## 4. Point、CrI、PI、OOF和PPC

| 字段 | 含义 |
|---|---|
| Point | binary的Pr(HIGH)或joint的m的后验均值 |
| PosteriorMedian | 同一期望量的后验中位数，另列保存 |
| CrI_lower/upper | 同一期望量后验的2.5%/97.5%分位数，反映参数不确定性 |
| 全面板joint PI | 未指定分母时，未来exact类型报告比例的95%后验预测区间；PredictionTarget明确标注 |
| CV count PI | 在该记录Total下的Beta-binomial预测区间 |
| CV exact PI | one-inflated Beta报告分布预测区间 |
| IntervalOverlap | interval与报告比例PI是否相交，仅为描述，不是点覆盖率 |
| OOF | 将该物种全部记录留出后生成的预测 |

Null或相同编码行由同一参数draw投影。全面板/外部报告PI使用共同随机数减少批次与顺序造成的Monte Carlo差异；这些列用于边际区间，不能当作跨物种相互独立的联合未来样本。记录级模拟器另外对每条记录模拟，用于OOF PI及PPC。

binary评价包括加权AUC、Brier、log score。AUC按HIGH–LOW配对及记录权重计算，并列计半分。正式汇总的AUC/FoldMeanAUC是逐折AUC等权平均；PooledAUC是合并全部OOF记录计算的另一个指标。平均ROC使用完整分段结点，积分等于平均折AUC；不能将分数相同的不同折去重。校准图用固定分箱和评价权重点估计，以物种簇bootstrap给区间，并标记低支持/退化。

模型比较在完整CV design上配对RecordID、物种、折及观测字段，计算模型减Null、species_equal训练减record_equal训练的平均log score差。bootstrap有放回重抽物种，record_equal保留重抽物种的全部记录，species_equal平均物种内记录平均差。该区间是**固定OOF预测**条件下的物种重采样近似，没有重新拟合，也未涵盖模型选择不确定性；它是一种明确范围的实现选择，不是唯一正确的校准方法。少于10物种或退化情况不给近似P值，逐折比较也不给P值。整体P/BH仅作探索性近似。

BH分组为Family×Scope×EvalWeighting×Route×Design；模型-vs-Null组包含两种训练的相关比较。两种训练共享物种和折，不能把比较当作独立重复。

PPC只用实际训练行。observed/replicated在同一记录、同一观测机制、同一评价权重下计算Mean、SD、ZeroFraction、OneFraction。joint分count/exact/all_point检查；interval不插补点值。它是训练内适配检查，不能称为外部验证。观测统计量超出复制统计量95%区间标REVIEW_REQUIRED，需要解释，而不是凭采样正常忽略。

## 5. 代码模块与阶段

| 文件 | 当前职责 |
|---|---|
| config/analysis.json；R/config.R | 网格、先验、采样、种子、bootstrap及固定规则；拒绝不支持的配置 |
| R/bootstrap.R | 统一root定位及模块加载 |
| R/data_encoding.R | 输入/分类/未分类计数、冻结词典、蓝图、行空间可估性 |
| R/weights.R | 分开计算训练/评价权重 |
| R/fitting.R；stan/joint_bb.stan | 实际模型规格和代码、拟合、严格参数诊断 |
| R/cache_io.R | 输入/记录/权重/蓝图/代码/采样/环境身份；实际拟合载荷和重算诊断 |
| R/prediction.R | 投影、Point/CrI、分类型PI、记录分数、外部预测及字段验证 |
| R/metrics.R | AUC/ROC、Brier、MAE/RMSE、log score、PI指标、校准 |
| R/cross_validation.R | 物种折与调度、统一证据schema、逐折/总体汇总、证据键完整性 |
| R/comparison.R | 配对物种bootstrap、状态、探索性BH和ROC表 |
| R/ppc.R | 同记录/类型/权重的训练PPC及图件 |
| R/plotting.R | 平均/逐折ROC、校准图、分模型物种预测页及图源表 |
| R/provenance.R | 分析指纹及派生表/图/报告的哈希清单 |
| R/reporting.R | 基于实际结果的报告、可移植参数包及完整性校验 |
| R/audit_run.R | 重建256规格、核对实际拟合和诊断、重新评分、检查输出及来源 |
| R/workflow.R；src/v3_pipeline.R | 阶段编排、配置生效、失败状态和最终门槛 |
| src/postprocess_results.R；src/plot_species_predictions.R；src/write_reports.R；src/audit_run.R | 独立后处理、绘图、报告、审计入口 |
| tests/ | 合同/边界、编排替身、真实合成集成、外推、Stan/R似然一致性 |

以下命令从本版本目录执行。Docker构建上下文也应是包含Dockerfile、renv.lock、R和src的版本目录；依赖恢复遵循版本随附的环境说明。

```bash
Rscript tests/parse_all.R --root .
Rscript tests/run_tests.R --root .
Rscript src/v3_pipeline.R --stage prepare --root .
Rscript tests/check_prepared.R --root .
Rscript tests/test_orchestration.R --root .
Rscript tests/test_integration.R --root .
Rscript tests/check_smoke_scores.R --root .
Rscript tests/check_external.R --root .
```

orchestration测试以采样/评分替身检查240 CV任务，不运行正式MCMC。integration测试在独立合成数据目录运行Null/M1×两路线×两训练×两折的16个真实短链拟合，标记INTEGRATION_TEST_ONLY。允许短链诊断警告只为检查接口，不能被正式审计当作研究结果。

正式入口如下；列出命令不表示已执行：

```bash
Rscript src/v3_pipeline.R --stage all --root .
```

all顺序为prepare→16全数据拟合→training PPC→240 CV及后处理→全面板预测→图件/报告/派生清单→正式审计。smoke可单独调用，不计入正式256任务。也可分阶段执行fit、ppc、cv、predict、report、audit。

有效设置来自config/analysis.json。CLI拒绝另设iter/warmup/chains/cores/seed/config/force以避免配置和实际运行不一致。当前正式设置是4链、4,000 iter、2,000 warmup、adapt_delta=.99、max_treedepth=12；核心采样参数及lp诊断须全部有限，R-hat<1.01、bulk/tail ESS≥400、零divergence、零树深命中、每链E-BFMI>.3。

正式诊断失败阻止继续。不能把保存的Status改为PASS绕过门槛：加载及最终审计会核对真实代码、数据、抽样控制、载荷并重算诊断。只有all全部必需步骤和审计成功才写COMPLETE；PPC需复核时写COMPLETE_WITH_REVIEW_FLAGS。重跑/异常更新状态，防止沿用旧COMPLETE。硬中断可能留下RUNNING/INCOMPLETE，必须核对实际进程及产物后恢复。

全拟合通过后可执行 `external --new-data <六位点CSV> --out <输出CSV>` 或 `export --out <模型包RDS>`。可移植包保存词典、蓝图、参数、身份和诊断，不需重新拟合；外部输入仍须Species及全部六个位点。代码不负责从完整蛋白自动推断位点编号。

## 6. 本轮证据状态

已核对输入、模型、观测机制及两轮统计修订，独立数值结果见复核矩阵。现存orchestration_test.json=PASS，日志终行对应240替身CV任务及4,880/480/64行，证明编排及其失败边界。deterministic_tests.log记录合同/科学边界通过；代码变更后仍应重新生成发布前验证记录，不能仅依赖旧日志存在。

真实16-fit合成集成已经恢复完成，integration_status.json=PASS_INTERFACE_ONLY；产生216条OOF记录、32行逐折指标、16行总体汇总。16个短链拟合均未满足正式ESS/R-hat门槛（无divergence或树深命中），只支持接口完成。外部Null/M1与缺失类别测试、600项Stan/R似然数值对照、坏缓存与状态/产物篡改负例均通过。另有2个不等记录数的合成二分类拟合通过严格诊断，并与独立数值积分的后验均值一致；这些也不是正式研究结果。详见review/RELEASE_VALIDATION_zh.md。

**正式16+240=256个研究拟合尚未启动，没有正式模型比较、预测性能或科学结论。**