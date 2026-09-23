import csv,json,math
from pathlib import Path
repo=Path(r'C:\Users\minfei\Documents\ChatGPT\建模\publication\v3_4_formal_results_20260923\repository');base=repo/'v2/results/derived'
def read(n):
 with (base/n).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
a=[r for r in read('paired_elpd_comparisons.csv') if r['Reference']=='Null' and r['Model'] in ['M1','M2','M3']];b=read('paired_elpd_M1M2M3_vs_Null_corrections_by_fold.csv');ref={(r['Route'],r['Design'],r['Model']):r for r in b};out=[]
for design in ['species5','species10']:
 g=sorted([r for r in a if r['Design']==design],key=lambda r:float(r['p_value_normal_approx']));adj=1
 for i in range(len(g)-1,-1,-1):
  r=g[i];adj=min(adj,float(r['p_value_normal_approx'])*len(g)/(i+1));s=ref[(r['Route'],r['Design'],r['Model'])];out.append(dict(Design=design,Route=r['Route'],Model=r['Model'],Raw=float(r['p_value_normal_approx']),ComputedBH=adj,SavedBH=float(s['BH_by_design']),difference=adj-float(s['BH_by_design'])))
print(json.dumps(out,indent=2))
