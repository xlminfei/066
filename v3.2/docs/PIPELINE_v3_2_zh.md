# v3.2 当前流程与各代码的职责

本版接收已经从冻结参考比对提取的六位点表 input/sites.csv，及原始逐记录 input/observations.csv。本轮没有重新比对365条全蛋白序列，也没有开发新增全蛋白输入接口。Site151保留用于适用范围提示；模型使用Site3、Site20、Site117、Site196、Site315。正式研究运行尚未开始。

## 模型与资料

|模型|五个位点的编码|
|---|---|
|Null|仅截距，同一拟合的物种均值相同|
|M1|Site3 C、Site20 K、Site117 K、Site196 C为参考状态；Site315 K/T为参考组；各自与other比较，MISSING单独列|
|M2|每个位点按C/K/S/T与non_CKST分组，MISSING单独列|
|M3|冻结面板中出现次数至少4的氨基酸保留独立类别，其余归OTHER，MISSING单独列；后续不重新学习字典|

binary路线把可判定的count/exact/interval记录转为HIGH/LOW，拟合逐记录加权Bernoulli。count/exact的比例>=0.5为HIGH；interval上界<=0.5为LOW，下界>=0.5为HIGH，严格跨过阈值不进入binary。joint_bb路线按原始资料类型联合建模：count使用实际Events/Total的Beta-binomial；exact使用未知分母报告比例的one-inflated Beta；interval使用同一报告分布在原区间的概率，包括上界1时的端点原子。不能给exact虚造分母，不能把interval中点当观测值。

训练record_equal的每条权重为1；species_equal为N_train/(S_train*R_s)，每折只用训练记录重算。训练后同一套OOF预测复用两种评价权重，因此四组合RR/RS/SR/SS对应两套拟合、四组相关评价，不是四个独立实验。评价权重在各指标有效记录集合重新计算。

## 正式运行的阶段与产物

|阶段|主要代码|职责与关键产物|
|---|---|---|
|配置、输入、预检|R/bootstrap.R、config.R、data_encoding.R；config/analysis.json|解析当前版本root、应用固定配置、校验记录、冻结编码字典和设计蓝图；核对365面板及153原记录|
|权重与适用范围|R/weights.R、applicability.R|训练/评价权重分别计算并检查；保留缺失、未见类别/组合、不可估计方向、Site151训练外状态提示|
|全数据拟合|R/fitting.R；stan/joint_bb.stan|两路线×四模型×两训练=16个正式拟合；缓存身份包含输入/权重/蓝图/源码/采样配置；M1/M2模板身份另含设计列|
|物种分组CV|R/workflow.R、cross_validation.R|每个物种所有记录同折；固定五折、十折各一次，共240个正式拟合，不额外随机重复十次|
|预测与原始评分|R/prediction.R|输出后验均值、可信/预测区间及未加训练权重的逐记录log预测密度；全面板预测不因评价方式重复|
|指标与比较|R/metrics.R、comparison.R、cross_validation.R|保留TrainWeighting/EvalWeighting和模型身份；binary给逐折ROC/AUC、等折均值AUC和另列PooledAUC、Brier；joint给ELPD/MeanLogScore、MAE/RMSE/Bias、PI覆盖和宽度；已存在的物种配对条件bootstrap比较与探索性P/BH保持原定义|
|训练资料检查|R/ppc.R|按相同记录子集/观察模型和评价权重比较观测与后验复制统计；PPC不代替独立CV|
|新增定量图|R/quantitative_diagnostics.R|从joint OOF的count/exact点记录生成源表、Bias汇总与预测—观测散点图；图有y=x、权重面积、记录/物种数，interval不插补|
|后处理、绘图、报告|R/workflow.R、plotting.R、reporting.R；src下入口|组装派生表、图件及reports/REPORT_v3_2.md；缺少必需产物时报错|
|审计|R/prediction_audit.R、audit_run.R|重新验证拟合载荷和诊断，从实际后验与当前输入独立复算所有OOF/全面板值，再检查指标、48项模型比较、32项训练比较及新增定量两表|

## 指标读法与适用记录

- ELPD是权重和归一到记录数后的log预测密度总和；MeanLogScore是相应平均。比较不同权重口径时，应明确总和尺度。它们不是概率百分比。
- MAE/RMSE/Bias只使用有点值的count/exact记录。Bias=加权平均(预测−观测)：正为高估、负为低估；正负抵消会使Bias小，所以须与MAE/RMSE同时阅读。
- LogScoreSpeciesUsed/LogScoreRecordsUsed说明log分数集合；PointSpeciesUsed/PointRecords说明点误差集合；PISpeciesUsed/PIRecords说明点PI覆盖/宽度集合。现有研究表静态核对为joint 51物种、点与PI 48物种、binary50物种，不能只写一列51代表全部指标。
- CrI反映均值的不确定性，PI反映未来观测的变动；joint全面板PI的目标为未来exact型报告，CV的count PI使用该记录实际分母。
- 既有P/BH是固定OOF上的条件、探索性比较，未包含重新拟合或模型选择的不确定性。本轮按用户范围不追加7.2。

## 本轮实际验收与正式研究的边界

只读输入合同/记录数、确定性反例、Beta函数与梯度检查、240任务合成替身编排、32真实合成CV拟合和后验复算均属于测试。测试目录是review/；正式根runs/results没有被创建为完成状态。

合成数据每物种4至15记录，专门覆盖不等权、只有interval的物种和M2/M3未见类别。这不是为展示高预测能力而生成的数据；其预测可能集中在0.5附近，Null同一折内为同一常数是模型定义所致。所有测试图标明SYNTHETIC TEST DATA，不可作为真实365物种预测或科学结论。

精确测试数量、误差与短链诊断见review/VALIDATION_v3_2.md。256项正式研究拟合的状态记录在provenance/formal_status.json；以后是否运行由用户另行决定。
