# 图注（v2，中文）

## F01_ROC_AUC_HighLow

High/Low 路线的物种分组留出 ROC 曲线。每个面板对应五折或十折；曲线把相同留出设计下的记录级预测合并用于可视化，图例中的 AUC 是各测试折 AUC 的不加权平均。灰色虚线表示随机排序。AUC 仅用于 High/Low 路线，不用于定量比率路线。

## F02_HighLow_calibration

High/Low 概率校准图。横轴为留出记录的平均预测 High 概率，纵轴为相应预测秩分箱中的实际 High 比例；误差线为二项比例 Wilson 95% 区间。它用于检查概率是否偏高或偏低，不等同于 ROC/AUC。

## F03_ELPD_delta_Null

逐条留出记录 ELPD 相对 Null 的差值。零线表示 Null；正值表示模型的留出预测密度总和更高。图中没有加入 paired SE 或显著性标记，因此不能把点的高低直接解释为统计学显著性。

## F04_quantitative_predicted_observed

定量路线 count/exact 点记录的留出预测与观测对照。虚线为相等线；颜色区分 count 和 exact。interval 记录不被替换成中点，但仍参与 ELPD 评分，因此不出现在这个点值图中。

## F05A_full_panel_High_heatmap

365 个物种的 High 后验概率热图，物种按 M1 的 High 概率排序。M1、M2、M3 的列用于比较固定五位点编码下的预测差异；Site151 保留在输入审计中但不进入任何主模型预测变量。

## F05B_full_panel_ratio_heatmap

365 个物种的联合 beta-binomial expected exact-report ratio 热图。颜色表示点估计，不代表单个未来实验的全部不确定性；对应 95% 后验可信区间和预测区间保存在全物种预测 CSV 中。

## F06_prediction_interval_widths

全物种预测区间宽度。蓝色为 expected quantity 的 95% 后验可信区间宽度，橙色为一个未来 exact 报告的 95% 后验预测区间宽度。预测区间通常更宽，因为它同时包含参数不确定性和未来报告本身的波动。

## F07_training_PPC_checks

训练资料上的后验预测检查。点为观测摘要，误差线为后验预测重复的 95% 范围；橙色表示该摘要落在范围外，需要人工复核。interval coverage 没有单个观测摘要，因此没有画入该点范围图，而在 CSV 中标为描述性检查。

## F06_species_binary_corrected、F06_species_joint_bb_corrected、F06_species_schemeA_tobit_corrected

三组分页图参照第一版 F06 的布局，按 42 个物种一页展示 365 个面板物种和 5 个模型。High/Low 分区画 High 概率和 95% 后验可信区间；联合定量和 Scheme A 分区分别画 expected exact-report ratio、95% 后验可信区间和 95% 后验预测区间。红色边框或空心点表示外推或缺失状态，但仍保留数值。

## F08_paired_ELPD_comparisons

按物种聚合留出 log predictive score 的配对比较。蓝色为相对 Null，橙色为相对 Site315；点为 ELPD 差值，线为物种聚类 paired SE 的 95% 正态近似区间。图中不使用 AUC，也不把近似 p 值解释成显著优越。

所有图均由冻结输入、正式拟合和逐条留出评分表生成；原始 CSV、转换规则、随机种子和模型诊断保留在 v2 目录。
