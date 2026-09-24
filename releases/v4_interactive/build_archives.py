import csv,hashlib,json,sys,zipfile
from pathlib import Path
repo=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
tag='v4-interactive';release=repo/'releases/v4_interactive'
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def manifest(folder):
    paths=sorted(p for p in folder.rglob('*') if p.is_file() and p.name!='FILES_SHA256.csv')
    rows=[dict(Path=p.relative_to(folder).as_posix(),Bytes=p.stat().st_size,SHA256=sha(p)) for p in paths]
    with (folder/'FILES_SHA256.csv').open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=['Path','Bytes','SHA256']);w.writeheader();w.writerows(rows)
manifest(repo/'v4');manifest(repo/'validation/v4_interactive')
entries=[]
for name,folders in [('v4-interactive-code.zip',['v4']),('v4-interactive-validation-complete.zip',['v4','validation/v4_interactive'])]:
    records=[]
    for folder in folders:
        for p in sorted((repo/folder).rglob('*')):
            if p.is_file():records.append(dict(Path=p.relative_to(repo).as_posix(),Bytes=p.stat().st_size,SHA256=sha(p)))
    zpath=out/name
    if zpath.exists():raise RuntimeError('Archive already exists')
    with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
        for r in records:z.write(repo/r['Path'],r['Path'])
    with zipfile.ZipFile(zpath) as z:
        assert z.testzip() is None
        assert len(z.namelist())==len(records)==len(set(z.namelist()))
        for r in records:
            b=z.read(r['Path']);assert len(b)==r['Bytes'] and hashlib.sha256(b).hexdigest()==r['SHA256']
    entry=dict(name=name,bytes=zpath.stat().st_size,sha256=sha(zpath),files=len(records),contents=records)
    if entry['bytes']>64*1024*1024:
        parts=[]
        with zpath.open('rb') as f:
            i=1
            while True:
                b=f.read(32*1024*1024)
                if not b:break
                p=out/(name+f'.part{i:03d}');p.write_bytes(b)
                parts.append(dict(name=p.name,bytes=len(b),sha256=hashlib.sha256(b).hexdigest(),
                  url=f'https://github.com/xlminfei/066/releases/download/{tag}/{p.name}'))
                i+=1
        entry['parts']=parts
    else:entry['url']=f'https://github.com/xlminfei/066/releases/download/{tag}/{name}'
    entries.append(entry)
result=dict(status='BUILT_AND_ALL_MEMBERS_VERIFIED',tag=tag,baseline='7ce962e17ea3ba24f1830d489179883caacbbbd0',
  new_mcmc_fits=0,archives=entries)
(release/'archive-manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({**{k:v for k,v in result.items() if k!='archives'},'archives':[
 {k:v for k,v in e.items() if k!='contents'} for e in entries]},ensure_ascii=False,indent=2))
