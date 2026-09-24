"""Verify either release ZIP, optionally downloading it, using only Python's standard library."""
import argparse,hashlib,json,urllib.request,zipfile
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('manifest',type=Path);ap.add_argument('--directory',type=Path,default=Path('.'))
ap.add_argument('--download',action='store_true');ap.add_argument('--code-only',action='store_true');a=ap.parse_args()
manifest=json.loads(a.manifest.read_text(encoding='utf-8'));a.directory.mkdir(parents=True,exist_ok=True)
for entry in manifest['archives']:
    if a.code_only and entry['name']!='v4-code.zip':continue
    path=a.directory/entry['name']
    if a.download and not path.exists():
        req=urllib.request.Request(entry['url'],headers={'User-Agent':'v4-archive-verifier'})
        with urllib.request.urlopen(req,timeout=60) as response,path.open('wb') as f:
            while True:
                chunk=response.read(1024*1024)
                if not chunk:break
                f.write(chunk)
    assert path.stat().st_size==entry['bytes']
    assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256']
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        assert set(z.namelist())=={r['Path'] for r in entry['contents']}
        assert len(z.namelist())==entry['files']
        for r in entry['contents']:
            data=z.read(r['Path'])
            assert len(data)==r['Bytes'] and hashlib.sha256(data).hexdigest()==r['SHA256'],r['Path']
    print(entry['name']+': PASS ('+str(entry['files'])+' files)')
