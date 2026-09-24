import csv,hashlib,io,json,sys,zipfile
from pathlib import Path
repo=Path(sys.argv[1]).resolve();dest=Path(sys.argv[2]).resolve();dest.mkdir(parents=True,exist_ok=True)
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def write_manifest(root):
    files=sorted(p for p in root.rglob('*') if p.is_file() and p.name!='FILES_SHA256.csv')
    rows=[dict(Path=p.relative_to(root).as_posix(),Bytes=p.stat().st_size,SHA256=sha(p)) for p in files]
    with (root/'FILES_SHA256.csv').open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=['Path','Bytes','SHA256']);w.writeheader();w.writerows(rows)
    return rows
code=write_manifest(repo/'v4');validation=write_manifest(repo/'validation/v4')
archives=[]
for name,roots in [('v4-code.zip',['v4']),('v4-validation-complete.zip',['v4','validation/v4'])]:
    rows=[]
    for folder in roots:
        for p in sorted((repo/folder).rglob('*')):
            if p.is_file():rows.append(dict(Path=p.relative_to(repo).as_posix(),Bytes=p.stat().st_size,SHA256=sha(p)))
    target=dest/name
    if target.exists():raise RuntimeError('Refuse archive overwrite: '+str(target))
    with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
        for r in rows:z.write(repo/r['Path'],r['Path'])
    with zipfile.ZipFile(target) as z:
        assert len(z.namelist())==len(rows)==len(set(z.namelist()))
        assert z.testzip() is None
        for r in rows:
            b=z.read(r['Path']);assert len(b)==r['Bytes'] and hashlib.sha256(b).hexdigest()==r['SHA256'],r['Path']
    archives.append(dict(name=name,bytes=target.stat().st_size,sha256=sha(target),files=len(rows),
        uncompressed_bytes=sum(r['Bytes'] for r in rows),contents=rows,
        url='https://github.com/xlminfei/066/releases/download/v4/'+name))
summary=dict(status='BUILT_AND_READBACK_VERIFIED',tag='v4',source_baseline='4e0fdbb08562f1a8905734b2f0eb831697281388',
 code_files=len(code)+1,validation_files=len(validation)+1,code_bytes=sum(r['Bytes'] for r in code),
 new_research_fits=0,real_synthetic_fits=2,archives=archives)
(repo/'releases/v4/archive-manifest.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({**{k:v for k,v in summary.items() if k!='archives'},
 'archives':[{k:v for k,v in a.items() if k!='contents'} for a in archives]},ensure_ascii=False,indent=2))
