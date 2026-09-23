import csv,json,math,hashlib,sys
from pathlib import Path
from collections import defaultdict
root=Path(sys.argv[1]);out=Path(sys.argv[2]);receipts=[]
for file in ['model_vs_null.csv','training_method_comparisons.csv']:
 with (root/'results'/file).open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
 maxp=max(abs(math.erfc(abs(float(r['Difference'])/float(r['SE_approx']))/math.sqrt(2))-float(r['P_approx'])) for r in rows)
 groups=defaultdict(list)
 for i,r in enumerate(rows):groups[tuple(r[c] for c in ['Family','Scope','EvalWeighting','Route','Design'])].append(i)
 bh=[None]*len(rows)
 for ix in groups.values():
  order=sorted(ix,key=lambda i:float(rows[i]['P_approx']));running=1.
  for rank in range(len(order)-1,-1,-1):
   i=order[rank];running=min(running,float(rows[i]['P_approx'])*len(order)/(rank+1));bh[i]=running
 err=max(abs(bh[i]-float(r['P_BH'])) for i,r in enumerate(rows))
 assert maxp<1e-12 and err<1e-12
 receipts.append(dict(file=file,rows=len(rows),normal_P_max_abs_difference=maxp,BH_max_abs_difference=err,group_sizes=sorted(set(len(g) for g in groups.values())),status='PASS'))
# Confirm original formal derived files remain byte-identical after read-only reanalysis.
with (root/'review/derived_outputs_manifest.csv').open(encoding='utf-8-sig',newline='') as f:manifest=list(csv.DictReader(f))
changed=[r['Path'] for r in manifest if hashlib.sha256((root/r['Path']).read_bytes()).hexdigest()!=r['SHA256']]
assert not changed
result={'status':'PASS','independent_checks':receipts,'unchanged_formal_outputs':len(manifest),'new_fits':0}
(out/'independent_P_BH_and_source_integrity.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
