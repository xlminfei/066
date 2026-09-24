"""Publish the user-authorized v4 release. Credentials remain in memory only."""
import argparse,hashlib,json,subprocess,urllib.request,urllib.error,urllib.parse
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('repository',type=Path);ap.add_argument('commit')
ap.add_argument('archive_directory',type=Path);a=ap.parse_args();repo=a.repository.resolve()
base='https://api.github.com/repos/xlminfei/066'
credential=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',
 cwd=repo,text=True,capture_output=True,check=True)
fields=dict(line.split('=',1) for line in credential.stdout.splitlines() if '=' in line)
token=fields.get('password')
if not token:raise RuntimeError('GitHub credential unavailable')
def request(method,url,obj=None,data=None,content_type='application/json'):
    if obj is not None:data=json.dumps(obj,ensure_ascii=False).encode('utf-8')
    req=urllib.request.Request(url,data=data,method=method,headers={
      'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json',
      'Content-Type':content_type,'User-Agent':'v4-publication','X-GitHub-Api-Version':'2022-11-28'})
    with urllib.request.urlopen(req,timeout=180) as response:return json.load(response)
try:release=request('GET',base+'/releases/tags/v4')
except urllib.error.HTTPError as e:
    if e.code!=404:raise
    release=request('POST',base+'/releases',obj={'tag_name':'v4','target_commitish':a.commit,
      'name':'v4 — 单组合发表代码与完整验证','draft':True,'prerelease':False,
      'body':'记录等权训练 × 物种等权评价；两路线、Null/M1/M2/M3、冻结五折与十折。30项检验按路线、指标、CV设计和训练评价组合分成10组三项BH。代码包可独立运行；完整验证档案含全部中间文件与原生合成对象。\n\n新128项研究数据拟合未执行。详见仓库 v4/README.md、v4/CHANGELOG_zh.md 和 validation/v4/VALIDATION_zh.md。'})
if release['tag_name']!='v4':raise RuntimeError('Unexpected release identity')
manifest=json.loads((repo/'releases/v4/archive-manifest.json').read_text(encoding='utf-8'))
paths=[a.archive_directory/e['name'] for e in manifest['archives']]
paths += [repo/'releases/v4/archive-manifest.json',repo/'releases/v4/verify_archives.py']
assets=request('GET',base+'/releases/'+str(release['id'])+'/assets?per_page=100')
by_name={x['name']:x for x in assets};receipts=[]
for path in paths:
    blob=path.read_bytes();digest='sha256:'+hashlib.sha256(blob).hexdigest()
    existing=by_name.get(path.name)
    if existing:
        if existing.get('digest')!=digest or existing['size']!=len(blob):raise RuntimeError('Existing asset differs: '+path.name)
        result=existing
    else:
        print('UPLOAD_START',path.name,len(blob),flush=True)
        result=request('POST','https://uploads.github.com/repos/xlminfei/066/releases/'+str(release['id'])+
          '/assets?name='+urllib.parse.quote(path.name),data=blob,content_type='application/octet-stream')
    if result.get('digest')!=digest or result['size']!=len(blob) or result['state']!='uploaded':
        raise RuntimeError('Asset verification mismatch: '+path.name)
    receipts.append({k:result.get(k) for k in ['id','name','size','state','digest','browser_download_url']})
    print('UPLOAD_VERIFIED',path.name,flush=True)
release=request('PATCH',base+'/releases/'+str(release['id']),obj={'draft':False})
record={'status':'PUBLISHED_ASSETS_VERIFIED','tag':'v4','commit':a.commit,'release_id':release['id'],
        'release_url':release['html_url'],'assets':receipts}
(repo/'releases/v4/delivery/release_upload.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in record.items() if k!='assets'},ensure_ascii=False,indent=2))
