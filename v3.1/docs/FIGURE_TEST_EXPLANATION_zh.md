# 为什么之前的预览图每个物种都是同一个值

之前显示的是绘图布局测试，不是365个物种的实际模型预测。生成器没有读取拟合模型，使用固定表达式：

~~~r
pred$Point <- .3 + .07 * match(pred$Model, V3_MODELS)
~~~

因此每个模型的所有物种都被赋同一个演示值：

|模型|旧布局夹具点值|
|---|---:|
|Null|0.37|
|M1|0.44|
|M2|0.51|
|M3|0.58|

它们既不是实测比例，也不是后验均值。旧图中的区间同样是用于画线的占位数值，不能解释为研究模型的CrI/PI。旧图仍保存在 review/visual_fixture，作为原始测试历史；当时只在部分图的小字中注明fixture，正文解释也不够明确，确实容易造成误解。

## 真正模型的区别

Null只含截距，不使用物种位点；同一套训练拟合对不同物种给出相同的期望预测是合理的。两种训练权重可产生不同的Null拟合。M1/M2/M3使用位点编码，不要求所有物种预测相同；编码相同的物种也可能得到相同预测。因此，不能为了让图看起来有差异而改变真实模型输出。

正式研究数据的16个全拟合和240个CV拟合尚未执行。现在没有可用来评价365物种真实预测是否相同的正式结果。

## 本次补充了什么

- 新测试输出到 review/visual_fixture_distinct，不覆盖旧布局测试。
- 所有新测试图顶端以大字标明 SYNTHETIC TEST DATA - NOT RESEARCH RESULTS；底部说明点和区间都是dummy数值，不再把占位线段称为实际后验区间。
- Null仍保留同一训练方式内的常数。M1/M2/M3为每个物种构造不同的确定性假数据，只用于检验绘图。
- 测试打乱输入记录顺序，再按Species、Route、Model、TrainWeighting四字段逐行核对Point、上下区间和警告；5,840行必须全部一致。这样能检出标签和值错位，而原先相同的数值无法有效检出这种错误。
- 当前绘图代码对没有FixtureOnly标记的正式预测保持原有图形含义；没有改变统计模型、先验、训练权重或正式预测算法。

测试命令：

~~~bash
Rscript tests/test_visual_report.R --root .
~~~

终态证据见 review/followup_test_visual_report.log 和 review/visual_fixture_distinct/visual_status.json。52项既有确定性回归仍通过，见 review/followup_run_tests.log。本次无需重拟合18个合成模型，因为改动仅涉及测试夹具和图示标识。
