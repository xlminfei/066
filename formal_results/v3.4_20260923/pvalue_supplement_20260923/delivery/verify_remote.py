#!/usr/bin/env python3
"""Verify GitHub file identities and publicly download/read back the whole supplement ZIP."""
import argparse,csv,hashlib,io,json,subprocess,time,urllib.request,zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timezone
from pathlib import Path
def sha(b):return hashlib.sha256(b).hexdigest()
ap=argparse.ArgumentParser()
ap.add_argument("--repository",type=Path,required=True);ap.add_argument("--commit",required=True)
ap.add_argument("--package-relative",required=True);ap.add_argument("--downloads",type=Path,required=True)
a=ap.parse_args();a.downloads.mkdir(parents=True,exist_ok=True)
package=a.repository/a.package_relative
def git(*args):
    return subprocess.check_output(["git","-c","core.longpaths=true",*args],cwd=a.repository).decode("utf-8")
def fetch(url,target):
    last=None
    for attempt in range(3):
        try:
            request=urllib.request.Request(url,headers={"User-Agent":"v34-pvalue-publication-verifier","Accept":"application/vnd.github+json" if "api.github.com" in url else "*/*"})
            with urllib.request.urlopen(request,timeout=45) as response:
                assert response.status==200
                with target.open("wb") as f:
                    while True:
                        b=response.read(1024*1024)
                        if not b:break
                        f.write(b)
            return target
        except Exception as e:
            last=e
            if attempt<2:time.sleep(2*(attempt+1))
    raise last
root_url="https://raw.githubusercontent.com/xlminfei/066/"+a.commit+"/"
tree_url="https://api.github.com/repos/xlminfei/066/git/trees/"+a.commit+"?recursive=1"
archive_record=json.loads((package/"archive_manifest.json").read_text(encoding="utf-8"))
requests=[(tree_url,a.downloads/"remote_git_tree.json"),
          (root_url+a.package_relative+"/"+archive_record["archive"],a.downloads/"public_supplement.zip")]
for name in ["README.md","ELPD_P_VALUES_zh.md","AUC_MAE_RMSE_P_VALUES_zh.md"]:
    requests.append((root_url+a.package_relative+"/"+name,a.downloads/("public_"+name)))
with ThreadPoolExecutor(max_workers=3) as executor:
    list(executor.map(lambda pair:fetch(*pair),requests))
tree=json.loads((a.downloads/"remote_git_tree.json").read_text(encoding="utf-8"))
assert not tree.get("truncated")
entries={r["path"]:r for r in tree["tree"] if r["type"]=="blob"}
changed=git("diff-tree","--no-commit-id","--name-only","-r","-z",a.commit).split("\0")
changed=[p for p in changed if p]
receipts=[]
for rel in changed:
    b=(a.repository/rel).read_bytes()
    blob=hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
    e=entries[rel];assert e["sha"]==blob and e["size"]==len(b),rel
    receipts.append({"Path":rel,"Bytes":len(b),"GitBlobSHA1":blob,"SHA256":sha(b)})
for name in ["README.md","ELPD_P_VALUES_zh.md","AUC_MAE_RMSE_P_VALUES_zh.md"]:
    assert (a.downloads/("public_"+name)).read_bytes()==(package/name).read_bytes(),name
archive=a.downloads/"public_supplement.zip"
assert archive.stat().st_size==archive_record["bytes"]
assert sha(archive.read_bytes())==archive_record["sha256"]
prefix=archive_record["zip_root"]
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    mb=z.read(prefix+"PAYLOAD_FILES.csv")
    assert mb==(package/"PAYLOAD_FILES.csv").read_bytes()
    rows=list(csv.DictReader(io.StringIO(mb.decode("utf-8"))))
    assert set(z.namelist())=={prefix+r["Path"] for r in rows}|{prefix+"PAYLOAD_FILES.csv"}
    assert len(z.namelist())==archive_record["files"]
    for r in rows:
        b=z.read(prefix+r["Path"])
        assert len(b)==int(r["Bytes"]) and sha(b)==r["SHA256"],r["Path"]
baseline="161c3fb780fd2d937f4c6823a912feedf8226a47"
preserved=[]
for rel in ["v1","v2","v3","v3.1","v3.2","v3.3","v3.4","formal_results/v3.4_20260923/snapshot"]:
    before=git("rev-parse",baseline+":"+rel).strip();after=git("rev-parse",a.commit+":"+rel).strip()
    assert before==after,rel
    preserved.append({"Path":rel,"TreeSHA1":before})
tag=git("ls-remote","origin","refs/tags/v3.4-formal-results").strip().split()[0]
assert tag=="a1e011cafce56b90e948e1dab5fdbce6a71e25de"
result={"status":"PASS","repository":"https://github.com/xlminfei/066",
        "verified_payload_commit":a.commit,"git_files_verified":len(receipts),
        "public_download_no_auth":True,"public_archive_bytes":archive.stat().st_size,
        "public_archive_sha256":sha(archive.read_bytes()),
        "public_archive_members_verified":len(rows)+1,"public_markdown_readbacks":3,
        "old_trees_preserved":preserved,"formal_results_tag_unchanged":tag,
        "source_analysis_files":88,"new_fits":0,"verified_utc":datetime.now(timezone.utc).isoformat(),
        "file_receipts":receipts}
delivery=package/"delivery";delivery.mkdir(exist_ok=True)
(delivery/"remote_verification.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({k:v for k,v in result.items() if k not in ["file_receipts","old_trees_preserved"]},ensure_ascii=False,indent=2))
