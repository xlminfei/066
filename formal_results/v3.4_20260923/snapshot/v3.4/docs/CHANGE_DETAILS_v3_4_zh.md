# v3.4 修改明细、理由及验收

基线为v3.3提交3692f07840807c8abfcac58dd87d1218a68c1149。两处问题在锁定R环境中均已复现；它们是公共输入校验的原有缺口，不是正常默认主流程已经产生错误研究结果的证据。

|位置|修改前的问题|本次修改|修改目的与验收|
|---|---|---|---|
|R/cross_validation.R：validate_fold_tables_v3|只拒绝未知设计名，没有要求当前V3_DESIGNS全部出现；sort(unique(Fold))会丢掉NA；同名设计/路线容易被列表索引遮蔽|设计名必须与当前配置集合一致，不能缺失、无名、NA或重复；路线名也唯一且与binary/joint_bb一致；表必须有唯一列名和Species/Fold列；物种集合正确且每种只一行；Fold为普通integer/double数值向量，逐行有限、整数、1..K，且覆盖全部K折|在任何fit回调和输出之前拒绝坏折表。保留设计顺序/行序可变、integer值的double列、factor物种标签，以及测试明确配置的两折设计。没有重新划分或随机挑选模型表现|
|R/metrics.R：evaluate_evidence joint分支|仅检查点值有限；例如其他字段合法的PredictedPoint=1.2或ObservedPoint=1.2仍能进入MAE/Bias|先要求列名唯一且两点值列存在，再在原有限性检查之后，检查所有joint PredictedPoint和count/exact ObservedPoint是否在闭区间[0,1]；超界明确报错|0和1合法；负值、>1、紧贴边界但已超界的浮点数均拒绝；不clip、不删除记录、不改变计算公式。interval ObservedPoint不被变成点目标，仍允许其NA并排除于点指标|
|R/config.R、config/analysis.json、input/contract.json|版本隔离|身份更新为ratio_analysis_v3_4_weighted_20260922，其他配置保持不变|新旧版本不混用缓存；完整配置去掉version后与基线相同|
|R/reporting.R、R/audit_run.R|新版本报告路径要一致|生成并要求REPORT_v3_4.md，只改版本标题/文件名|实际生成报告测试通过；v3.3固定评价权重的比较说明保留|
|Dockerfile、环境/交付工具、测试入口|独立复现与交付|更新安装路径与版本标签，增加本轮防护/对照/范围检查及runner|R4.6.1/79包锁保持；新Docker构建与环境测试、解析检查均记录|

## 旧版如何被直接复现

before模式加载冻结v3.3模块，而不是人为模拟错误公式。构造12个纯合成物种、完整五折/十折表，再只移除十折、或将一个仍有其他同折物种的Fold置NA。旧验证器接受这两个输入。

joint负例为其他字段合法的count/exact/interval合成证据；改变点值时保持PI覆盖字段在逻辑上一致，避免由无关检查提前报错掩盖范围漏洞。旧版对PredictedPoint=1.2和适用ObservedPoint=1.2仍评分。

入口负例将fit_function换成一个只记数并立即报错的哨兵。旧版缺少十折时触达该哨兵1次；新版本在前置校验处停止，哨兵调用0、输出目录未创建。**哨兵不是采样器，本轮实际采样次数始终0。**

## 具体测试

最终防护套件151项。第一轮148项后，自查追加并复现3个点列合同反例：interval-only缺PredictedPoint、缺ObservedPoint，以及重复点列；它们会让范围判断真空通过或歧义取列，因而属于同一公共评分输入合同的必要补充。最终旧版90项满足期望、61项暴露未拒绝的反例或入口问题；这代表两类缺口的多个组合，不是61个独立模型错误。最终结果以测试收据为准。

合法结果对照：使用原32个合成拟合保存的1472条OOF记录，以及本轮240任务替身编排的2944条OOF记录，对逐折和总体、两路线/四模型/两训练/两评价共640组评分逐字段使用identical()比较，新旧结果完全相同。固定种子生成的默认五折/十折表也完全相同。

进一步自查覆盖：缺设计、无名/重复设计、NA/NaN/Inf/小数/越界/字符/factor折号、缺折、重复或缺失物种、缺路线与重复列名；0/1点值、两评价方式、interval-only集合、非法数据阻止fit回调及有效测试设计可用。没有用错误输入过滤或数值裁剪绕过失败。

完整测试及限制见review/VALIDATION_v3_4.md；所有文件的修改状态与SHA见FILE_CHANGE_INDEX.csv，源码差异见review/SOURCE_DIFF_v3_3_to_v3_4.patch。

## 保持不变的内容

Stan与14个核心R模块、5个运行入口保持原字节。原输入、M1/M2/M3编码、两种训练/评价、Site151排除与Site315保留、固定五/十折、Beta保护、MeanLogScore比较解释、先验和正式4链4000/2000配置均保留。

本轮没有重跑旧32项短链或长链收敛验证，没有重开RDS；它们原有FAILED_DIAGNOSTICS记录保留在旧发布中。正式16全拟合+240CV及真实性能仍未运行/验收。
