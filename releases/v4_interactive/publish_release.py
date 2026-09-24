"""Publish the authorized v4 interactive update; keep credentials in memory."""
import argparse,hashlib,json,subprocess,urllib.request,urllib.error,urllib.parse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ap=argparse.ArgumentParser();ap.add_argument('repository',type=Path);ap.add_argument('commit');ap.add_argument('archives',type=Path)
a=ap.parse_args();repo=a.repository.resolve();folder=repo/'releases/v4_interactive';tag='v4-interactive'
meta=json.loads((folder/'archive-manifest.json').read_text(encoding='utf-8'))
raw=subprocess.run(['git','credential','fill'],cwd=repo,input='protocol=https\nhost=github.com\n\n',text=True,capture_output=True,check=True)
token=dict(x.split('=',1) for x in raw.stdout.splitlines() if '=' in x).get('password')
if not token:raise RuntimeError('GitHub credential unavailable')
base='https://api.github.com/repos/xlminfei/066'
def req(method,url,obj=None,data=None):
    if obj is not None:data=json.dumps(obj,ensure_ascii=False).encode('utf-8')
    request=urllib.request.Request(url,data=data,method=method,headers={
      'Authorization':'Bearer '+token,'User-Agent':'v4-interactive-publisher',
      'Accept':'application/vnd.github+json','Content-Type':'application/json' if obj is not None else 'application/octet-stream',
      'X-GitHub-Api-Version':'2022-11-28'})
    with urllib.request.urlopen(request,timeout=180) as response:return json.load(response)
try:r=req('GET',base+'/releases/tags/'+tag)
except urllib.error.HTTPError as e:
    if e.code!=404:raise
    r=req('POST',base+'/releases',obj={'tag_name':tag,'target_commitish':a.commit,
      'name':'v4：逐行中文注释的R交互入口','draft':True,'prerelease':False,
      'body':"""v4增加Ubuntu R/RStudio中的逐行/逐段运行入口。原模型、四阶段、输入、设置、Stan和统计方法不变。
主文件145个代码行及支持工具97个代码行均有中文注释；展开一个正式CV任务，随后用原函数完成其余任务。
普通R无--file会话及两路线缓存重放通过；17项交互保护通过。本轮没有新增MCMC，完整回放的批量拟合使用明确替身。
下载v4-interactive-code.zip即可获得独立代码；完整验证档案为5个分卷，使用verify_archives.py和archive-manifest.json下载、合并和逐文件核验。
原v4标签和原附件保持不变。"""})
assets=req('GET',base+'/releases/'+str(r['id'])+'/assets?per_page=100')
existing={x['name']:x for x in assets}
paths=[]
for e in meta['archives']:
    paths.extend(a.archives/p['name'] for p in e.get('parts',[e]))
paths += [folder/'archive-manifest.json',folder/'verify_archives.py']
def upload(path):
    b=path.read_bytes();h='sha256:'+hashlib.sha256(b).hexdigest()
    if path.name in existing:
        result=existing[path.name]
    else:
        print('UPLOAD_START',path.name,len(b),flush=True)
        result=req('POST','https://uploads.github.com/repos/xlminfei/066/releases/'+str(r['id'])+
          '/assets?name='+urllib.parse.quote(path.name),data=b)
    if result.get('digest')!=h or result['size']!=len(b) or result['state']!='uploaded':
        raise RuntimeError('Asset mismatch: '+path.name)
    print('UPLOAD_VERIFIED',path.name,flush=True)
    return result
with ThreadPoolExecutor(max_workers=2) as executor:results=list(executor.map(upload,paths))
r=req('PATCH',base+'/releases/'+str(r['id']),obj={'draft':False})
final_assets=req('GET',base+'/releases/'+str(r['id'])+'/assets?per_page=100')
by_name={x['name']:x for x in final_assets}
receipts=[]
for path in paths:
    entry=by_name[path.name];digest='sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()
    assert entry['digest']==digest and entry['size']==path.stat().st_size
    receipts.append({k:entry.get(k) for k in ['id','name','size','state','digest','browser_download_url']})
record={'status':'PUBLISHED_AND_SERVER_VERIFIED','tag':tag,'commit':a.commit,'release_id':r['id'],
 'release_url':r['html_url'],'assets':receipts}
(folder/'delivery/release_upload.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in record.items() if k!='assets'},ensure_ascii=False,indent=2),flush=True)
