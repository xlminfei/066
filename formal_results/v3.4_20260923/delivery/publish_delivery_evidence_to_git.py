import csv,hashlib,io,json,sys,zipfile
from pathlib import Path,PurePosixPath
w=Path(sys.argv[1]);dest=Path(sys.argv[2]);dest.mkdir(parents=True,exist_ok=True);verified=0
with zipfile.ZipFile(w/'public_delivery_evidence.zip') as z:
 rows=list(csv.DictReader(io.StringIO(z.read('_archive/CONTENTS.csv').decode('utf-8'))))
 for r in rows:
  b=z.read(r['Path'])
  if len(b)!=int(r['Bytes']) or hashlib.sha256(b).hexdigest()!=r['SHA256']:raise RuntimeError('Public delivery file mismatch')
  verified+=1
 for n in z.namelist():
  p=PurePosixPath(n)
  if p.is_absolute() or '..' in p.parts or any(':' in s for s in p.parts):raise RuntimeError('Unsafe delivery path')
  target=(dest/Path(*p.parts)).resolve()
  if not target.is_relative_to(dest.resolve()):raise RuntimeError('Unsafe delivery destination')
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(n))
result={'status':'PASS','source':'anonymous public GitHub Release download','delivery_files_verified':verified,'sha256':hashlib.sha256((w/'public_delivery_evidence.zip').read_bytes()).hexdigest()}
(w/'final_delivery_public_readback.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result,indent=2))
