import csv,json,hashlib,math,sys
from pathlib import Path
from collections import defaultdict
root,out=map(Path,sys.argv[1:3])
def read(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def j(n):return json.loads((out/n).read_text(encoding='utf-8'))
rows=read(out/'supplementary_metric_tests.csv');support=read(out/'auc_fold_species_support.csv');plan=j('ANALYSIS_PLAN.json')
assert j('independent_validation.json')['status']==j('bootstrap_verification.json')['status']=='PASS'
cn={'record_equal':'记录等权','species_equal':'物种等权','fivefold':'五折','tenfold':'十折'}
def fmt(v):
 if v in ('','NA',None):return '—'
 x=float(v)
 return f'{x:.3e}' if 0<x<.0001 else f'{x:.5f}'
def link(label,p):return f'[{label}]({p.as_posix()})'
def tables(design,ew):
 a=[r for r in rows if r['Design']==design and r['EvalWeighting']==ew and r['Metric']=='AUC' and r['Model']!='Null']
 b=[r for r in rows if r['Design']==design and r['EvalWeighting']==ew and r['Metric'] in ['MAE','RMSE']]
 t='| 模型 | 训练方式 | AUC | 95%条件bootstrap区间 | 原始近似P | 单指标BH（6项） | 三指标BH（18项） |\n|---|---|---:|---|---:|---:|---:|\n'
 for r in a:t+=f"| {r['Model']} | {cn[r['TrainWeighting']]} | {float(r['Estimate']):.4f} | [{float(r['CI95_lower'])+.5:.4f}, {float(r['CI95_upper'])+.5:.4f}] | {fmt(r['P_approx'])} | {fmt(r['P_BH_endpoint'])} | {fmt(r['P_BH_three_metrics'])} |\n"
 t+='\n| 指标 | 模型 | 训练方式 | 模型值（百分点） | Null值（百分点） | 模型−Null（百分点） | 95%差值区间（百分点） | 原始近似P | 单指标BH（6项） | 三指标BH（18项） |\n|---|---|---|---:|---:|---:|---|---:|---:|---:|\n'
 for r in b:t+=f"| {r['Metric']} | {r['Model']} | {cn[r['TrainWeighting']]} | {100*float(r['Estimate']):.3f} | {100*float(r['ReferenceEstimate']):.3f} | {100*float(r['Difference']):+.3f} | [{100*float(r['CI95_lower']):+.3f}, {100*float(r['CI95_upper']):+.3f}] | {fmt(r['P_approx'])} | {fmt(r['P_BH_endpoint'])} | {fmt(r['P_BH_three_metrics'])} |\n"
 return t
blocks=[]
for design in ['fivefold','tenfold']:
 for ew in ['species_equal','record_equal']:blocks.append('## '+cn[design]+' · '+cn[ew]+'评价\n\n'+tables(design,ew))
counts=[]
for design in ['fivefold','tenfold']:
 for ew in ['species_equal','record_equal']:
  for metric in ['AUC','MAE','RMSE']:
   rr=[r for r in rows if r['Design']==design and r['EvalWeighting']==ew and r['Metric']==metric and r['MultiplicityEligible']=='TRUE']
   counts.append(dict(Design=design,EvalWeighting=ew,Metric=metric,Tests=len(rr),RawPBelow05=sum(float(r['P_approx'])<.05 for r in rr),BH6Below05=sum(float(r['P_BH_endpoint'])<.05 for r in rr),BH18Below05=sum(float(r['P_BH_three_metrics'])<.05 for r in rr)))
with (out/'significance_counts.csv').open('w',encoding='utf-8-sig',newline='') as f:w=csv.DictWriter(f,fieldnames=list(counts[0]));w.writeheader();w.writerows(counts)
limits=[r for r in support if int(r['HighBearingSpecies'])<2 or int(r['LowBearingSpecies'])<2]
assert len(limits)==4 and all(r['Design']=='tenfold' for r in limits)
report='''# v3.4：AUC对0.5、MAE和RMSE对Null的补充检验

这是查看ELPD结果后新增的**探索性补充分析**。此前v3.4表中的P值针对MeanLogScore差异；在相同记录与评价权重下，也等价于对应ELPD差异的检验。本文件新增三个不同终点的检验，不能把它们改称原先ELPD检验的结果。

## 本次计算了什么

- AUC：H0为原有“各折AUC等权平均”=0.5，双侧近似检验；没有改成PooledAUC。32行包括8个Null结构性机会水平结果，24项非Null检验。
- MAE：M1/M2/M3与**同训练方式、同折表、同评价权重的Null**作配对比较，H0为MAE_model−MAE_Null=0，共24项。
- RMSE：同样与对应Null作配对比较，H0为RMSE_model−RMSE_Null=0，共24项。每次重抽样均重新计算sqrt(加权平均平方误差)，没有把RMSE误做成绝对误差平均。
- 共80行，其中72项非结构性检验。五折/十折、两种训练和两种评价全部保留。
- 本次没有新增MAE/RMSE两种训练方式之间的检验，也没有做M1、M2、M3所有两两比较；这不是表中P值的含义。

## 计算方法与校正规则

计算前先保存ANALYSIS_PLAN.json，固定50,000次重抽样、种子基数20260923、双侧检验及校正规则。

AUC在原有每一折内，以物种为整组，按HIGH-only、LOW-only、mixed三种物种记录组成分层重抽样，保留每层物种数。一个物种的全部记录一起抽取，重复抽中的物种按独立的bootstrap副本计数。每次重新计算各折的加权AUC并等权平均，不丢弃无效折，不把记录当独立物种。分层是为了保留两类支持，推断因此额外条件于原折表及类别组成。

MAE/RMSE使用count/exact的145条记录、48个物种。以物种配对重抽样，模型和Null共用同一份物种抽样索引；物种等权在有效点值子集内定义。interval不替换成中点。记录等权按抽到的全部记录平均，物种等权按抽到的物种副本等权平均。

原始近似P使用Z=估计差值/bootstrap标准误，再计算双侧正态尾概率2*pnorm(-abs(Z))。区间使用bootstrap百分位数，不是正态P值的严格反演。非常小的P值来自正态尾部外推，**不是50,000次重抽样直接验证了十亿分之一的概率**。

为同时补充三个指标，计算前约定：同一CV设计、同一评价方式下，三指标×三模型×两训练＝18项作为本补充的联合BH家族；同时给出每个指标单独六项的BH列。Null的AUC结构性结果不进入校正家族。两列回答不同的多重比较范围，不能事后只选较小的一列。跨指标校正不保证数值总比单指标校正大，BH还取决于这一组P值的排序。

## 结果概览与解释

五折、物种等权评价仍是主要阅读口径：

- AUC：M1/M2/M3的两种训练共六项，原始及两种BH列均低于0.05。
- MAE：M2记录训练与M3两种训练的原始P低于0.05；但**按MAE单独六项校正，没有一项低于0.05**。三指标18项联合校正下，M3两种训练低于0.05，因此MAE结论对比较家族敏感，不能不加限定地写“MAE显著改善”。
- RMSE：M2记录训练、M3记录训练和M3物种训练，在六项与18项两种校正下都低于0.05。
- 十折敏感性结果并不全部重复五折的误差显著性：物种等权评价下，MAE六项/18项均无低于0.05，RMSE单指标六项也无低于0.05；详细值全部列在后面的表中。

M3记录等权训练在主评价下：AUC=0.8008，MAE相对对应Null减少4.780个百分点，RMSE减少6.961个百分点。M3物种等权训练相应误差减少5.310和5.919个百分点。比较的是不同终点与其基线，不意味着这些模型在所有指标上均有同样强的证据，也不能用“某模型P更小”推断它显著优于另一个非Null模型。

ELPD检查完整预测分布并使用153条记录、51个物种；MAE/RMSE只检查145条点值记录、48个物种的点预测误差。因此，误差指标有改善而ELPD主比较仍不确定，并不矛盾。新增指标不会改写已发表的ELPD结果。

## 重要的推断边界

这些是**固定已训练OOF预测的条件近似P值**，未重新拟合，没有把全部训练集重叠、训练随机性、分折选择和模型选择不确定性纳入。这不是完整训练流程的置换检验，也不是新物种外部验证，不能将极小的近似P当作全流程确证性保证。

AUC还条件于原折号和物种类别组成。十折每折只有5个物种，其中第1、4、5、7折各只有1个带LOW记录的物种，不能从这些折得到充分的LOW类物种间变异信息。已在SupportNote和auc_fold_species_support.csv中明确标记，十折AUC的推断尤其应谨慎。五折每折10物种，带LOW记录的物种至少3个；这仍然是小样本条件近似。

Null在每一折内所有物种预测分数相同，按并列计半分规则AUC恒为0.5。本表用P=1表示没有区分优势，区间[0.5,0.5]为结构性结果，不能解释成数据给出了极高精度。非Null若出现零bootstrap方差则不产生P=0；本次未出现这种退化行。

区间没有做多重区间校正。P＜0.05也不表示比例预测误差足够小；例如M3主评价MAE仍约28.6—28.9个百分点。应连同已有ELPD、PPC、预测区间和外推警告解释。

'''
report+='\n\n'.join(blocks)
report+='\n\n## 主评价下的差值与区间图\n\n!['+'主评价补充检验图]('+(out/'primary_supplementary_tests.png').as_posix()+')\n\n'+link('矢量SVG',out/'primary_supplementary_tests.svg')+'\n'
report+='''
## 验证与复现

- 18项确定性检查通过，包括手算加权AUC、物种副本权重、并列分数、无效折拒绝、RMSE与MAE反例、结构性Null及非Null零方差处理。
- 96个指标点值与原正式汇总表一致，最大误差约5e-16。
- 80组完整bootstrap差值向量已保存；从中选定240个实际重抽样实例，逐条复制物种记录后用原指标函数独立复算，最大误差约2.22e-16。
- 独立Python正态尾概率和BH排序算法复核通过，最大误差约2e-15。
- 原有31个正式派生文件的SHA-256保持不变；没有新拟合、没有覆盖原P值文件。

关键文件：

'''
for n,label in [('supplementary_metric_tests.csv','全部80行结果'),('auc_tests.csv','AUC对0.5'),('mae_tests.csv','MAE对Null'),('rmse_tests.csv','RMSE对Null'),('ANALYSIS_PLAN.json','计算前固定的分析方案'),('auc_fold_species_support.csv','每折类别与物种支持'),('bootstrap_difference_draws.rds','完整重抽样差值'),('bootstrap_species_multiplicities.rds','物种抽样索引与分组数据'),('calculate_supplement_tests.R','计算脚本'),('supplement_functions.R','计算函数'),('independent_validation.json','独立核验结果')]:report+='- '+link(label,out/n)+'\n'
report+='\n复现命令（使用项目R环境）：\n\n~~~text\nRscript test_supplement_functions.R OUTPUT_DIR V3_4_ROOT\nRscript calculate_supplement_tests.R V3_4_ROOT OUTPUT_DIR\nRscript verify_bootstrap_results.R V3_4_ROOT OUTPUT_DIR\n~~~\n\n方法背景：项目原R/metrics.R和R/cross_validation.R定义指标；[LeDell等关于CV-AUC的论文](https://pmc.ncbi.nlm.nih.gov/articles/PMC4533123/)讨论按验证折平均的目标；[pROC源码](https://github.com/xrobin/pROC/blob/master/R/ci.auc.R)说明其常规AUC bootstrap与分层处理。本补充按本项目物种聚类和评价权重自行实现，未直接套用记录独立的DeLong或pROC检验，也未声称文献保证本项目小样本下的精确检验水平。\n'
(out/'ADDITIONAL_METRIC_TESTS_zh.md').write_text(report,encoding='utf-8')
summary={'status':'COMPLETE_EXPLORATORY_SUPPLEMENT','rows':80,'AUC_rows':32,'MAE_rows':24,'RMSE_rows':24,'bootstrap_replicates':50000,'meaningful_tests':72,'null_auc_structural_rows':8,'new_fits':0,'primary_report':'ADDITIONAL_METRIC_TESTS_zh.md','source_results_modified':False,'testing_scope':'MAE/RMSE model versus same-training Null; no pairwise training-method tests in this supplement','normal_approximation_and_stratification_limits_disclosed':True}
(out/'supplement_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(summary,ensure_ascii=False,indent=2))
