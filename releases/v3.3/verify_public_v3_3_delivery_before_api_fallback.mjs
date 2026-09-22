import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
const dir=path.resolve(process.argv[2]||'.');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const response=await fetch('https://api.github.com/repos/xlminfei/066/releases/tags/v3.3',{headers:{'User-Agent':'ratio-v3.3-check'},signal:AbortSignal.timeout(20000)});
if(!response.ok)throw Error('Release HTTP'+response.status);
const release=await response.json();
const expected=await Promise.all((await fs.readdir(path.join(dir,'upload_receipts'))).map(async f=>JSON.parse(await fs.readFile(path.join(dir,'upload_receipts',f),'utf8'))));
if(release.draft||release.id!==393624027||release.tag_name!=='v3.3'||expected.length!==57||release.assets.length!==57)throw Error('Public identity/count mismatch');
for(const e of expected){const aa=release.assets.filter(a=>a.name===e.name);if(aa.length!==1||aa[0].state!=='uploaded'||aa[0].size!==e.bytes||aa[0].digest!=='sha256:'+e.sha256)throw Error('Public asset mismatch:'+e.name)}
const checks=await Promise.all(['v3.3-complete-evidence.zip.part001','v3.3-complete-evidence.zip.part040','v3.3-complete-evidence.parts.json'].map(async name=>{const a=release.assets.find(x=>x.name===name);const r=await fetch(a.browser_download_url,{signal:AbortSignal.timeout(45000)});if(!r.ok)throw Error('Download HTTP'+r.status);const b=Buffer.from(await r.arrayBuffer());const sha=hash(b);if(b.length!==a.size||'sha256:'+sha!==a.digest)throw Error('Byte mismatch:'+name);return{name,bytes:b.length,sha256:sha,unauthenticated_download_verified:true}}));
const receipt={status:'PUBLISHED_ALL57_ASSETS_PUBLICLY_VERIFIED',release_id:release.id,tag:'v3.3',url:release.html_url,published_at:release.published_at,code_commit:'d3a6571d476fc33656b3a998c797b3d552f56da7',source_files:277,native_RDS_files:33,source_files_omitted:0,archive_bytes:656142878,archive_sha256:'5fc2b56e7583ad0d8f5ea3a62c788438f39bf9d163c01fb934b932e50981492e',assets_verified:expected.length,assets:release.assets.map(a=>({name:a.name,bytes:a.size,sha256:a.digest.slice(7),server_digest:a.digest,url:a.browser_download_url})),public_download_checks:checks,new_posterior_fits:0,formal_research_fits:0,checked_at:new Date().toISOString()};
await fs.writeFile(path.join(dir,'remote_delivery_verification.json'),JSON.stringify(receipt,null,2)+String.fromCharCode(10));
console.log(JSON.stringify({status:receipt.status,assets:expected.length,public_byte_downloads:checks.length,url:release.html_url}));
