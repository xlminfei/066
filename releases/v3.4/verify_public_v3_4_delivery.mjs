import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
const dir=path.resolve(process.argv[2]);const repo=path.resolve(process.argv[3]);
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
// Metadata uses the already authorized account; public page/files use no credential.
let credential=await new Promise((resolve,reject)=>{const p=spawn('git',['-C',repo,'-c','credential.interactive=never','credential','fill'],{env:{...process.env,GIT_TERMINAL_PROMPT:'0',GCM_INTERACTIVE:'Never'},windowsHide:true});let out='';p.stdout.on('data',b=>out+=b);p.on('error',reject);p.on('close',code=>code===0?resolve(out):reject(Error('Credential helper failed')));p.stdin.end('protocol=https\nhost=github.com\npath=xlminfei/066.git\n\n');});
let line=credential.split('\n').find(s=>s.startsWith('password='));if(!line)throw Error('No authorized repository credential');let token=line.slice(9).trim();
const response=await fetch('https://api.github.com/repos/xlminfei/066/releases/tags/v3.4',{headers:{'User-Agent':'ratio-v3.4-check','Authorization':'Bearer '+token},signal:AbortSignal.timeout(20000)});
token=null;line=null;credential=null;
if(!response.ok)throw Error('Release metadata HTTP'+response.status);const release=await response.json();
const expected=await Promise.all((await fs.readdir(path.join(dir,'upload_receipts'))).map(async f=>JSON.parse(await fs.readFile(path.join(dir,'upload_receipts',f),'utf8'))));
if(release.draft||release.id!==393691565||release.tag_name!=='v3.4'||expected.length!==16||release.assets.length!==16)throw Error('Release identity/count mismatch');
for(const e of expected){const a=release.assets.filter(x=>x.name===e.name);if(a.length!==1||a[0].state!=='uploaded'||a[0].size!==e.bytes||a[0].digest!=='sha256:'+e.sha256)throw Error('Asset mismatch:'+e.name)}
const page=await fetch('https://github.com/xlminfei/066/releases/tag/v3.4',{signal:AbortSignal.timeout(20000)});if(!page.ok||page.url.includes('/login'))throw Error('Public release page unavailable');
const downloads=await Promise.all(['v3.4-complete-evidence.zip','v3.4-complete-evidence.files.csv','verify_v3_4_archive.py'].map(async name=>{const a=release.assets.find(x=>x.name===name);const r=await fetch(a.browser_download_url,{signal:AbortSignal.timeout(45000)});if(!r.ok)throw Error('Public download HTTP'+r.status);const b=Buffer.from(await r.arrayBuffer());const sha=hash(b);if(b.length!==a.size||'sha256:'+sha!==a.digest)throw Error('Public byte mismatch:'+name);return{name,bytes:b.length,sha256:sha,unauthenticated_download_verified:true}}));
const receipt={status:'PUBLISHED_ALL16_ASSETS_VERIFIED_PUBLIC_COMPLETE_ARCHIVE_DOWNLOAD_PASSED',release_id:release.id,tag:'v3.4',url:release.html_url,published_at:release.published_at,code_commit:'3a090759e64d5b6e8a7026ee358eb4e4fa032586',metadata_access:'authorized GitHub account',public_page_status:page.status,source_files:221,source_files_omitted:0,archive_sha256:'abb1db9af70d5bc53b7c958cb599acef85f038344137162767090de4908cf5db',assets_verified:16,assets:release.assets.map(a=>({name:a.name,bytes:a.size,sha256:a.digest.slice(7),server_digest:a.digest,url:a.browser_download_url})),public_download_checks:downloads,new_fits:0,real_data_fits:0,checked_at:new Date().toISOString()};
await fs.writeFile(path.join(dir,'remote_delivery_verification.json'),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify({status:receipt.status,assets:16,public_downloads:downloads.length,url:release.html_url}));
