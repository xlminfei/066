import csv,hashlib,io,json,sys,zipfile
from pathlib import Path
w=Path(sys.argv[1]);assets=w/'assets';selected=[]
base_names=['source_inventory_before_hash.json','build_complete_archive.py','archive_build.log','archive_build_exit.json','archive_build_validation.json','archive_zipinfo_regression.py','archive_zipinfo_regression.log','upload_formal_asset.ps1','upload_batch.ps1','upload_plan.json','upload_batch.log','upload_batch_result.json','probe_upload.log','verify_git_mirror.py','git_mirror_validation.log','git_index_validation.json','remote_git_validation.json','results_commit.json','git_push_results.log','git_push_results_exit.json','release_created.json','RELEASE_NOTES_zh.md','refresh_repository_manifest.py','local_restore_test.log','local_restore_test_exit.json','remote_primary_assets_verified.json','public_download_validation.json','verify_remote_primary_assets.ps1','verify_public_downloads.py','public_download_check.log','public_light_download.log','public_download_check_exit.json','release_published.json','remote_primary_assets_verification.log','build_delivery_evidence.py','source_freeze_final_check.json']
for n in base_names:
 p=w/n
 if p.is_file():selected.append((n,p))
for sub in ['upload_logs','upload_receipts']:
 for p in sorted((w/sub).rglob('*')):
  if p.is_file():selected.append((p.relative_to(w).as_posix(),p))
for n in ['build_complete_archive.py','archive_build.log','archive_build_exit.json']:
 p=w/'archive_attempt1'/n
 if p.is_file():selected.append(('archive_attempt1/'+n,p))
for rel in ['local_restore_test/restore_verification.json','public_light_download/restore_verification.json']:
 p=w/rel
 if p.is_file():selected.append((rel,p))
selected.append(('restore_v3_4_formal.py',assets/'restore_v3_4_formal.py'))
archive=assets/'v3.4-formal-delivery-evidence.zip';manifest=[]
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for rel,p in selected:
  b=p.read_bytes();z.writestr(rel,b);manifest.append(dict(Path=rel,Bytes=len(b),SHA256=hashlib.sha256(b).hexdigest()))
 s=io.StringIO(newline='');wr=csv.DictWriter(s,fieldnames=['Path','Bytes','SHA256']);wr.writeheader();wr.writerows(manifest);mb=s.getvalue().encode();z.writestr('_archive/CONTENTS.csv',mb)
 z.writestr('_archive/README.txt','Publication execution evidence. All 778 run-source files are preserved in the complete formal archive. Failed first packaging ZIPs were not published; the failure log, source and regression counterexample are retained here. This delivery archive cannot recursively contain its own later upload receipts, which are saved in Git after upload.\n')
with zipfile.ZipFile(archive) as z:
 for r in manifest:
  b=z.read(r['Path'])
  if len(b)!=r['Bytes'] or hashlib.sha256(b).hexdigest()!=r['SHA256']:raise RuntimeError('Delivery evidence verification failure')
(assets/'v3.4-formal-delivery-evidence.files.csv').write_bytes(mb)
receipt=dict(status='PASS',file_count=len(manifest),archive_bytes=archive.stat().st_size,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),all_files_readback_verified=True)
(assets/'v3.4-formal-delivery-evidence.build.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8');print(json.dumps(receipt,indent=2))
