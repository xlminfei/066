import csv,hashlib,json,re,sys
from pathlib import Path
b=Path(sys.argv[1]);expected={};issues=[]
with (b/'files.csv').open(encoding='utf-8',newline='') as f:
 for r in csv.DictReader(f):
  if r['GitMirror']:expected[r['GitMirror']]=r
for rel,r in expected.items():
 p=b/rel
 if not p.is_file() or p.stat().st_size!=int(r['Bytes']) or hashlib.sha256(p.read_bytes()).hexdigest()!=r['SHA256']:issues.append(rel)
actual={p.relative_to(b).as_posix() for p in (b/'snapshot').rglob('*') if p.is_file()}
if actual!=set(expected):issues.append('mirror path universe mismatch')
links=[]
for name in ['README.md','ANALYSIS_zh.md','RUN_REVIEW_zh.md']:
 for target in re.findall(r'\]\(([^)]+)\)',(b/name).read_text(encoding='utf-8')):
  if target.startswith(('http:','https:','#')):continue
  p=(b/target.split('#')[0]);links.append({'source':name,'target':target,'exists':p.exists()})
  if not p.exists():issues.append('missing link '+name+' -> '+target)
result={'status':'PASS' if not issues else 'FAIL','mirrored_files':len(expected),'byte_exact_matches':len(expected)-sum(1 for x in issues if x in expected),'local_links_checked':len(links),'issues':issues}
(b/'git_mirror_validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result,indent=2));sys.exit(0 if not issues else 1)
