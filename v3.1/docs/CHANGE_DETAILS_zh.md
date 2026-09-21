# v3 → v3.1：逐文件修改理由、前后差异与验证证据

本文件补充模块级 [REVIEW_MATRIX_zh.md](REVIEW_MATRIX_zh.md)，回答每项实质修改的四个问题：**在哪里改、原来有什么问题、为什么这样改、修改后有什么证据**。它不把“新增功能”“合理实现选择”都写成旧版数学错误，也不以代码存在代替实际运行。

## 1. 对照基线与结论边界

- **原版基线**：Git 提交 `c693e278a098be4e1bb8b027613cae9fe78edf6c` 的 `v3/`。当前仓库保留的 `v3/` 与该提交的版本一致，可直接逐文件对照。
- **中间修订稿**：原工作目录中的 `review/pre_v31_audit_snapshot/`。完整证据附件 `v3.1-complete-evidence.zip` 使用路径 `working-v3/review/pre_v31_audit_snapshot/` 保存它。下文把只存在于此稿的错误明确写为“中间稿”，避免错误归因给 Git 原版。
- **当前实现**：本文件同版本目录的 `R/`、`src/`、`tests/`、`scripts/`。源码链接使用仓库相对路径和函数起始行；后续行号变化时以函数名定位。
- **首次 v3.1 发布**：提交 `4ca55f8`；本次补充保留原 `v3.1` 标签，完整证据版本使用 `v3.1-complete`。本文件的发布说明不代替 GitHub 上传完成收据。
- **研究意图**：在冻结365物种位点面板中，以五个位点的联合编码预测新物种的比例相关响应或 `Pr(HIGH)`，比较 Null/M1/M2/M3、两种训练权重及两种评价权重。Site151保留输入、仅用于适用范围提示；Site315仍在M1/M2/M3中。四种组合不是四套独立训练。
- **正式研究运行**：16个全数据拟合和240个物种分组CV拟合仍未执行。下面的“通过”只能按对应层级解释，不能转换成正式收敛、模型优于Null或外部泛化结论。

修改类型：**修复**表示已定位的实现/统计口径错误；**补齐**表示原流程缺少必要功能或验证；**实现选择**表示在明示假设下采用的一种方案；**保留并澄清**表示原思路并非错误。

## 2. 可复现测试索引

以下命令从 `v3.1/` 执行；Docker构建、挂载与环境命令见 [reproduction_ubuntu.md](reproduction_ubuntu.md) 和 [scripts/ENVIRONMENT.md](../scripts/ENVIRONMENT.md)。依赖次序不能交换：T05生成的实际合成拟合供T06、T07、T08、T11读取；T08也生成T11所需的两个参考拟合。RDS带有平台相关编译内容，换环境不能假定原缓存可直接恢复，应按脚本重新生成。

