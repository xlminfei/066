import csv,hashlib,json,tarfile,re,sys
from pathlib import Path
from collections import Counter,defaultdict
repo=Path(sys.argv[1]);out=Path(sys.argv[2]);cur=Path(sys.argv[3]);summary={}
for filename in ['model_vs_null.csv','training_method_comparisons.csv']:
 with (cur/'results'/filename).open(encoding='utf-8-sig',newline='') as f:rs=list(csv.DictReader(f))
 groups=defaultdict(list)
 for x in rs:groups[(x['Route'],x['EvalWeighting'],x['Design'])].append(x)
 summary[filename]=[dict(group=k,n=len(v),raw_below05=sum(float(x['P_approx'])<.05 for x in v if x['P_approx'] not in ('','NA')),BH_below05=sum(float(x['P_BH'])<.05 for x in v if x['P_BH'] not in ('','NA'))) for k,v in groups.items()]
print('CURRENT_P_COUNTS',json.dumps(summary,ensure_ascii=False,indent=2))
archive_inventory=[]; hits=[];selected=[]
for archive in sorted((repo/'v1/archive').glob('*.tar.gz')):
 with tarfile.open(archive,'r:gz') as tf:
  for member in tf:
   if not member.isfile():continue
   archive_inventory.append(dict(archive=archive.name,path=member.name,bytes=member.size))
   if member.name.lower().endswith(('.csv','.md','.txt','.json','.r','.py')):
    b=tf.extractfile(member).read();text=b.decode('utf-8-sig','replace')
    found=[]
    for i,line in enumerate(text.splitlines(),1):
     if re.search(r'p[_ .-]?value|p[_ .-]?bh|p[_ .-]?approx|p[_ .-]?normal|p_adjust|p_adj|pnorm\(|p\s*[<＝=]\s*0\.|Pr\([^)]*>|显著|BH校正',line,re.I):found.append({'line':i,'text':line[:1000]})
    if found:
     hits.append(dict(archive=archive.name,path=member.name,hits=found[:80]))
     # Preserve only relevant text members, using a safe mirror under this audit.
     dest=out/'v1_evidence'/archive.stem.replace('.tar','')/member.name
     if dest.resolve().is_relative_to(out.resolve()):dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
    if re.search(r'comparison|compare|contrast|elpd|diagnostic|primary.*report|report.*primary',member.name,re.I):selected.append(dict(archive=archive.name,path=member.name,bytes=member.size))
(out/'v1_archive_inventory.json').write_text(json.dumps(archive_inventory,ensure_ascii=False,indent=2),encoding='utf-8')
(out/'v1_pvalue_search.json').write_text(json.dumps(hits,ensure_ascii=False,indent=2),encoding='utf-8')
(out/'current_pvalue_counts.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print('V1_ARCHIVE_FILES',len(archive_inventory),'HIT_FILES',len(hits))
print('V1_HITS',json.dumps(hits,ensure_ascii=False,indent=2))
print('V1_COMPARISON_CANDIDATES',json.dumps(selected,ensure_ascii=False,indent=2))
