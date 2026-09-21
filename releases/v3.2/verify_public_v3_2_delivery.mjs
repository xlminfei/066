import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
const dir=path.resolve(process.argv[2]||'.');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const response=await fetch('https://api.github.com/repos/xlminfei/066/releases/tags/v3.2',{headers:{'User-Agent':'ratio-v3.2-check'},signal:AbortSignal.timeout(15000)});
if(!response.ok)throw Error('Release HTTP '+response.status);
const release=await response.json();
const expected=await Promise.all((await fs.readdir(path.join(dir,'upload_receipts'))).map(async f=>JSON.parse(await fs.readFile(path.join(dir,'upload_receipts',f),'utf8'))));
if(release.draft||release.id!==393166329||release.assets.length!==80||expected.length!==80)throw Error('Public identity/count mismatch');
for(const e of expected){const matches=release.assets.filter(a=>a.name===e.name);if(matches.length!==1||matches[0].state!=='uploaded'||matches[0].size!==e.bytes||matches[0].digest!=='sha256:'+e.sha256)throw Error('Public mismatch '+e.name)}
const checks=await Promise.all(['v3.2-complete-evidence.zip.part001','v3.2-complete-evidence.zip.part061','v3.2-complete-evidence.parts.json'].map(async name=>{const a=release.assets.find(x=>x.name===name);const r=await fetch(a.browser_download_url,{signal:AbortSignal.timeout(45000)});if(!r.ok)throw Error('Download HTTP'+r.status);const b=Buffer.from(await r.arrayBuffer());const sha=hash(b);if(b.length!==a.size||'sha256:'+sha!==a.digest)throw Error('Download mismatch '+name);return{name,bytes:b.length,sha256:sha}}));
console.log(JSON.stringify({status:'PUBLIC80_METADATA_AND3_DOWNLOADS_VERIFIED',release:release.html_url,checks},null,2));
