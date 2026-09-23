#!/usr/bin/env python3
"""Read-only byte-level checks for the v3.4 P-value supplement; no model execution."""
import argparse, csv, hashlib, json, re
from pathlib import Path
from urllib.parse import unquote
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def rows(p):
    with p.open(encoding="utf-8-sig", newline="") as f: return list(csv.DictReader(f))
def safe(root, rel):
    p=(root/rel.replace("\\","/")).resolve()
    if not p.is_relative_to(root.resolve()): raise ValueError("Unsafe path: "+rel)
    return p
def verify(root):
    manifest=rows(root/"PAYLOAD_FILES.csv")
    for r in manifest:
        p=safe(root,r["Path"])
        assert p.is_file(), r["Path"]
        assert p.stat().st_size==int(r["Bytes"]), r["Path"]
        assert sha(p)==r["SHA256"], r["Path"]
    copies=rows(root/"SOURCE_FILES.csv")
    for r in copies:
        p=safe(root,r["Path"])
        assert sha(p)==r["SHA256"] and p.stat().st_size==int(r["Bytes"]),r["Path"]
    source_count=0
    for folder,name in [("source/elpd_audit","AUDIT_FILE_MANIFEST.csv"),
                        ("source/additional_metrics","FILE_MANIFEST.csv")]:
        base=root/folder
        rr=rows(base/name)
        declared={r["Path"].replace("\\","/") for r in rr}
        actual={p.relative_to(base).as_posix() for p in base.rglob("*") if p.is_file() and p.name!=name}
        assert declared==actual,(folder,declared^actual)
        for r in rr:
            p=safe(base,r["Path"])
            assert sha(p)==r["SHA256"] and p.stat().st_size==int(r["Bytes"]),r["Path"]
        source_count+=len(rr)+1
    formal=root/"context/v3.4"
    derived=rows(formal/"review/derived_outputs_manifest.csv")
    for r in derived: assert sha(safe(formal,r["Path"]))==r["SHA256"],r["Path"]
    plan=json.loads((root/"source/additional_metrics/ANALYSIS_PLAN.json").read_text(encoding="utf-8"))
    for name,digest in plan["source_hashes"].items():
        assert sha(formal/"results"/name)==digest,name
    checked_links=0
    for name in ["README.md","REPRODUCE_zh.md","ELPD_P_VALUES_zh.md","AUC_MAE_RMSE_P_VALUES_zh.md"]:
        text=(root/name).read_text(encoding="utf-8")
        for dest in re.findall(r"\]\(([^)]+)\)",text):
            if dest.startswith(("http:","https:","#","mailto:")): continue
            assert not re.match(r"[A-Za-z]:",dest),(name,dest)
            dest=unquote(dest.split("#")[0])
            if dest.startswith(("archive/","delivery/")) or dest=="archive_manifest.json":continue
            assert safe(root,dest).exists(),(name,dest)
            checked_links+=1
    return dict(status="PASS",payload_files=len(manifest),copied_files=len(copies),
                original_analysis_files=source_count,formal_derived_files=len(derived),
                source_prediction_hashes=len(plan["source_hashes"]),
                local_links_checked=checked_links,new_fits=0,scientific_values_changed=False)
if __name__=="__main__":
    ap=argparse.ArgumentParser();ap.add_argument("directory",type=Path,nargs="?",default=Path("."));args=ap.parse_args()
    print(json.dumps(verify(args.directory.resolve()),ensure_ascii=False,indent=2))
