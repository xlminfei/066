import csv,json,math,hashlib,sys
from pathlib import Path
from collections import defaultdict
root,out=map(Path,sys.argv[1:3])
def read(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
rows=read(out/'supplementary_metric_tests.csv');eligible=[r for r in rows if r['MultiplicityEligible']=='TRUE'];assert len(rows)==80 and len(eligible)==72
p_error=[]
for r in rows:
 if r['TestStatus']=='STRUCTURAL_AUC_0_5_NO_DISCRIMINATION':assert float(r['Estimate'])==.5 and float(r['P_approx'])==1;continue
 expected=math.erfc(abs(float(r['Difference'])/float(r['SE_approx']))/math.sqrt(2));p_error.append(abs(expected-float(r['P_approx'])))
def check_bh(keys,col,n):
 groups=defaultdict(list)
 for r in eligible:groups[tuple(r[k] for k in keys)].append(r)
 errors=[]
 for key,group in groups.items():
  assert len(group)==n;ordered=sorted(group,key=lambda r:float(r['P_approx']));running=1.
  for i in range(n-1,-1,-1):
   r=ordered[i];running=min(running,float(r['P_approx'])*n/(i+1));errors.append(abs(running-float(r[col])))
 return max(errors)
e1=check_bh(['Metric','Design','EvalWeighting'],'P_BH_endpoint',6);e2=check_bh(['Design','EvalWeighting'],'P_BH_three_metrics',18)
assert max(p_error)<1e-12 and e1<1e-12 and e2<1e-12
manifest=read(root/'review/derived_outputs_manifest.csv');changed=[r['Path'] for r in manifest if hashlib.sha256((root/r['Path']).read_bytes()).hexdigest()!=r['SHA256']];assert not changed
result={'status':'PASS','result_rows':80,'inferential_tests':72,'normal_P_max_abs_error':max(p_error),'BH_endpoint_max_abs_error':e1,'BH_three_metrics_max_abs_error':e2,'source_files_unchanged':len(manifest),'new_fits':0}
(out/'independent_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
