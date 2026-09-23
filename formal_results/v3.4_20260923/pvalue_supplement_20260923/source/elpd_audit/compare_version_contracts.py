import csv,hashlib,json,tarfile,re,sys,itertools,math
from pathlib import Path
repo,out,cur=map(Path,sys.argv[1:4])
def read(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
result={'inputs':[],'folds':[],'v1_csv_significance_columns':[],'v1_selected':[]}
for name in ['observations.csv','sites.csv']:
 paths={'v1':repo/'v1/data'/name,'v2':repo/'v2/data'/name,'v3.4':cur/'input'/name};data={v:read(p) for v,p in paths.items()}
 key='RecordID' if name=='observations.csv' else 'Species'
 keys={v:{x[key]:x for x in xs} for v,xs in data.items()};fields={v:list(xs[0]) for v,xs in data.items()}
 def norm(v):
  if v in ['', 'NA','NaN']:return None
  try:return float(v)
  except ValueError:return v
 for v,p in paths.items():
  missing=set(keys['v3.4'])-set(keys[v]);extra=set(keys[v])-set(keys['v3.4']);changed=[]
  for k in set(keys[v])&set(keys['v3.4']):
   for c in set(fields[v])&set(fields['v3.4']):
    if norm(keys[v][k][c])!=norm(keys['v3.4'][k][c]):changed.append({'key':k,'column':c,'old':keys[v][k][c],'new':keys['v3.4'][k][c]})
  result['inputs'].append(dict(file=name,version=v,rows=len(data[v]),columns=fields[v],sha256=sha(p),missing_keys=len(missing),extra_keys=len(extra),changed_cells=changed))
for route in ['binary','joint_bb']:
 for k in [5,10]:
  old=repo/'v2/results'/f'folds_{"joint" if route=="joint_bb" else "binary"}_species_{k}.csv'
  new=cur/'results'/f'folds_{route}_species_{k}.csv'
  old_rows=[r for r in read(repo/'v2/results/cv_record_scores_v2.csv') if r['Route']==route and r['Design']==f'species{k}' and r['Model']=='Null']
  a={}
  for r in old_rows:
   if r['Species'] in a and a[r['Species']]!=int(r['Fold']):raise RuntimeError('Conflicting old fold assignment')
   a[r['Species']]=int(r['Fold'])
  b={r['Species']:int(r['Fold']) for r in read(new)}
  sp=sorted(set(a)&set(b));pairs=list(itertools.combinations(sp,2));agree=sum((a[i]==a[j])==(b[i]==b[j]) for i,j in pairs);both=sum(a[i]==a[j] and b[i]==b[j] for i,j in pairs)
  same_partition=all((a[i]==a[j])==(b[i]==b[j]) for i,j in pairs)
  result['folds'].append(dict(route=route,k=k,species=len(sp),same_species_set=set(a)==set(b),same_numeric_fold=sum(a[s]==b[s] for s in sp),same_partition_up_to_labels=same_partition,pair_agreement=agree/len(pairs),pairs_together_in_both=both,old_pairs_together=sum(a[i]==a[j] for i,j in pairs),new_pairs_together=sum(b[i]==b[j] for i,j in pairs)))
for ap in sorted((repo/'v1/archive').glob('*.tar.gz')):
 with tarfile.open(ap,'r:gz') as tf:
  for m in tf:
   if not m.isfile():continue
   if m.name.endswith('.csv'):
    b=tf.extractfile(m).read();text=b.decode('utf-8-sig','replace');rs=list(csv.DictReader(text.splitlines()));headers=list(rs[0]) if rs else next(csv.reader(text.splitlines()),[])
    cols=[c for c in headers if re.search(r'(^p$|^p_|p[_ .-]?value|^pd$|prob.*(positive|negative|zero)|^Pr_gt_0$|pval)' ,c,re.I)]
    if cols:result['v1_csv_significance_columns'].append(dict(archive=ap.name,path=m.name,columns=cols,examples=[{c:r[c] for c in cols} for r in rs[:3]]))
    if m.name.endswith(('cv_model_comparison_all.csv','model_comparison_loo_primary.csv','loo_estimates_primary.csv','cv_model_comparison_with_mc.csv')):
     dest=out/'v1_selected'/ap.stem.replace('.tar','')/m.name
     if dest.resolve().is_relative_to(out.resolve()):dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
     result['v1_selected'].append(dict(archive=ap.name,path=m.name,rows=len(rs),columns=headers,first_rows=rs[:2]))
(out/'version_contract_comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'input_checks':len(result['inputs']),'changed_cells':sum(len(x['changed_cells']) for x in result['inputs']),'folds':result['folds'],'v1_significance_columns':result['v1_csv_significance_columns'],'v1_selected_tables':len(result['v1_selected'])},ensure_ascii=False,indent=2))