| ID | 命令/核查方式 | 保存的结果与可支持结论 |
|---|---|---|
| T01 | `Rscript tests/parse_all.R --root .` | [初版解析](../review/verified_parse_all.log)、[迁移后解析](../review/package_parse_all.log)、[本轮解析](../review/followup_parse_all.log)：37个R文件解析通过。只证明语法/模块可加载，不证明每条运行分支正确。 |
| T02 | `Rscript tests/run_tests.R --root .` | [初版52项断言](../review/verified_run_tests.log)、[迁移后回归](../review/package_run_tests.log)、[本轮回归](../review/followup_run_tests.log)通过。包含合同、反例、模拟与聚合检查；“模拟器存在”这类断言本身不是分布正确性的证据，须结合T05/T06及相应数值检查。 |
| T03 | `Rscript src/v3_pipeline.R --stage preflight --root .`，再 `Rscript tests/check_prepared.R --root .` | [预检](../review/preflight_v3.json)、[迁移后准备检查](../review/package_check_prepared.log)：365面板物种、153记录、50 binary/51 joint响应物种，16+240=256个计划任务。没有执行正式拟合。 |
| T04 | `Rscript tests/test_orchestration.R --root .` | [日志](../review/orchestration_run.log)、[收据](../review/orchestration_test.json)：**采样/评分替身**完成240个CV任务身份，4,880条OOF、480逐折指标、64总体指标；含缺记录、旧route名、缺AUC、身份失效和失败状态负例。不能证明240次真实MCMC完成。 |
| T05 | `Rscript tests/test_integration.R --root .` | [采样及中间失败日志](../review/integration_verified.log)、[最终验收日志](../review/integration_pass.log)、[收据](../review/integration/integration_status.json)、[逐拟合诊断](../review/integration/fit_diagnostics.csv)：Null/M1×两路线×两训练×两折=16次真实合成拟合；216条OOF、32逐折、16总体指标；每折确实留出3个物种；状态 `PASS_INTERFACE_ONLY`。16个短链均未达到正式诊断门槛。 |
| T06 | `Rscript tests/check_smoke_scores.R --root .` | [日志](../review/verified_check_smoke_scores.log)、[数值收据](../review/integration/stan_r_likelihood_agreement.json)：20个抽样×30条合成记录=600项Stan/R似然对照，最大绝对误差约 `1.065814e-14`。该文件名沿用smoke，但当前实际读取T05的合成joint M1拟合。不等于所有极端参数/所有观测边界均已枚举。 |
| T07 | `Rscript tests/check_external.R --root .`；T05内还验证单条/批量/倒序 | [日志](../review/verified_check_external.log)、[外部测试表](../review/integration/external_prediction_test.csv)：真实Null/M1合成后验、未见MISSING、批量/单条/倒序的Point与PI一致。未覆盖正式M2/M3全网格外部预测。 |
| T08 | `Rscript tests/test_weighted_posterior.R --root .` | [日志](../review/weighted_posterior_verified.log)、[独立积分对照](../review/weighted_posterior/quadrature_comparison.csv)：20条LOW和2条HIGH来自两个物种；2个binary Null拟合均通过严格诊断；记录等权积分均值0.131609/MCMC0.132741，物种等权0.5/0.502278；最大误差0.002278。 |
| T09 | `Rscript tests/test_artifact_guards.R --root .` | [日志](../review/verified_test_artifact_guards.log)：交换实际fit、错key、坏RDS、伪造诊断、RDS往返、不合法配置、同长度错误任务表、旧状态、修改产物等负例按预期处理。测试会读T05真实拟合。 |
| T10 | `docker build --progress=plain -t ratio-analysis-v3-1:local .`；容器中 `Rscript scripts/test_environment.R` | [构建/环境日志](../review/environment_build.log)：R4.6.1、79个锁定包、必需依赖闭包和命名空间加载通过，错误R版本/缺BH负例通过，临时空库恢复abind通过。构建成功不等于任何研究模型收敛。 |
| T11 | `Rscript tests/save_validation_snapshots.R --root .` | [日志](../review/validation_snapshots.log)、[数值后验快照](../review/validation_snapshots.rds)、[原fit清单](../review/compiled_fit_inventory.csv)：18个合成拟合的参数、蓝图、数据、诊断及joint原始log_lik可查。快照不是可恢复正式拟合的模型缓存。完整附件另保留原始fit文件。 |
| T12 | `Rscript tests/test_visual_report.R --root .` | [本轮日志](../review/followup_test_visual_report.log)、[新收据](../review/visual_fixture_distinct/visual_status.json)、[图源](../review/visual_fixture_distinct/figures/species_prediction_plot_source.csv)：5,840条主键、全部Point/CrI/PI端点和标签在打乱行序后仍一一对应，4份各9页PDF；Null恒定，M1/M2/M3各有365个人工不同值。**纯绘图夹具，不是模型拟合结果。** |

前次 [REVIEW_MATRIX_zh.md](REVIEW_MATRIX_zh.md) 还记录了临时容器内的120,000 draws理论矩、独立簇重采样、400个SVD行空间对照、手算PPC和150组×5折ROC检查。这些是附加复核记录；其中没有独立脚本/原始回显文件的项目，不以一段说明冒充可独立重放的测试收据。本文件的自动化通过声明优先依赖T01—T12现存脚本及结果。

## 3. 输入、编码、权重与配置

