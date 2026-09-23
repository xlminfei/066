#!/usr/bin/env python3
"""Download/verify the complete v3.4 formal record; no model execution."""
import argparse,csv,hashlib,io,json,os,shutil,stat,sys,time,urllib.error,urllib.request,zipfile
from pathlib import Path,PurePosixPath
from concurrent.futures import ThreadPoolExecutor,as_completed
MANIFEST_NAME='v3.4-formal-archive-manifest.json'
EXPECTED_MANIFEST_SHA256='ac686d33dd13d8422af314fe44730d1ecac762db4e5ea9491e58e2acd4aa966a'
BASE='https://github.com/xlminfei/066/releases/download/v3.4-formal-results/'
def hash_file(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()
def safe_name(name):
 if not name or '/' in name or '\\' in name or name in ['.','..']:raise ValueError('Unsafe asset name')
 return name
def fetch(name,path,expected_sha=None,expected_bytes=None,offline=False):
 safe_name(name)
 if path.exists() and (expected_bytes is None or path.stat().st_size==expected_bytes) and (expected_sha is None or hash_file(path)==expected_sha):return 'verified_existing'
 if offline:raise RuntimeError('Missing or mismatched offline file: '+str(path))
 tmp=path.with_name(path.name+'.download_tmp');last=None
 for attempt in range(1,5):
  try:
   req=urllib.request.Request(BASE+name,headers={'User-Agent':'v34-formal-archive-restorer','Accept':'application/octet-stream'})
   with urllib.request.urlopen(req,timeout=180) as response,tmp.open('wb') as f:
    shutil.copyfileobj(response,f,8*1024*1024)
   if expected_bytes is not None and tmp.stat().st_size!=expected_bytes:raise RuntimeError('Byte count mismatch '+name)
   if expected_sha is not None and hash_file(tmp)!=expected_sha:raise RuntimeError('SHA256 mismatch '+name)
   os.replace(tmp,path);return 'downloaded_and_verified'
  except Exception as e:
   last=e
   if attempt<4:time.sleep(min(20,3*attempt))
 raise RuntimeError('Download failed for '+name+': '+str(last))
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--directory',type=Path,default=Path('v3.4-formal-download'));ap.add_argument('--mode',choices=['full','light'],default='full');ap.add_argument('--offline',action='store_true');ap.add_argument('--workers',type=int,default=4);ap.add_argument('--extract-to',type=Path)
 args=ap.parse_args();d=args.directory;d.mkdir(parents=True,exist_ok=True);started=time.time()
 fetch(MANIFEST_NAME,d/MANIFEST_NAME,EXPECTED_MANIFEST_SHA256,offline=args.offline)
 meta=json.loads((d/MANIFEST_NAME).read_text(encoding='utf-8'));fm=meta['files_manifest']
 fetch(fm['name'],d/fm['name'],fm['sha256'],offline=args.offline)
 with (d/fm['name']).open(encoding='utf-8',newline='') as f:all_files=list(csv.DictReader(f))
 transfers=[]
 if args.mode=='full':
  parts=meta['parts']
  with ThreadPoolExecutor(max_workers=max(1,min(args.workers,8))) as pool:
   jobs={pool.submit(fetch,p['name'],d/p['name'],p['sha256'],p['bytes'],args.offline):p for p in parts}
   for future in as_completed(jobs):
    p=jobs[future];result=future.result();transfers.append(dict(name=p['name'],bytes=p['bytes'],status=result));print('PART_VERIFIED',len(transfers),'/',len(parts),p['name'],flush=True)
  arc=meta['archive'];archive=d/arc['name']
  if not archive.exists() or archive.stat().st_size!=arc['bytes'] or hash_file(archive)!=arc['sha256']:
   tmp=archive.with_name(archive.name+'.assemble_tmp');h=hashlib.sha256();total=0
   with tmp.open('wb') as dst:
    for p in parts:
     with (d/p['name']).open('rb') as src:
      for b in iter(lambda:src.read(8*1024*1024),b''):dst.write(b);h.update(b);total+=len(b)
   if total!=arc['bytes'] or h.hexdigest()!=arc['sha256']:raise RuntimeError('Assembled archive mismatch')
   os.replace(tmp,archive)
  selected=all_files
 else:
  arc=meta['light_archive'];archive=d/arc['name'];result=fetch(arc['name'],archive,arc['sha256'],arc['bytes'],args.offline);transfers=[dict(name=arc['name'],bytes=arc['bytes'],status=result)];selected=[x for x in all_files if x['Category']!='formal_native_fit']
 expected={r['Path']:r for r in selected}
 with zipfile.ZipFile(archive) as z:
  names=z.namelist()
  if len(names)!=len(set(names)) or set(names)-{'_archive/CONTENTS.csv','_archive/ARCHIVE_INFO.json','_archive/README.txt'}!=set(expected):raise RuntimeError('Archive entry universe mismatch')
  for i,(name,row) in enumerate(expected.items(),1):
   h=hashlib.sha256();n=0
   with z.open(name) as f:
    for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b);n+=len(b)
   if n!=int(row['Bytes']) or h.hexdigest()!=row['SHA256']:raise RuntimeError('Restored entry mismatch '+name)
   if i%128==0 or i==len(expected):print('FILE_VERIFIED',i,'/',len(expected),flush=True)
  if args.extract_to:
   target=args.extract_to.resolve()
   if target.exists() and any(target.iterdir()):raise RuntimeError('Extraction target must be empty; refusing to overwrite')
   target.mkdir(parents=True,exist_ok=True)
   for info in z.infolist():
    p=PurePosixPath(info.filename)
    if p.is_absolute() or '..' in p.parts or any(':' in part for part in p.parts) or '\\' in info.filename or stat.S_ISLNK(info.external_attr>>16):raise RuntimeError('Unsafe ZIP entry')
    destination=target.joinpath(*p.parts).resolve()
    if not destination.is_relative_to(target):raise RuntimeError('ZIP entry outside extraction target')
    destination.parent.mkdir(parents=True,exist_ok=True)
    with z.open(info) as src,destination.open('xb') as dst:shutil.copyfileobj(src,dst,8*1024*1024)
 report=dict(status='PASS',mode=args.mode,archive=arc,verified_source_files=len(selected),verified_native_fit_files=sum(x['Category']=='formal_native_fit' for x in selected),transfers=transfers,offline=args.offline,extracted_to=str(args.extract_to) if args.extract_to else None,elapsed_seconds=time.time()-started,new_model_computations=0)
 (d/'restore_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('RESTORE_VERIFY_PASS',len(selected),'source files; mode='+args.mode,flush=True)
if __name__=='__main__':main()
