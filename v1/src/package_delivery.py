"""Package only a fully audited run; keep all fits in the full directory and a smaller replay ZIP."""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import shutil
import zipfile

root=Path(__file__).resolve().parents[1]
workspace=root.parents[1]
destination=workspace/"outputs"/"ratio_analysis_20260914"
parser=argparse.ArgumentParser()
parser.add_argument("--audit",required=True,help="Final machine-readable audit JSON whose status is PASS")
parser.add_argument("--dry-run",action="store_true")
options=parser.parse_args()
audit_path=Path(options.audit).resolve()
audit=json.loads(audit_path.read_text(encoding="utf-8"))
if audit.get("status")!="PASS":raise RuntimeError("Final audit has not passed; do not publish an apparently complete package.")
if (audit.get("version")!="formal_acceptance_20260914_v1" or audit.get("complete") is not True
    or Path(audit.get("analysis_root","")).resolve()!=root
    or audit.get("run")!="runs/formal_20260914_26e686af86fa"
    or not audit.get("checks") or any(item.get("Status")!="PASS" for item in audit["checks"])
    or not audit.get("files_hashed")):
    raise RuntimeError("The supplied PASS is not the complete, current formal-run acceptance report.")
for relative,expected_hash in audit["files_hashed"].items():
    evidence=(root/relative).resolve()
    if not evidence.is_relative_to(root):raise RuntimeError("Audit evidence is outside this analysis directory")
    with evidence.open("rb") as handle:current_hash=hashlib.file_digest(handle,"sha256").hexdigest()
    if current_hash!=expected_hash:raise RuntimeError(f"Evidence changed after final acceptance: {relative}")
if not destination.resolve().is_relative_to((workspace/"outputs").resolve()):raise RuntimeError("Unexpected delivery path")
allowed_dirs={"input","source_snapshot","manual","provenance","environment","review","scripts","derived","figures","figure_data","runs","logs"}
exclude_parts={"_runtime","_mplconfig","__pycache__","io_probe"}
exclude_names={"runtime_replay_test.log"}
payload=[]
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():continue
    rel=path.relative_to(root)
    if rel.parts[0] not in allowed_dirs and path.parent!=root:continue
    if any(part in exclude_parts for part in rel.parts) or path.name in exclude_names:continue
    if ".tmp" in path.name or path.suffix in {".pyc",".lock"}:continue
    payload.append((path,rel))
total=sum(path.stat().st_size for path,_ in payload)
required=sum(path.stat().st_size for path,rel in payload if not (destination/rel).exists())
if shutil.disk_usage(workspace).free<required+10*1024**3:raise RuntimeError("Not enough free space for the complete artifact directory")
summary=dict(files=len(payload),full_directory_bytes=total,additional_copy_bytes=required,destination=str(destination))
print(json.dumps(summary,ensure_ascii=False,indent=2),flush=True)
if options.dry_run:raise SystemExit(0)
def digest(path):
    with path.open("rb") as handle:return hashlib.file_digest(handle,"sha256").hexdigest()
rows=[]
for source,rel in sorted(payload,key=lambda item:item[1].as_posix()):
    target=destination/rel
    target.parent.mkdir(parents=True,exist_ok=True)
    source_hash=digest(source)
    if target.exists():
        if digest(target)!=source_hash:raise RuntimeError(f"Existing output has different content; preserve and resolve: {rel}")
    else:shutil.copy2(source,target)
    if target.stat().st_size!=source.stat().st_size or digest(target)!=source_hash:raise RuntimeError(f"Copy verification failed: {rel}")
    rows.append(dict(File=rel.as_posix(),Bytes=source.stat().st_size,SHA256=source_hash))
manifest=destination/"DELIVERY_MANIFEST.csv"
with manifest.open("w",encoding="utf-8",newline="") as handle:
    writer=csv.DictWriter(handle,fieldnames=["File","Bytes","SHA256"]);writer.writeheader();writer.writerows(rows)
(destination/"DELIVERY_MANIFEST.sha256").write_text(digest(manifest)+"  DELIVERY_MANIFEST.csv\n",encoding="utf-8")

# Complete posterior objects remain in the full delivery folder. The ZIP is the portable figure/data/code set.
archive=workspace/"outputs"/"ratio_analysis_20260914_figures_data_code.zip"
if archive.exists():raise RuntimeError("A delivery ZIP already exists; do not silently replace it")
zip_members=[]
with zipfile.ZipFile(archive,"x",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as bundle:
    for row in rows:
        rel=Path(row["File"])
        if rel.suffix.lower() in {".rds",".rdata",".so",".dll"}:continue
        bundle.write(destination/rel,"ratio_analysis_20260914/"+rel.as_posix())
        zip_members.append(row)
    bundle.write(manifest,"ratio_analysis_20260914/DELIVERY_MANIFEST.csv")
    bundle.write(destination/"DELIVERY_MANIFEST.sha256","ratio_analysis_20260914/DELIVERY_MANIFEST.sha256")
    bundle.writestr("ratio_analysis_20260914/ZIP_CONTENTS_NOTE.txt",
        "This ZIP contains figures, source data, code, notes and manifests. Full RDS posterior objects are in the full delivery directory, not in this ZIP. DELIVERY_MANIFEST describes that full directory.\n")
    bundle.writestr("ratio_analysis_20260914/ZIP_MANIFEST.json",json.dumps(zip_members,ensure_ascii=False,indent=2))
with zipfile.ZipFile(archive) as bundle:
    for row in zip_members:
        raw=bundle.read("ratio_analysis_20260914/"+row["File"])
        if len(raw)!=row["Bytes"] or hashlib.sha256(raw).hexdigest()!=row["SHA256"]:raise RuntimeError("ZIP readback mismatch")
result=dict(status="PASS",full_directory=str(destination),full_files=len(rows),zip=str(archive),
            zip_sha256=digest(archive),zip_data_files=len(zip_members),final_audit=str(audit_path))
(workspace/"outputs"/"ratio_analysis_20260914_delivery_check.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(result,ensure_ascii=False,indent=2))
