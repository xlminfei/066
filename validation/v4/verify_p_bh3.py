import csv,hashlib,json,math,sys
from pathlib import Path
from collections import defaultdict
repo=Path(sys.argv[1]);root=repo/'validation/v4';src=root/'metrics_final/hypothesis_tests.csv'
with src.open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
assert len(rows)==30
groups=defaultdict(list)
p_errors=[];bh_errors=[]
for r in rows:
    groups[tuple(r[k] for k in ['Route','Metric','Design','TrainWeighting','EvalWeighting'])].append(r)
    p_errors.append(abs(math.erfc(abs(float(r['Difference'])/float(r['SE_approx']))/math.sqrt(2))-float(r['P_approx'])))
assert len(groups)==10
for key,rr in groups.items():
    assert len(rr)==3 and {r['Model'] for r in rr}=={'M1','M2','M3'}
    ordered=sorted(rr,key=lambda r:float(r['P_approx']));running=1
    for i in range(2,-1,-1):
        r=ordered[i];running=min(running,float(r['P_approx'])*3/(i+1))
        bh_errors.append(abs(running-float(r['P_BH3'])))
assert max(p_errors)<1e-12 and max(bh_errors)<1e-12
formal=repo/'formal_results/v3.4_20260923/snapshot/v3.4'
with (formal/'review/derived_outputs_manifest.csv').open(encoding='utf-8-sig',newline='') as f:manifest=list(csv.DictReader(f))
for r in manifest:assert hashlib.sha256((formal/r['Path']).read_bytes()).hexdigest()==r['SHA256']
result=dict(status='PASS',tests=30,BH_families=10,models_per_family=3,normal_P_max_error=max(p_errors),
 BH3_max_error=max(bh_errors),original_formal_outputs_unchanged=len(manifest),new_fits=0)
(root/'independent_P_BH3.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
