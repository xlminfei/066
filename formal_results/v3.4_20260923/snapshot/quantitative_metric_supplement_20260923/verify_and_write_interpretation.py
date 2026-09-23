import csv,json,math,hashlib,sys,itertools,xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image
root=Path(sys.argv[1]);out=Path(sys.argv[2])
def rows(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def link(label,p):return f'[{label}]({p.as_posix()})'
cv=rows(root/'results/cv_metrics_summary.csv');mc=rows(root/'results/model_vs_null.csv');tc=rows(root/'results/training_method_comparisons.csv')
keys=['Design','Route','Model','TrainWeighting','EvalWeighting'];mk=lambda x:tuple(x[k] for k in keys)
lookup={mk(x):x for x in cv}; plotted=rows(out/'plotted_values.csv'); issues=[]
expected={(mk(x),m) for x in cv for m in (['ELPD','MAE','RMSE'] if x['Route']=='joint_bb' else ['ELPD'])}
actual=[(mk(x),x['Metric']) for x in plotted]
if len(actual)!=len(set(actual)) or set(actual)!=expected:issues.append('plotted key grid mismatch')
for x in plotted:
 raw=float(lookup[mk(x)][x['Metric']]);scale=1 if x['Metric']=='ELPD' else 100
 if not math.isclose(float(x['RawValue']),raw,rel_tol=1e-12,abs_tol=1e-12) or not math.isclose(float(x['PlotValue']),raw*scale,rel_tol=1e-12,abs_tol=1e-12):issues.append('plotted value mismatch '+str(mk(x)))
for x in rows(root/'review/derived_outputs_manifest.csv'):
 if sha(root/x['Path'])!=x['SHA256']:issues.append('formal output changed '+x['Path'])
figures=[]
for stem in ['ELPD','MAE','RMSE','ELPD_binary']:
 png=out/f'{stem}_comparison.png';svg=out/f'{stem}_comparison.svg';preview=out/f'{stem}_preview.png'
 with Image.open(png) as im: im.verify()
 with Image.open(png) as im: size=list(im.size)
 with Image.open(preview) as im: im.verify()
 node=ET.parse(svg).getroot();paths=sum(1 for e in node.iter() if e.tag.endswith('path'))
 if not paths:issues.append('SVG empty '+stem)
 figures.append(dict(metric=stem,png_dimensions=size,png_sha256=sha(png),svg_sha256=sha(svg),svg_paths=paths))
primary=[x for x in cv if x['Route']=='joint_bb' and x['Design']=='fivefold' and x['EvalWeighting']=='species_equal']
secondary=[x for x in cv if x['Route']=='joint_bb' and x['Design']=='tenfold' and x['EvalWeighting']=='species_equal']
name={'record_equal':'记录等权','species_equal':'物种等权'}
def metric_table(xs):
 head='| 模型 | 训练方式 | ELPD（越大越好） | MeanLogScore | MAE（百分点） | RMSE（百分点） | Bias（百分点） |\n|---|---|---:|---:|---:|---:|---:|\n'
 return head+'\n'.join(f"| {x['Model']} | {name[x['TrainWeighting']]} | {float(x['ELPD']):.2f} | {float(x['MeanLogScore']):.4f} | {100*float(x['MAE']):.2f} | {100*float(x['RMSE']):.2f} | {100*float(x['Bias']):+.2f} |" for x in xs)
q=lambda m,t,d='fivefold':lookup[(d,'joint_bb',m,t,'species_equal')]
m3=q('M3','record_equal');m3s=q('M3','species_equal');null=q('Null','record_equal')
c=next(x for x in mc if x['Route']=='joint_bb' and x['Design']=='fivefold' and x['EvalWeighting']=='species_equal' and x['TrainWeighting']=='record_equal' and x['Model']=='M3')
tr=next(x for x in tc if x['Route']=='joint_bb' and x['Design']=='fivefold' and x['EvalWeighting']=='species_equal' and x['Model']=='M3')
fig_block='\n\n'.join('!['+stem+' 比较图]('+ (out/f'{stem}_preview.png').as_posix()+')\n\n'+link('高清 PNG',out/f'{stem}_comparison.png')+' · '+link('矢量 SVG',out/f'{stem}_comparison.svg') for stem in ['ELPD','MAE','RMSE'])
comp_primary=[x for x in mc if x['Route']=='joint_bb' and x['Design']=='fivefold' and x['EvalWeighting']=='species_equal']
comp_table='| 模型 | 训练方式 | 相对Null的MeanLogScore差 | 95%区间下界 | 上界 | P_approx | P_BH |\n|---|---|---:|---:|---:|---:|---:|\n'+'\n'.join(f"| {x['Model']} | {name[x['TrainWeighting']]} | {float(x['Difference']):+.4f} | {float(x['CI95_lower']):+.4f} | {float(x['CI95_upper']):+.4f} | {float(x['P_approx']):.4f} | {float(x['P_BH']):.4f} |" for x in comp_primary)
report=f'''# v3.4 正式结果：ELPD、MAE、RMSE补充图与中文解读

本文件补充现有正式结果的展示与解释。原v3.4报告已列出这些指标，但没有对应的独立比较图，也没有逐项解读。本轮使用已保存CSV，未重新拟合、未改变数据/权重/先验、未新增bootstrap或显著性检验。原正式输出文件的SHA-256仍全部一致。

## 如何读图

每图包含四个面板：上排五折、下排十折；左列物种等权评价、右列记录等权评价。左上角为预先指定的主评价。蓝色圆点为记录等权训练，橙色菱形为物种等权训练。

只在同一面板内比较模型和训练方式。物种等权评价与记录等权评价针对不同目标，不能跨面板挑出一个最高或最低数值宣布赢家。两套CV使用同一批物种，十折是敏感性分析；四种训练—评价组合彼此相关。

三个指标展示完整OOF记录上的既有总体值，不是简单平均各折误差。本轮没有新增误差条；这些点图不能表示差异的不确定性，也不能用它们直接判定统计显著性。

## 指标分别是什么意思

| 指标 | 本项目实际计算 | 好坏方向 | 使用的数据 |
|---|---|---|---|
| ELPD | 评价权重乘每条留出观测的log预测概率/密度，再相加；权重和等于记录数153 | 越大越好，例如-182优于-200 | count、exact、interval合计153条、51物种 |
| MeanLogScore | ELPD除以评价权重和；在本定量总体比较中为ELPD/153 | 越大越好 | 同ELPD |
| MAE | 评价加权的绝对误差平均值 | 越小越好 | count/exact的145条、48物种 |
| RMSE | 评价加权的平方误差平均值再开方，大误差影响更大 | 越小越好 | 同MAE |

MAE/RMSE使用后验均值作为点预测。图中乘100转为“百分点”：MAE=0.2886表示所选评价权重下，每条观测报告的绝对预测误差平均约28.86个百分点。它不表示准确率为71.14%，也不是相对误差28.86%。interval没有唯一观测点，故不参与MAE/RMSE，不使用区间中点代替。

ELPD评价完整预测分布，MAE/RMSE评价点预测，所以三者的排序可以不完全相同。ELPD的绝对值没有这里预设的通用合格线；binary与joint_bb观测模型不同，其ELPD不直接比较。

## 主结果：五折、物种等权评价

{metric_table(primary)}

- 按主要log score目标，M3记录等权训练的ELPD={float(m3['ELPD']):.2f}，在此面板中最高。相同训练方式的Null为{float(null['ELPD']):.2f}，两者相差{float(m3['ELPD'])-float(null['ELPD']):.2f}个本项目定义的加权总log-score单位。
- M3物种等权训练的MAE={100*float(m3s['MAE']):.2f}个百分点、RMSE={100*float(m3s['RMSE']):.2f}个百分点，是这个面板中最低的点估计。
- 但相对M3记录等权训练，其MAE只减少{100*(float(m3['MAE'])-float(m3s['MAE'])):.2f}个百分点、RMSE只减少{100*(float(m3['RMSE'])-float(m3s['RMSE'])):.2f}个百分点；ELPD反而略低。这不支持把物种等权训练概括为所有指标都更好。
- M3记录等权训练相对同训练Null，MAE减少{100*(float(null['MAE'])-float(m3['MAE'])):.2f}个百分点、RMSE减少{100*(float(null['RMSE'])-float(m3['RMSE'])):.2f}个百分点。点预测确有改善，但平均绝对误差仍约29个百分点，实际用途能否接受还需结合目标容许误差讨论。

## 数值改善是否已经有充分的差异证据

下表直接读取已有模型比较结果。Difference和区间是MeanLogScore差，不是MAE/RMSE差；相对Null为正表示log score改善。

{comp_table}

对主结果中的M3记录等权训练，差值为{float(c['Difference']):+.4f}，95%物种bootstrap近似区间为[{float(c['CI95_lower']):+.4f}, {float(c['CI95_upper']):+.4f}]，P_approx={float(c['P_approx']):.4f}，P_BH={float(c['P_BH']):.4f}。区间跨0，目前不能宣称其相对Null具有明确统计显著优势。P值较大也不能证明两者等效。

M3两种训练的MeanLogScore差（物种训练减记录训练）为{float(tr['Difference']):+.4f}，95%近似区间为[{float(tr['CI95_lower']):+.4f}, {float(tr['CI95_upper']):+.4f}]，P_approx={float(tr['P_approx']):.4f}，P_BH={float(tr['P_BH']):.4f}。因此也不能据这些结果断言两种训练已有可靠差别。

上述区间来自固定OOF预测下的物种配对bootstrap；P_approx使用近似正态差异统计量，区间则使用bootstrap分位数，二者不是严格反演关系。它们不包含重新训练和模型选择的不确定性。MAE/RMSE目前只有点估计，现有log score的P值不能移用于它们；本轮依照既定范围没有补做MAE/RMSE置信区间或检验。

## 十折敏感性分析

{metric_table(secondary)}

十折下，跨本面板8套拟合，记录等权训练的M3仍给出最高ELPD，物种等权训练的M3给出最低MAE/RMSE。两种M3训练的点误差差距仍小。注意，在仅看物种等权训练时，M2的十折ELPD略高于M3，因此不能概括成“M3在所有训练/评价/设计组合下都最佳”。十折不是独立重复实验。

## 还要同时保留的限制

本次正式采样和最终审计全部通过，这支持这些数值来自约定流程。模型适用性仍需结合训练内PPC的18项提示、校准支持不足/退化状态、预测区间宽度及目标物种外推警告解释。

例如主评价下M3记录等权训练的预测区间覆盖率为{100*float(m3['PICoverage']):.2f}%，平均区间宽度约{100*float(m3['MeanPIWidth']):.2f}个百分点。高覆盖率伴随很宽的区间，不应单凭覆盖率高便认定预测已足够精确。

## 三项定量比较图

{fig_block}

## 分类ELPD补充图

分类路线仅使用152条可判HIGH/LOW的记录、50个物种。它是另一观测模型的留出log score，不与定量ELPD的绝对值直接比较。定性路线没有本报告中的比例MAE/RMSE。

![分类ELPD]({(out/'ELPD_binary_preview.png').as_posix()})

{link('分类ELPD高清 PNG',out/'ELPD_binary_comparison.png')} · {link('分类ELPD矢量 SVG',out/'ELPD_binary_comparison.svg')}

## 来源、复现和验证

- 正式源文件：{link('CV总体指标',root/'results/cv_metrics_summary.csv')}、{link('模型对Null比较',root/'results/model_vs_null.csv')}、{link('训练方式比较',root/'results/training_method_comparisons.csv')}。
- 可复现脚本：{link('make_metric_figures.R',out/'make_metric_figures.R')}。使用项目既有R 4.6.1 Docker镜像和基础图形设备生成PNG/SVG，中文字体为Microsoft YaHei。最初检查发现宿主Python没有Matplotlib，因此采用已有R环境，未安装新依赖。
- 脚本用法：Rscript make_metric_figures.R VERSION_ROOT OUTPUT_DIR。Linux环境需有图中所用中文字体。
- 定量/分类各32个组的身份已核对；128个实际绘制值逐项回查正式汇总表，MAE/RMSE仅作×100的单位转换。
- PNG已打开校验，SVG已解析，图像目视检查另见visual_check.json；plot_validation.json和supplement_validation.json保存数值及源文件校验结果。
- 本补充目录与原v3.4目录隔离；原正式结果、31个派生输出校验值和最终审计状态保持不变。原生产绘图入口未改，今后重跑时应显式运行这份补图脚本。
- round1目录保留第一次生成的图片、脚本与日志作为中间文件；最终文件位于本目录根层。
'''
(out/'INTERPRETATION_zh.md').write_text(report,encoding='utf-8')
validation=dict(status='PASS' if not issues else 'FAIL',plotted_values=len(plotted),figures=figures,issues=issues,formal_derived_files_verified=31,new_fits=0,new_bootstrap=0,new_tests_of_effect=0,statement='Numeric source and file validation; visual inspection separately recorded.')
(out/'supplement_validation.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(validation,ensure_ascii=False,indent=2));sys.exit(0 if not issues else 1)
