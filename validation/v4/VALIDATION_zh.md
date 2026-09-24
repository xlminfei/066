# v4 验证结果与证据边界

版本目标：记录等权训练×物种等权评价，binary/joint_bb，Null/M1/M2/M3，冻结五折/十折，各一次；三项BH。所有测试使用原已验证镜像 sha256:c67aade078ec1510b1b036a1a34c6ad0aad66534296b9e6587cd9f283093ca58（R4.6.1）。

**代码和本轮分层验证通过。没有执行新的128项研究数据拟合。** 本目录包含旧后验复算、真实合成拟合和替身编排三个不同层次，不能合并计数为正式拟合已完成。

| 验证 | 实际结果 | 证据 |
|---|---|---|
| 固定数据与计划 | 六CSV身份和51/50/48支持集合正确，8full+120CV | prepare_check；run_plan |
| 核心契约与原生复算 | 122项检查通过；24组新旧模型规格一致；24个既有原生对象复算 | core_pass/core_status.json、model_spec_equivalence.csv、posterior_replay_checks.csv |
| 全面板与留出预测 | 8个full对象复算2920行；16个CV对象覆盖两路线、四模型、两种设计的第1折；最大数值误差5.33e-15 | core_pass |
| 真实新拟合 | 2个合成M1模型（binary/joint_bb），4链/2000迭代/1000预热，原诊断门槛；均PASS | synthetic_fits下原生RDS、诊断、预测、PPC、完整日志 |
| 合成诊断数值 | binary Rhat1.00257，最小bulk ESS1784.61；joint Rhat1.00395，最小bulk ESS1902.87；两者均零发散/零深度命中，E-BFMI>0.90 | synthetic_diagnostics.csv |
| 指标和P重算 | 436行对照通过；120折指标、16汇总、30检验；P最大误差5.44e-15，CI1.55e-15 | metrics_final，保留30组draw与8组multiplicity |
| 抽样算法 | AUC/误差multiplicity与旧补充完全一致；18组draw数值一致；4组log-score种子索引一致 | metrics_final/test_status.json |
| BH3独立复核 | 30项、10组；独立Python最大P误差1.50e-15、BH3误差1.11e-15 | independent_P_BH3.json |
| 边界与恢复防护 | 最终源码47/47通过；防止prepared、折表、字段、receipt和完成网格异常 | guard_final |
| 完整调度 | 实际走过128项任务但拟合由明确替身提供；2440OOF、2920面板、120/16/30表与7图完整 | orchestration，README_TEST_ONLY.txt |
| 图件 | 7PDF共30页全部渲染；修正两种图的标签/标题；图源未变化 | plots_final、visual_final |
| 环境 | 79个锁定包版本及完整依赖闭包匹配，无环境升级 | environment_check.log |
| 原结果保护 | 31个原正式派生输出SHA保持不变；旧版本目录不改 | independent_P_BH3.json、发布检查 |

最终防护与绘图检查对应分析源码身份：
75ac77db4f6fa772a7c6a4038b5b70ba93b8b8b103add1b38fe71f11319f2b7a

## 保留的失败/中间尝试

core_check、core_final、core_verified 以及 intermediate 中保留了开发验收过程的中间结果，不能用它们替代最终 core_pass：

- 初次跨版本缓存对照适配器使用了排序后的请求物种，而旧蓝图保存的是实际传入顺序；随后修正为原顺序。
- JSON删除后，先验常数1在R对象中有integer/double容器差异，数值严格相等。对照适配器在先确认all.equal(tolerance=0)后才规范存储类型；这是测试适配，不是生产缓存的跨版本导入功能。
- 核心测试最后写出receipt有一处括号语法错误，导致此前检查完成后脚本未正常退出；已修正并完整重跑。
- 合成测试最初误把跨0.5区间送入binary评分，生产函数正确拒绝；测试按生产合格记录选择规则修正，已拟合的binary缓存仍经身份验证复用，未另跑一次采样。
- 视觉首轮数值标签靠近右边界，最终版扩大横向边距。渲染器报告Symbol/ArialUnicode显示字体不可用，但全部实际ASCII标签/数值正常显示，已逐页检查并保存警告原文。

最终判定只依据 core_pass、metrics_final、guard_final、synthetic_fits、orchestration和plots_final的PASS及实际退出码。未删除或放宽诊断/统计检查以获得通过。

## 可支持和不可支持的结论

这些证据支持v4在所测数据和接口上保持原模型定义、预测及原始推断算法，并落实新三项BH方案。它们不证明新Ubuntu服务器已跑完研究拟合，也不把条件近似P值变成严格全流程确证。128项新正式运行仍须由使用者按v4四步入口完成并通过诊断。

公开代码包只含v4。验证代码、日志、合成原生拟合、保存的bootstrap对象、图件、失败尝试和本说明单独归档，以保证发表用代码简单可移动。
