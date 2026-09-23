import csv,hashlib,io,json,os,shutil,sys,time,zipfile
from pathlib import Path
from datetime import datetime,timezone
run=Path(sys.argv[1]);work=Path(sys.argv[2]);browse=Path(sys.argv[3]);assets=work/'assets'
assets.mkdir(exist_ok=True);snapshot=browse/'snapshot';snapshot.mkdir(parents=True,exist_ok=True)
inv=json.loads((work/'source_inventory_before_hash.json').read_text(encoding='utf-8'))
entries=inv['files'];rows=[];start=time.time()
full=assets/'v3.4-formal-complete.zip';quick=assets/'v3.4-formal-results-light.zip'
if full.exists() or quick.exists():raise SystemExit('Refusing to replace an existing archive; inspect previous attempt first')
def dumpcsv(rows):
 s=io.StringIO(newline='');w=csv.DictWriter(s,fieldnames=['Path','Bytes','SHA256','Category','GitMirror']);w.writeheader();w.writerows(rows);return s.getvalue().encode('utf-8')
def category(p):
 if p.endswith('/fit.rds'):return 'formal_native_fit'
 if p.startswith('run_logs_'):return 'run_logs_and_postrun_verification'
 if p.startswith('quantitative_metric_'):return 'metric_figures_interpretation_and_intermediates'
 if '/results/' in p:return 'formal_results_or_test_results'
 if '/figures/' in p:return 'figures_or_plot_sources'
 if '/runs/' in p:return 'prepared_state_plans_and_runtime_intermediates'
 if '/review/' in p:return 'audits_tests_and_review_evidence'
 return 'source_configuration_inputs_documentation'
with zipfile.ZipFile(full,'w',allowZip64=True,compression=zipfile.ZIP_DEFLATED,compresslevel=6) as zf,zipfile.ZipFile(quick,'w',allowZip64=True,compression=zipfile.ZIP_DEFLATED,compresslevel=6) as zq:
 for i,e in enumerate(entries,1):
  rel=e['path'];p=run/rel;before=p.stat()
  if before.st_size!=e['bytes']:raise RuntimeError('Source size changed: '+rel)
  fit=rel.endswith('/fit.rds');h=hashlib.sha256();zi=zipfile.ZipInfo.from_file(p,arcname=rel);zi.compress_type=zipfile.ZIP_STORED if fit else zipfile.ZIP_DEFLATED
  if fit:
   with p.open('rb') as src,zf.open(zi,'w',force_zip64=True) as dst:
    while True:
     chunk=src.read(8*1024*1024)
     if not chunk:break
     h.update(chunk);dst.write(chunk)
  else:
   b=p.read_bytes();h.update(b);zf.writestr(zi,b,compresslevel=6);zq.writestr(zi,b,compresslevel=6)
   target=snapshot/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b)
  after=p.stat()
  if before.st_size!=after.st_size or before.st_mtime_ns!=after.st_mtime_ns:raise RuntimeError('Source modified during archive: '+rel)
  rows.append(dict(Path=rel,Bytes=before.st_size,SHA256=h.hexdigest(),Category=category(rel),GitMirror='' if fit else 'snapshot/'+rel))
  if i%64==0 or i==len(entries):print(f'ARCHIVE_FILES {i}/{len(entries)} bytes={sum(int(r["Bytes"]) for r in rows)}',flush=True)
 csvdata=dumpcsv(rows);(assets/'v3.4-formal-files.csv').write_bytes(csvdata);(browse/'files.csv').write_bytes(csvdata)
 meta=dict(source_commit='c9ec1c58e173dd5209bbbe5e89b2213553fc0630',source_files=len(rows),source_bytes=sum(int(r['Bytes']) for r in rows),native_fit_files=sum(r['Category']=='formal_native_fit' for r in rows),status='COMPLETE_WITH_REVIEW_FLAGS',formal_audit='PASS',ppc_review_flags=18,root_selection=inv['selections'],excluded_source_files=0)
 for z,kind in [(zf,'complete'),(zq,'light_without_256_native_fit_objects')]:
  z.writestr('_archive/CONTENTS.csv',csvdata)
  z.writestr('_archive/ARCHIVE_INFO.json',json.dumps(dict(meta,archive_kind=kind),ensure_ascii=False,indent=2)+'\n')
  z.writestr('_archive/README.txt','The complete archive preserves every selected source file byte-for-byte. The light archive contains every file except the 256 native fit.rds objects. Restore instructions and SHA256 manifest are separate Release assets. Historical NOT_RUN and synthetic diagnostics remain provenance; current formal status is v3.4/review/final_v3_status.json.\n')
# Verify every source entry by reading back the actual archive; ZipFile also checks CRC.
verify=[]
for p,selected in [(full,rows),(quick,[r for r in rows if r['Category']!='formal_native_fit'])]:
 with zipfile.ZipFile(p) as z:
  wanted={r['Path'] for r in selected};names=z.namelist()
  if len(names)!=len(set(names)) or {n for n in names if not n.startswith('_archive/')}!=wanted:raise RuntimeError('Archive entry set mismatch')
  for i,r in enumerate(selected,1):
   h=hashlib.sha256();n=0
   with z.open(r['Path']) as src:
    while True:
     b=src.read(8*1024*1024)
     if not b:break
     n+=len(b);h.update(b)
   if n!=int(r['Bytes']) or h.hexdigest()!=r['SHA256']:raise RuntimeError('Archive file mismatch '+r['Path'])
   if i%128==0 or i==len(selected):print(f'ARCHIVE_READBACK {p.name} {i}/{len(selected)}',flush=True)
  verify.append(dict(archive=p.name,verified_source_files=len(selected),all_sha256_and_crc_match=True))
# Fixed-size binary parts, each safely under the GitHub per-asset cap.
part_size=64*1024*1024;parts=[];whole=hashlib.sha256()
with full.open('rb') as f:
 i=0
 while True:
  b=f.read(part_size)
  if not b:break
  i+=1;whole.update(b);name=f'v3.4-formal-complete.zip.part{i:04d}';(assets/name).write_bytes(b)
  parts.append(dict(name=name,bytes=len(b),sha256=hashlib.sha256(b).hexdigest()))
  if i%16==0:print(f'ARCHIVE_PARTS {i}',flush=True)
qh=hashlib.sha256(quick.read_bytes()).hexdigest()
manifest=dict(schema_version=1,release_tag='v3.4-formal-results',repository='xlminfei/066',source=meta,archive=dict(name=full.name,bytes=full.stat().st_size,sha256=whole.hexdigest()),part_size=part_size,parts=parts,light_archive=dict(name=quick.name,bytes=quick.stat().st_size,sha256=qh),files_manifest=dict(name='v3.4-formal-files.csv',sha256=hashlib.sha256(csvdata).hexdigest()),archive_metadata_entries=3)
for dest in [assets/'v3.4-formal-archive-manifest.json',browse/'archive-manifest.json']:dest.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
receipt=dict(status='PASS',readback=verify,source_files=len(rows),native_fit_files=256,source_bytes=meta['source_bytes'],archive_bytes=full.stat().st_size,archive_sha256=whole.hexdigest(),parts=len(parts),light_bytes=quick.stat().st_size,elapsed_seconds=time.time()-start,completed_at=datetime.now(timezone.utc).isoformat())
(work/'archive_build_validation.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8');shutil.copyfile(work/'archive_build_validation.json',browse/'archive_build_validation.json');print(json.dumps(receipt,indent=2),flush=True)
