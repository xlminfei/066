# v3.4 → v4：逐项修改与理由

基线为仓库提交 4e0fdbb08562f1a8905734b2f0eb831697281388。旧目录和旧结果保留。本次主要是落实新的分析范围，并不是说旧四组合程序或六/十八项 BH 的算术错误。

| 新位置 | 原位置/功能 | 修改与理由 | 对应验证 |
|---|---|---|---|
| settings.R | R/config.R＋config/analysis.json | 合并为唯一设置；固定记录训练/物种评价；保留实际生效的 B_ELPD=2000、其余检验50000 | 配置、128任务和原始P复算 |
| data/ 两张原输入 | v3.4/input | 字节不改，保留0/1、区间及缺失信息 | 六输入SHA与支持数 |
| data/ 四张折表 | 正式结果/results/folds_*.csv | 直接保存已使用的物种划分，移除随机分折生成器 | 完整物种集合、1..K、无重叠及篡改反例 |
| R/data_encoding.R | R/data_encoding.R | 保留核心函数，仅更换设置符号；移走多版本prepared包装 | 8个全数据蓝图、24组规格与Site151排除检查 |
| 01_prepare.R | workflow准备阶段 | 六CSV→验证→冻结字典/编码→128任务清单；准备与拟合分开 | 准备入口成功；没有拟合 |
| R/model_functions.R | fitting、prediction、applicability、ppc、cache部分 | 训练记录权重固定1；合并模型相关函数；保留两路线、三观测模型、均值/区间目标、适用范围及PPC | 24原生模型复算、两次新合成拟合 |
| stan/joint_bb.stan | v3.4同文件 | 原样保留稳定Beta算法、收敛检查和端点质量 | SHA一致；不重复宣称本轮重跑全部旧梯度测试 |
| 02_fit.R | workflow/cross_validation拟合调度 | 删除训练方式循环，保留8full+120CV；逐项诊断、受控缓存及SHA清单 | 128替身任务编排＋实际两路线合成拟合 |
| R/metric_functions.R | metrics、comparison、CV汇总、补充检验函数 | 只保留物种等权；按指标合格集合重算权重；保留折均AUC、Brier、Bias、PI和校准 | 436行旧值对照、边界与抽样顺序检验 |
| 03_evaluate.R | postprocess＋单独P值补充脚本 | AUC/误差检验纳入正常主流程；只保留30个非Null全设计检验 | 30行/10组、完整输出、原始P/CI保持 |
| P_BH3 | 原P_BH/BH6/BH18 | 按路线/指标/设计/训练/评价每组三模型重算；固定n=3，NA不缩家族 | R手算反例＋独立Python30项复算 |
| R/checks.R、R/load.R | 多版本provenance/audit/runner | 保留少量必要身份、范围、诊断、固定文件集、主键和结束检查；取消默认全后验大审计 | 47项最终守卫回归 |
| 04_plot.R、R/plot_functions.R | plotting＋长report | 保留ROC/校准/物种图，加入整合指标与BH3检验图；PPC只留表，不生成长报告 | 7份PDF30页渲染/视觉检查，源表SHA不变 |
| run_all.R | 多阶段旧主入口 | 一个总入口，四个分步入口；可选--output | CLI准备、整条编排、分步守卫 |
| renv.lock、environment/restore.R、Dockerfile | 原依赖和构建 | 软件版本不升级；Docker可选，Ubuntu可直接Rscript | 同一R4.6.1、79包环境验证 |
| 文档 | 原长报告/复现/变更文件 | README、方法、输入输出和Ubuntu分步说明；说明当前未执行新的128项研究拟合 | 链接/文件清单和发布校验 |

## 本轮自查实际修复的防护缺口

第一次实现后的独立审查发现并复现了三处缺口。它们已在最终版修复：

1. 分步恢复仅核对prepared里保存的身份字段，仍会接受被改动的观测或合法但不同的折成员。现在从六张冻结CSV重建并比较相关状态；每次独立阶段入口只检查一次，不在每项指标/拟合里重复重建。
2. 仅看表行数和receipt自报列表不足以确认完成，空列表或有行无内容的表可能通过。现在固定阶段必需文件集，验证完整身份网格，并核对128个预期拟合文件的SHA和大小。
3. 预测表缺数值列时，R的NULL可能让any()检查失效。现在先要求完整且唯一的列，再检查数值和区间。

此外，视觉检查修正指标图右边数值标签的空间，并把BH图标题明确为每个面板三项；数值表没有变化。

## 删除的运行负担

不再有物种平衡训练、记录等权评价、训练方式比较、每折P值表、多份JSON设置、反复生成折表、默认重开全部后验的审计、长自动报告及新物种接口。旧开发测试、失败复现、大模型对象与上传/分卷工具不放进可移动代码包。

这些材料没有从历史仓库删掉；本轮新验证档案在 validation/v4。详细测试结果见该目录 VALIDATION_zh.md。v4主程序不依赖它。

## 交互式逐行入口更新

新增interactive_analysis.R、interactive_support.R和INTERACTIVE_zh.md；每个新代码行均有中文注释。原模型和评价模块不变。逐项理由及新测试见[交互更新记录](https://github.com/xlminfei/066/blob/main/validation/v4_interactive/CHANGE_DETAILS_zh.md)。
