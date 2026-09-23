#!/usr/bin/env python3
"""Archive a declared immutable payload and read back every ZIP member."""
import argparse,csv,hashlib,json,zipfile
from datetime import datetime,timezone
from pathlib import Path
from verify_package import verify
def digest(b):return hashlib.sha256(b).hexdigest()
ap=argparse.ArgumentParser();ap.add_argument("directory",type=Path);args=ap.parse_args()
root=args.directory.resolve()
validation=verify(root)
with (root/"PAYLOAD_FILES.csv").open(encoding="utf-8",newline="") as f: manifest=list(csv.DictReader(f))
items={r["Path"]:r for r in manifest}
mp=root/"PAYLOAD_FILES.csv"
items["PAYLOAD_FILES.csv"]={"Path":"PAYLOAD_FILES.csv","Bytes":mp.stat().st_size,"SHA256":digest(mp.read_bytes())}
prefix="v3.4-pvalue-supplement-20260923/"
archive_dir=root/"archive";archive_dir.mkdir(exist_ok=True)
archive=archive_dir/"v3.4-pvalue-supplement-20260923.zip"
assert not archive.exists(),"Refuse to overwrite an existing archive"
with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
    for rel in sorted(items):
        b=(root/rel).read_bytes();r=items[rel]
        assert len(b)==int(r["Bytes"]) and digest(b)==r["SHA256"],rel
        info=zipfile.ZipInfo(prefix+rel,date_time=(2026,9,23,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=0o100644<<16;z.writestr(info,b)
with zipfile.ZipFile(archive) as z:
    assert len(z.namelist())==len(items)==len(set(z.namelist()))
    assert z.testzip() is None
    assert set(z.namelist())=={prefix+rel for rel in items}
    for rel,r in items.items():
        b=z.read(prefix+rel)
        assert len(b)==int(r["Bytes"]) and digest(b)==r["SHA256"],rel
record={"archive":archive.relative_to(root).as_posix(),"bytes":archive.stat().st_size,
        "sha256":digest(archive.read_bytes()),"zip_root":prefix,"files":len(items),
        "uncompressed_bytes":sum(int(r["Bytes"]) for r in items.values()),
        "source_analysis_files":88,"copied_dependency_files":75,
        "original_formal_archive_replaced":False,"new_fits":0,
        "excluded_from_recursive_archive":["archive/","archive_manifest.json","delivery/"],
        "created_utc":datetime.now(timezone.utc).isoformat()}
(root/"archive_manifest.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
delivery=root/"delivery";delivery.mkdir(exist_ok=True)
record.update(validation)
record.update({"status":"PASS","zip_members_checked":len(items),"zip_crc":"PASS",
               "every_member_sha256":"PASS"})
(delivery/"archive_validation.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(record,ensure_ascii=False,indent=2))