| ID/类型 | 修改位置 | 修改前的问题与修改理由 | 修改后的实现与证据 |
|---|---|---|---|
| C01 保留并澄清 | [config/analysis.json](../config/analysis.json)、[R/config.R](../R/config.R#L1)、[Stan模型](../stan/joint_bb.stan) | 两训练×两评价、逐记录加权Bernoulli、joint共同均值及原始Stan训练/评分分离，并非应全部推翻的错误。评价再拟合会把16+240任务错误翻倍。 | 保持4模型/2路线/2训练；每份OOF重复评价而不重复拟合；保留 `target += train_weight[i] * record_log_lik(...)`，输出 `log_lik[i]`不乘训练权重。Stan文件相对基线**没有改写**。T03/T04数量与身份核查、T06似然对照；正式全网格未运行。 |
| C02 补齐 | [R/config.R:apply_analysis_config/validate_sampling_v3](../R/config.R#L91)、[src/v3_pipeline.R](../src/v3_pipeline.R#L5) | 原版配置、全局常量和CLI参数分散，容易把“配置文件里写了”误认为“已实际用于拟合”。 | 正式采样、先验、种子和bootstrap数从配置加载；固定模型/路线/位点/折数合同拒绝越界改动。CLI拒绝另设iter/warmup/chains/cores/seed/config/force，避免覆盖语义不清。T02拒绝增入Site151、改成四折；T09错误warmup配置使实际入口失败。 |
| C03 修复/重构 | [R/bootstrap.R](../R/bootstrap.R#L1)、[所有src入口](../src/) | 旧入口/测试使用当前目录或相对目录拼接，同一版本从其他cwd运行容易加载错树或找不到Stan。 | `--root`→`V3_ROOT`→脚本所在版本目录定位；验证 `R/config.R`存在；共同模块按显式顺序加载。T01/T02/T03在发行目录迁移后通过，日志为package_*；这是已测迁移路径，不是任意路径字符组合保证。 |
| C04 补齐 | [R/data_encoding.R:validate_sites_panel/validate_input_data](../R/data_encoding.R#L7)、[prepare_state](../R/data_encoding.R#L253) | 原版外部位点输入检查不完整，非法残基、空/重复物种、字符串空格或含Exact的interval可能流入编码。验证没有把规范化后的数据返回给后续步骤。 | 统一物种/标识trim、六位点与残基允许集验证；interval必须留空Exact；返回 `list(observations=..., sites=...)`并用于准备状态。HIGH/LOW阈值和exact=0拒绝规则未改。T02包含分类边界、非法残基、空物种、缺失类别；T03固定输入通过。并非所有输入拒绝分支都有独立反例。 |
| C05 修复 | [R/data_encoding.R:build_binary_counts](../R/data_encoding.R#L102)；原 [v3同函数](../../v3/R/data_encoding.R#L86) | `as.integer(obs$High==1)`对不可分类记录产生NA；`aggregate(. ~ Species, ...)`可先删掉含NA的整条记录，导致UnclassifiedCount/RecordCount低报。已有High又 `cbind` 也可能产生重名。 | 显式赋值High；High/Low指示量用 `!is.na(High) & ...`，不可分类记录贡献0/0/1/1。T02的一条count+一条跨阈值interval反例应得到Unclassified=1、RecordCount=2。 |
| C06 修复 | [R/data_encoding.R:make_design_blueprint](../R/data_encoding.R#L177)、[design_from_blueprint](../R/data_encoding.R#L233) | 原 `lev <- sort(unique(vals))`只预留面板已有水平；新MISSING/OTHER可能生成全零行，与参考类别混同。 | M1/M2预留各自参考、非参考、MISSING方向；M3单独保留OTHER与MISSING；任何不能由蓝图表示的编码类别明确拒绝。T02预留MISSING及外部独立方向检查；T05/T07真实M1未见缺失类别接口通过。 |
| C07 数值稳健性/验证选择 | [R/data_encoding.R:row_in_span](../R/data_encoding.R#L171) | 比较 `rank(X)`与 `rank(rbind(X,x))`的数学原理本来正确；本轮对退化矩阵的数值实现进行交叉检查，不能在没有复现具体误判时断言旧QR原理错误。“能按先验生成数值”不能等同于训练数据识别。 | 比较 `qr(t(train_x))$rank`与 `qr(t(rbind(train_x,row_x)))$rank`，并保持可估性警告。T02低秩反例通过；前次矩阵记录400例独立SVD对照。转置不是改变数学定义，而是本实现的数值处理选择。 |
| C08 修复 | [R/config.R:blueprint_key](../R/config.R#L66)、[R/data_encoding.R:prepare_state](../R/data_encoding.R#L253)、[R/workflow.R:make_fold_tables_v3](../R/workflow.R#L8)、[R/cross_validation.R:validate_fold_tables_v3](../R/cross_validation.R#L30)、[R/applicability.R:assess_applicability](../R/applicability.R#L17) | 原折表 `list(binary=b5,joint=j5)`与 `V3_ROUTES=c("binary","joint_bb")`不匹配，`folds[["joint_bb"]]`得到NULL；原缓存也有joint与joint_bb蓝图键混用。 | 折表、blueprint、拟合、预测及警告全部通过受控route命名；检查每路线物种集合、重复物种和折ID。每CV拟合/警告使用实际训练物种蓝图。T04注入旧joint名应失败；T05两路线真实留出通过。独立警告字段是基线已有正确设计，保留而不是宣称全部本轮新建。 |
| C09 保留并澄清 | [R/weights.R](../R/weights.R#L6)、[R/fitting.R:binary_training_data/joint_training_data](../R/fitting.R#L26) | `N/(S R_s)`不是公式错误；错误是把权重总和N解释成N个独立观测信息，或期待复制数据后后验不变。 | 保持公式，仅按当前路线/折合格记录求R_s；新增WeightAlgorithm身份；评价在每个指标可用集合重算权重。T02物种总权重、总和、复制反例通过；T08实际后验与独立积分相符。权重尺度仍是预设选择，不保证自动区间校准。 |

## 4. 拟合规格、诊断和缓存

| ID/类型 | 修改位置 | 修改前的问题与修改理由 | 修改后的实现与证据 |
|---|---|---|---|
| C10 修复/重构 | [R/fitting.R:fit_spec_v3/fit_from_spec_v3](../R/fitting.R#L76)、[R/cache_io.R:fit_identity](../R/cache_io.R#L1) | 原binary代码身份为固定字符串 `sha256_object("brms_bernoulli_v3")`；模型公式或实现变化不一定使其失效。中间稿的公式/先验签名仍未核实实际fit。 | 先构建训练蓝图、数据、公式、先验及实际 `make_stancode`输出，再生成请求身份；记录训练行/物种、数据/输入/蓝图/权重与算法、代码、先验、采样控制、seed、R和包版本。评价权重不进入拟合身份。T04改变输入/蓝图/adapt_delta使身份变；反转评价顺序不变。T05/T08真实规格核验。 |
| C11 修复 | [R/cache_io.R:validate_bundle_for_use/cache_is_valid](../R/cache_io.R#L27) | 原只对元数据key、request、路线/模型/训练标签做比较；实际fit缺失、损坏或被调换时，壳信息可能仍显得正确。 | 核对对象类、保存数据/代码/蓝图哈希、训练物种、版本/网格、请求与载荷指纹；坏RDS返回缓存无效。T05缺失fit/错误代码负例，T09坏RDS/错key/调换实际fit负例通过。 |
| C12 修复 | [R/cache_io.R:validate_fitted_bundle_v3](../R/cache_io.R#L75)、[R/workflow.R:load_full_bundles_v3](../R/workflow.R#L44) | 即使bundle自洽，也不能仅凭外层 `diagnostics$Status="PASS"`信任真实对象；真实链数/seed/iter/warmup/control和模型代码可能不符。 | 重建当前spec，比较实际Stan代码、链数与采样设置；brms比较实际使用的High/TrainWeight/设计列；重新计算诊断。brms会移除未入公式的ID，所以ID由外层数据/请求核对；不要求实际brms对象保留不存在的列。joint保存数据与请求核对，未声称从stanfit恢复了一份独立原始数据槽。T05/T09伪造PASS仍被拒绝；T08严格诊断通过。 |
| C13 修复 | [R/cache_io.R:fit_payload_hash_v3](../R/cache_io.R#L96)、[validate_fitted_bundle_v3](../R/cache_io.R#L75) | 真实集成揭示rstan代码的 `model_name2`属性、编译环境/指针等可导致“相同实际程序”在RDS往返后误拒绝；对整个原生对象粗暴序列化不能作为稳定的数值身份。 | 实际代码按字符内容/trim比较；载荷摘要取参数数组、采样器数值、链控制、代码和brms实际数据等稳定内容。既保留篡改检查又避免属性误判。T09明确记录RDS往返指纹保持、调换实际fit拒绝。此摘要是完整性校验，不是防恶意重签名机制。 |
| C14 修复 | [R/fitting.R:diagnostic_metrics_pass/diagnose_draws_v3](../R/fitting.R#L1) | Git原版把确定性派生输出也混入R-hat/ESS，可能因常量输出产生NA；中间稿为解决它，改成删掉全部NA的参数行，反而可能放过真实采样参数诊断缺失。 | 明确只诊断采样参数及lp，检查draws和所有R-hat/ESS均有限；门槛R-hat<1.01、bulk/tail ESS≥400、零divergence、零树深命中、E-BFMI>.3。确定性预测/似然另查。T02 `(rhat,ESS)=(1,800)/(NA,NA)`反例拒绝；T05诚实保留16项短链警告；T08两项严格PASS。 |
| C15 修复/清理 | [R/fitting.R:joint_training_data](../R/fitting.R#L47)、[R/prediction.R:extract_parameters_v3](../R/prediction.R#L6) | 原Null用一列全0设计代替零列，产生无必要beta参数；改成真实K=0后，rstan提取零长度beta可能返回NULL，中间投影代码会在检查零列之前构造非法matrix。 | Null保留K=0，beta显式归一化为 `matrix(numeric(), nrow=n_draws, ncol=0L)`；有预测列时按准确维度恢复beta。T02零列投影，T05两路线真实Null拟合/预测，T07批量Null通过。 |
| C16 实现选择/可观察性补齐 | [R/fitting.R:fit_from_spec_v3](../R/fitting.R#L94) | 重复编译消耗大，原 `refresh=0`使长时间无输出难以区分计算与停滞。 | 按实际代码哈希复用编译模型/brms模板，仍对每个训练数据、权重和seed重新采样；写FIT_START/FIT_END并 `refresh=50`。T05日志中有实际采样与终态；T08复用程序后仍产生与独立积分相符的新后验。不把编译复用当作复用上一组后验。 |

## 5. 预测、评分、交叉验证与比较

| ID/类型 | 修改位置 | 修改前的问题与修改理由 | 修改后的实现与证据 |
|---|---|---|---|
| C17 修复 | [R/prediction.R:null_projection_draws/project_parameters_v3](../R/prediction.R#L16)；原 [joint_projection_draws](../../v3/R/prediction.R#L22) | 原Null `rep(plogis(alpha), each=n_species)`后按列填matrix，混淆draw与species维度，单条和批量投影不等价。 | 改为 `rep(..., times=n_species)`；非Null统一 `plogis(sweep(beta %*% t(X),1,alpha,"+"))`，按蓝图列序。T02已知(.1,.8)draw矩阵、T05/T07真实单条/批量/倒序一致。真正Null在同一次拟合下各物种均值相同是模型定义。 |
| C18 修复/口径统一 | [R/prediction.R:posterior_quantiles/summarize_prediction_draws](../R/prediction.R#L1) | 原全面板 `Point=q[2,]`是中位数，CV用 `colMeans`；同字段代表不同量，偏斜后验会不一致；单列apply也可能降维。 | `Point=colMeans(draws)`，中位数另列 `PosteriorMedian`；分位数显式保持矩阵维度并拒绝非有限draw。T02的(.1,.2,.9)不对称后验反例通过；T05/T07使用统一投影路径。 |
| C19 实现选择/接口修复 | [R/prediction.R:external_prediction_table](../R/prediction.R#L69)、[report_quantile_v3/joint_predictive_draws](../R/prediction.R#L29) | 原全面板从m读结果、外部另写投影和随机模拟，容易分叉；PI随机数消耗随外部批次或排序变化，妨碍同记录对照。 | 面板与外部统一由参数和冻结蓝图投影；exact报告PI用同一draw级uniform做分位变换，使重复/重排物种边际区间一致；正式外推需已接受诊断，测试显式允许短链警告。T05/T07同一行Point/PI批次不变。共同随机数用于边际PI稳定性，不能解释成跨物种独立未来样本。 |
| C20 修复（中间稿）/补齐 | [R/prediction.R:joint_record_predictive_draws/joint_record_scores](../R/prediction.R#L42) | Git原版没有记录级PI；中间稿给所有类型调用连续报告分布，count记录的离散支持/Total/phi_count被忽略，影响count覆盖率解释。 | count先模拟 `p~Beta(phi_count*m,phi_count*(1-m))`，再 `y~Binomial(Total,p)/Total`；exact/interval沿报告混合分布。记录 `PIObservationModel`；count/exact算点覆盖，interval仅记录区间相交，不插补中点。T02分母2/20离散支持、共同均值、端点质量；T05真实接口，T06原始似然对照。正式覆盖率尚无。 |
| C21 修复/补齐 | [R/prediction.R:validate_prediction_table_v3](../R/prediction.R#L60)、[R/metrics.R:evaluate_evidence](../R/metrics.R#L79) | 旧 `is.finite(Point) & (...)`只检查有限值范围，NA/Inf反而可能未被拒绝；中间稿也可能在PI缺失时默默减小覆盖率评价集合。 | 主键唯一，Point/CrI与joint PI必须有限且范围/上下界正确；记录PI宽度必须等于上下界之差，点覆盖标记必须与观测重算结果一致；输出PICoverage/MeanPIWidth/PIRecords。T02含PI指标与非有限分数回归；T05实际PI接口。部分输入拒绝分支只有源码核对，未逐项注入所有可能异常。 |
| C22 修复 | [R/metrics.R:log_mean_exp/weighted_mean/assert_score_column](../R/metrics.R#L1) | 原 `valid <- is.finite(...)`筛掉评分失败记录，指标表面成功却改变测试集和物种权重；AUC也静默丢掉异常行。 | logdraw允许负无穷参与log均值，但拒绝NA/NaN/+Inf；记录级最终非有限log score带RecordID报错；AUC真值必须0/1、预测与权重有效；普通指标默认不删异常。T02 -Inf记录拒绝、NA log均值拒绝、分数标签.2拒绝。 |
| C23 修复 | [R/prediction.R:binary_record_scores/joint_record_scores](../R/prediction.R#L91)、[R/cross_validation.R:run_cv_v3](../R/cross_validation.R#L111) | 中间稿joint新增PI字段而binary无同名列，最终跨路线 `rbind`列数不一；原逐折 `cbind(...Route..., evaluate_evidence(...))`可带重复Route列。 | 两路线证据统一schema，不适用PI字段显式NA；逐折指标先赋身份字段再按白名单输出，PI列不会丢失。T04完整双路线240任务合并、T05真实合成216条跨路线合并通过。 |
| C24 修复 | [R/cross_validation.R:summarize_cv_metrics_v3](../R/cross_validation.R#L75) | 原总体汇总只把Design补回 `evaluate_evidence`，丢失Model/TrainWeighting；相同行数无法知道指标归属。原 `na.rm=TRUE`也可能隐去某折AUC缺失。 | 明确保留Design/Route/Model/TrainWeighting/EvalWeighting复合主键；AUC是逐折等权均值，PooledAUC单列；任何binary折AUC不有限即失败。T02身份回归；T04缺折AUC负例及480/64行；T05真实32/16行。 |
| C25 补齐 | [R/cross_validation.R:validate_cv_evidence_v3](../R/cross_validation.R#L192)、[R/workflow.R:task_plan_v3](../R/workflow.R#L15) | 只数任务/结果行数不能识别删一行又补一行、错物种、错折或重复记录。 | 按设计/路线/模型/训练逐项重建应有RecordID集合，核对物种与折；计划保存训练数据/权重/配置哈希和seed；证据保存FitKey与RunPurpose。T04删记录、旧route负例；T05真实留出与身份检查；正式审计拒绝 `INTEGRATION_TEST_ONLY`。 |
| C26 修复+实现选择 | [R/comparison.R:pair_log_score_rows/cluster_bootstrap_difference](../R/comparison.R#L1)、[compare_evidence_models/compare_training_methods](../R/comparison.R#L35) | 原按单折记录差值做 `sd(d)/sqrt(length(d))`，将同物种记录当作独立不确定性单位；只有物种等权比较输出，未形成完整design主比较。 | RecordID严格一一配对并检查物种/折/观测字段；完整design上有放回重抽物种。物种等权平均物种内平均差，记录等权保留被抽物种的全部记录。两种EvalWeighting均输出，by-fold作为附表。T02簇反例/错物种/错折、T04编排；固定OOF bootstrap不含重新拟合或模型选择，属于明确范围的近似。 |
| C27 修复/解释收紧 | [R/comparison.R:cluster_bootstrap_difference/add_comparison_adjustment](../R/comparison.R#L17) | 原SE=0且差非0时给 `P=0`，退化样本被解释成极强证据；原BH只按Family分组，混入不同口径。 | 退化bootstrap或少物种不给近似P，by-fold不给P；状态标记有限支持/退化/固定OOF近似；BH按Family×Scope×EvalWeighting×Route×Design分组。T02退化与两物种反例通过。近似P/BH仅探索性，不能说已获得无条件有效的显著性。 |
| C28 修复 | [R/metrics.R:calibration_bins](../R/metrics.R#L125) | 原 `Bin=as.character(z$Bin[ii])`传入多元素，data.frame把一个箱复制多行；中间箱内重算物种权重还可能改变全评价集合定义的点估计目标。 | 每箱一个字符串/一行；点估计使用完整评价集固定权重；簇bootstrap重抽时带着原记录权重；标注INSUFFICIENT_SUPPORT/LIMITED_SPECIES/DEGENERATE_INTERVAL。T02单箱多记录只输出一行、区间字段回归。覆盖率校准不由该测试自动保证。 |

## 6. PPC、图件、报告、导出、审计与运行状态

| ID/类型 | 修改位置 | 修改前的问题与修改理由 | 修改后的实现与证据 |
|---|---|---|---|
| C29 补齐并修复中间稿 | [R/ppc.R](../R/ppc.R#L1)、[R/workflow.R:run_stage_v3](../R/workflow.R#L75) | Git原版没有完整PPC阶段；中间稿将全部点记录的观测平均与“每物种一个模拟报告”的平均相比，记录集合、权重、观测机制不一致；只有interval的物种也可能仅进入模拟侧。 | 从 `bundle$request$train_rows`取同一训练行；binary模拟Bernoulli，joint使用记录类型模拟；按count/exact/all_point和两评价权重对Mean/SD/ZeroFraction/OneFraction做相同统计。interval不插补点。T05保存[training_ppc_test.csv](../review/integration/training_ppc_test.csv)验证真实拟合接口；前次手算核查另见矩阵。正式PPC未生成，训练PPC不称作独立验证。 |
| C30 修复/增强 | [R/plotting.R:mean_roc_summary_v3/plot_roc_base](../R/plotting.R#L1)、[R/metrics.R:roc_coordinates](../R/metrics.R#L47) | 原图只有逐折曲线而没有与报告AUC相应的平均曲线；中间稿 `mean(unique(AUC))`把AUC相同的不同折去重；随机权重累计会给端点1±浮点误差造成插值NA。 | 每折取唯一AUC后保留折重数；用完整分段结点构建平均曲线；规范化近0/1横轴、强制理论终点；图例写平均CV AUC与折数。T02五折(.5,.5,.5,.5,1)得到.6而非.75，1-2e-16端点反例通过；前次随机ROC复核见矩阵。 |
| C31 增强 | [R/plotting.R:plot_calibration_base/plot_species_predictions_base](../R/plotting.R#L35) | 原校准模型均同色/同点形，物种图把多个模型叠画且物种标签拥挤；缺乏点/区间/警告可追溯表。 | 校准按模型区分颜色与形状；物种每页42种、4个模型分栏，按Species匹配；显示Point/CrI/joint PI及适用性提示，导出Page/YPosition和全部图源数值。旧布局夹具只查标签/页序；本轮T12增加不同值、乱序和全部数值端点核验。 |
| C32 修复解释与测试缺口（本轮） | [tests/test_visual_report.R](../tests/test_visual_report.R#L5)、[R/plotting.R](../R/plotting.R#L60) | 旧测试明写 `Point=.3+.07*match(Model,V3_MODELS)`，因此同模型下365个物种全部相同：Null=.37、M1=.44、M2=.51、M3=.58；这只是绘图夹具。旧图小字Fixture提示不够醒目，且常数值无法暴露数值错配。 | 保留旧 [visual_fixture](../review/visual_fixture/)作为历史；新增 [visual_fixture_distinct](../review/visual_fixture_distinct/)：Null按训练方式恒定，M1/M2/M3各365个不同人工值；乱序后逐主键比Point及全部区间端点；任何FixtureOnly图均加醒目 `SYNTHETIC TEST DATA - NOT RESEARCH RESULTS`大标题。T12收据通过。新图仍没有用正式拟合，绝不把“画得有差异”当作修复了真实模型性能。 |
| C33 补齐/修复 | [R/reporting.R:write_results_report_v3](../R/reporting.R#L6)、[src/write_reports.R](../src/write_reports.R#L1) | 原报告仅写预测/CV行数及固定说明；即使没有实际数值也可输出REPORT_PASS，不能满足结果复核要求。 | 必需CV汇总、模型比较、训练比较和PPC文件存在才写报告；嵌入实际表和权重/OOF/PI/PPC解释。解析T01通过，源代码已核对；**完整正式报告生成未运行**。旧空报告不作为v3.1计算结果。 |
| C34 补齐 | [R/reporting.R:export_model_package_v3/predict_model_package_v3](../R/reporting.R#L23)、[R/workflow.R](../R/workflow.R#L110) | 缺少不依赖原生编译对象的可移植预测包；简单复制stanfit RDS不能保证跨环境可用。 | 仅完整16全拟合网格并通过诊断时导出；保存配置、冻结词典、蓝图、参数draw、请求与诊断及摘要；提供所需R文件；加载核对摘要/版本并沿用相同外部投影。T01解析；T07覆盖共用投影接口。**正式16-fit导出及跨机器端到端加载未运行**，不能把外部Null/M1通过当作全导出通过。 |
| C35 修复/补齐 | [R/audit_run.R](../R/audit_run.R#L1)、[src/audit_run.R](../src/audit_run.R#L1) | 原审计仅“256个唯一任务”和“fit.rds都存在”，无拟合时可给PLAN_PASS；空壳/陈旧对象/错误结果仍可能通过存在性检查。 | 重建当前规范任务网格，逐任务重建spec、实际拟合核验和重算诊断；检查OOF身份/FitKey/RunPurpose；重新计算逐折与总体分数；核对全面板预测完整主键、必需输出/报告、来源收据。T09同长度错任务表拒绝；T04/T05覆盖组成接口。**正式256-fit审计成功路径未运行**。 |
| C36 修复/补齐 | [R/provenance.R](../R/provenance.R#L1) | 原产物缺少绑定当前输入/配置/源码的来源封印；中间收据把命名字符向量直接写JSON，可能变成无文件名数组，`for(n in names(...))`空循环导致漏检。 | 源码/输入/配置组成AnalysisFingerprint；CV/predict/PPC阶段记录每个路径的哈希；写入使用 `files=as.list(setNames(...))`，读取拒绝空/无名清单；图表报告另有派生总清单。T09先验证有效收据，再改同一CSV必须拒绝；JSON收据检查已实测。 |
| C37 修复 | [R/workflow.R:run_with_status_v3](../R/workflow.R#L117)、[R/audit_run.R:audit_plan_v3](../R/audit_run.R#L53) | 原成功状态可能在重跑失败后保留，旧COMPLETE/audit PASS被误读为当前完成。 | 阶段开始写RUNNING；正式主阶段重置INCOMPLETE；异常写FAILED并重抛；仅all完成必需步骤及审计后才能COMPLETE，PPC异常为COMPLETE_WITH_REVIEW_FLAGS。T04/T09实际失败入口及坏任务网格覆盖旧状态；当前[final_v3_status.json](../review/final_v3_status.json)仍为INCOMPLETE。硬中断可能留下RUNNING，仍须核对进程。 |
| C38 重构/补齐 | [R/workflow.R:postprocess_v3/render_outputs_v3/run_stage_v3](../R/workflow.R#L53)、[src/v3_pipeline.R](../src/v3_pipeline.R)、[src/postprocess_results.R](../src/postprocess_results.R)、[src/plot_species_predictions.R](../src/plot_species_predictions.R) | 原大主脚本和独立后处理重复计算逻辑；后处理仅写species_equal比较，新增功能易与主流程脱节。 | 抽为共同workflow；all顺序prepare→全拟合→PPC→CV及后处理→全面板预测→图/报告/封印→审计；独立入口调用同一模块，两评价和design/by-fold都输出。T01语法、T04编排替身、T05代表性真实CV；**all完整正式链路未运行**。 |

## 7. 环境、输入字节、测试文件和交付物

| ID/类型 | 文件与变化 | 原因与验收 |
|---|---|---|
| C39 复现补齐 | [Dockerfile](../Dockerfile)、[renv.lock](../renv.lock)、[scripts/restore_environment.R](../scripts/restore_environment.R)、[scripts/test_environment.R](../scripts/test_environment.R)、[scripts/ENVIRONMENT.md](../scripts/ENVIRONMENT.md) | 基线使用可变镜像tag和少数包版本断言，不能证明必需依赖已完整恢复；中间稿镜像摘要曾不完整。现固定完整64位镜像digest，锁定79个必需R依赖闭包，固定renv bootstrap版本及源码SHA-256，缺/错包显式恢复与复验。T10正例、错误R/缺BH反例和空库恢复通过。apt附加系统包未做历史快照，不能承诺按位一致镜像。 |
| C40 字节保存修复，数据值未改 | [input/observations.csv](../input/observations.csv)、[input/sites.csv](../input/sites.csv)、[input/contract.json](../input/contract.json)、[仓库.gitattributes](../../.gitattributes) | `git show c693e278...:v3/input/observations.csv`实测15,576字节、0个CRLF；当前v3.1为15,730字节、154个CRLF。仅统一CRLF→LF后逐字符完全一致，数据单元格没有变。旧contract已记录CRLF文件SHA `3c886f7f2c11012463296b350a931543542b4e1c0d128ad3c408fda9ae824d79`；基线Git blob为 `5d05803955852e02095f50816033f2a768f8e3ee3da3e71f477a8ba78a948c59`。本版 `-text`保留冻结字节，contract只更新版本身份，不能写成“Git文件字节完全没变”。T03当前合同哈希通过。 |
| C41 产物重新生成 | [runs/](../runs/)、[results/折表](../results/)、[provenance/](../provenance/)、[review/](../review/) | `binary_counts.csv`因C05修复重算；panel_encoded/prepared状态/256任务计划随统一编码与身份重建；输出两路线5/10折四张折表。MANIFEST、runtime_spec和哈希收据随包更新。它们是准备/测试/复现材料，不是正式拟合结果。T03/T04/T11及各JSON收据说明用途。 |
| C42 测试覆盖补齐 | [tests/test_contracts.R](../tests/test_contracts.R)、[test_scientific_contracts.R](../tests/test_scientific_contracts.R)、[test_release_regressions.R](../tests/test_release_regressions.R)、[run_tests.R](../tests/run_tests.R)、[parse_all.R](../tests/parse_all.R)、[check_prepared.R](../tests/check_prepared.R) | 原有限自检没有覆盖已定位边界。现三份确定性脚本合计52项输出断言；runner隔离测试局部环境并统一加载当前配置。解析包括R/src/tests三个目录。T01/T02/T03通过。52不是穷尽边界证明，代码注释也不能证明全部测试先于实现编写。 |
| C43 真实接口与审计证据补齐 | [tests/test_orchestration.R](../tests/test_orchestration.R)、[test_integration.R](../tests/test_integration.R)、[check_smoke_scores.R](../tests/check_smoke_scores.R)、[check_external.R](../tests/check_external.R)、[test_weighted_posterior.R](../tests/test_weighted_posterior.R)、[test_artifact_guards.R](../tests/test_artifact_guards.R)、[save_validation_snapshots.R](../tests/save_validation_snapshots.R) | 将“替身全网格”“真实短链接口”“独立积分”“原始似然”“破坏性负例”“数值快照”分开保存，避免一次smoke PASS替代所有验收。T04—T09/T11结果与限制如索引。旧print_versions.R只是版本输出工具，未做实质算法改写。 |
| C44 说明与完整归档补齐 | [V3_1_WORKFLOW_zh.md](V3_1_WORKFLOW_zh.md)、[REVIEW_MATRIX_zh.md](REVIEW_MATRIX_zh.md)、本文件、[reproduction_ubuntu.md](reproduction_ubuntu.md)、[版本README](../README.md)、[RELEASE_VALIDATION_zh.md](../review/RELEASE_VALIDATION_zh.md) | 原说明仅模块/问题层级，不足以逐函数追溯；原发布有意省略原生fit缓存，不能满足本轮“所有现存说明、中间文件和测试结果”要求。本文件增加44项前后理由/证据；完整附件以 `working-v3/`保存原工作目录全部现存文件、以 `published-v3.1/`保存当前发行目录全部现存文件。旧失败日志、旧快照、旧均一图和本轮新图分开保留；不能删旧失败或用新PASS覆盖其历史。远端完整性以归档清单、大小、SHA-256和上传读回为准。 |

## 8. 对“所有修改都标出来了吗”的准确回答

本文件覆盖相对指定Git基线的所有生产R模块、5个src入口、配置、Docker/环境、测试入口、生成物和说明的实质变化。模块逐行空格/换行、序列化文件字节和完整代码增删应以Git差异及完整补丁核对，不把这些机械变化逐行冒充独立科学修改。中间稿特有的count PI、PPC、诊断放行、AUC折去重与真实接口问题已分别标明，避免说成原审查建议本来全对。

仍须明确保留的边界：

1. 正式16+240拟合没有运行，因此不存在正式365物种估计图或正式优劣结果。三张预览所展示的常数是旧人工绘图数据，不是所有物种真实比例相同的结论。
2. 真实接口覆盖Null/M1及两种路线/训练；M2/M3通过编码/合同/编排检查，尚未完成正式MCMC全网格验证。
3. 正式PPC、完整计算报告、正式便携模型包导出和256拟合成功审计没有执行；其源码与组件证据不能替代这些验收。
4. 中间失败日志与短链诊断警告全部仍有效地描述相应尝试；当前终态收据只能解释其自身数据、代码和层级。
5. 完整附件只承诺归档时仍存在的本项目文件。已结束容器或R临时目录中从未持久化的对象不能事后凭空恢复；存在的文件用清单追溯，不以“可重新生成”代替本轮要求保存的现存原件。
## 9. 本轮归档与传输实现

C45：scripts/build_complete_archive.ps1 逐项枚举两个指定根目录的全部现存文件，先计算SHA-256，再生成ZIP并逐项读回校验，拒绝源文件在打包期间变化。它新增归档能力，不改变模型。C46：scripts/upload_release_asset.ps1 使用现有Git凭据在进程内完成指定仓库的Release附件上传；不把凭据写入文件。上传后必须读回服务器的字节数和SHA-256，两者一致才保存成功收据。完整性终态见 provenance/complete_upload_receipt.json；未形成收据前不声称上传通过。

C47：scripts/restore_complete_evidence.py 为分片恢复工具，固定完整ZIP与分片清单摘要，逐片校验后才合并，不覆盖校验不符的已有文件。本地24片重组得到386,483,393字节，SHA-256与原ZIP相同；不改变任何研究模型或数值。上传及验证日志见 provenance/complete_delivery_receipts。
