import hashlib,importlib.util,json,sys,time,urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
w=Path(sys.argv[1]);assets=w/'assets';directory=w/'public_part_samples';directory.mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('restorer',assets/'restore_v3_4_formal.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
meta=json.loads((assets/'v3.4-formal-archive-manifest.json').read_text(encoding='utf-8'))
parts=[meta['parts'][i] for i in [0,len(meta['parts'])//2,len(meta['parts'])-1]]
def one(p):
 result=m.fetch(p['name'],directory/p['name'],p['sha256'],p['bytes'],False)
 return dict(name=p['name'],bytes=p['bytes'],sha256=p['sha256'],status=result)
with ThreadPoolExecutor(max_workers=3) as pool:verified=list(pool.map(one,parts))
restore_sha=hashlib.sha256((assets/'restore_v3_4_formal.py').read_bytes()).hexdigest();m.fetch('restore_v3_4_formal.py',directory/'restore_v3_4_formal.py',restore_sha,offline=False)
req=urllib.request.Request('https://github.com/xlminfei/066/releases/tag/v3.4-formal-results',headers={'User-Agent':'ratio-formal-public-verifier'})
with urllib.request.urlopen(req,timeout=120) as resp:code=resp.status;page=resp.read()
if code!=200:raise RuntimeError('Public release page not accessible')
light=json.loads((w/'public_light_download'/'restore_verification.json').read_text(encoding='utf-8'))
if light['status']!='PASS' or light['offline'] or light['verified_source_files']!=522:raise RuntimeError('Public light restore not verified')
report=dict(status='PASS',requests_authenticated=False,release_page_http=code,public_light_archive_source_files_verified=522,public_light_archive_sha256=light['archive']['sha256'],sampled_full_parts=verified,restore_script_public_sha256=restore_sha,full_archive_verification_boundary='All 170 parts have server SHA256/size verification and the full archive was locally assembled/read back for 778 files. Public HTTP downloads verified the light archive and first/middle/last data parts, not a second download of every full part.')
(w/'public_download_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,indent=2))
