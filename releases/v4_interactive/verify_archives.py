"""Download/restore the v4 interactive packages; verify bytes and every ZIP member."""
import argparse,hashlib,json,urllib.request,zipfile
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('manifest',type=Path);ap.add_argument('--directory',type=Path,default=Path('.'))
ap.add_argument('--download',action='store_true');ap.add_argument('--code-only',action='store_true');a=ap.parse_args()
meta=json.loads(a.manifest.read_text(encoding='utf-8'));a.directory.mkdir(parents=True,exist_ok=True)
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def ensure(e):
    p=a.directory/e['name']
    if a.download and not p.exists():
        req=urllib.request.Request(e['url'],headers={'User-Agent':'v4-interactive-archive-verifier'})
        with urllib.request.urlopen(req,timeout=60) as response,p.open('wb') as f:
            while True:
                b=response.read(1024*1024)
                if not b:break
                f.write(b)
    assert p.stat().st_size==e['bytes'] and sha(p)==e['sha256'],e['name']
    return p
for e in meta['archives']:
    if a.code_only and e['name']!='v4-interactive-code.zip':continue
    if 'parts' in e:
        parts=[ensure(part) for part in e['parts']]
        target=a.directory/e['name']
        if not target.exists():
            with target.open('wb') as f:
                for part in parts:
                    with part.open('rb') as s:
                        for b in iter(lambda:s.read(1024*1024),b''):f.write(b)
        assert target.stat().st_size==e['bytes'] and sha(target)==e['sha256']
    else:target=ensure(e)
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        assert len(z.namelist())==e['files']==len(set(z.namelist()))
        assert set(z.namelist())=={r['Path'] for r in e['contents']}
        for r in e['contents']:
            b=z.read(r['Path'])
            assert len(b)==r['Bytes'] and hashlib.sha256(b).hexdigest()==r['SHA256'],r['Path']
    print(e['name']+': PASS ('+str(e['files'])+' members)',flush=True)
