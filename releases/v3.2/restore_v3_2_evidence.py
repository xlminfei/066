#!/usr/bin/env python3
"""Download, verify and reassemble the v3.2 complete evidence archive (public assets)."""
import argparse, hashlib, json, os, pathlib, re, tempfile, urllib.request
BASE = "https://github.com/xlminfei/066/releases/download/v3.2/"
MANIFEST_NAME = "v3.2-complete-evidence.parts.json"
MANIFEST_SHA = "f0bd5d1c325dfb7000fce7ee45820e786b3ae4b5ca6e378fd9e827afda7eef29"
ARCHIVE_SHA = "51a577666046b0d667534485df6626a61bd59c35f589b46d7e0ddb553ce83c56"
def digest(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""): h.update(b)
    return h.hexdigest()
def safe(root, name):
    if pathlib.Path(name).name != name: raise ValueError("Unsafe file name")
    p = (root / name).resolve()
    p.relative_to(root)
    return p
def download(root, name, expected):
    target = safe(root, name)
    if target.exists():
        if digest(target) != expected: raise ValueError("Existing file checksum mismatch: " + name)
        return target
    fd, tmp_name = tempfile.mkstemp(prefix=".download-", dir=root)
    tmp = pathlib.Path(tmp_name).resolve(); tmp.relative_to(root)
    try:
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(BASE + name, timeout=300) as response:
            for b in iter(lambda: response.read(1024 * 1024), b""): out.write(b)
        if digest(tmp) != expected: raise ValueError("Downloaded file checksum mismatch: " + name)
        if target.exists(): raise FileExistsError(target)
        os.rename(tmp, target)
    finally:
        if tmp.exists(): tmp.unlink()
    return target
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", default="v3.2-complete-data")
    parser.add_argument("--manifest", help="Use a local parts manifest")
    parser.add_argument("--no-download", action="store_true", help="Verify existing parts and join locally")
    a = parser.parse_args(); root = pathlib.Path(a.directory).resolve(); root.mkdir(parents=True, exist_ok=True)
    manifest = pathlib.Path(a.manifest).resolve() if a.manifest else safe(root, MANIFEST_NAME)
    if not manifest.exists():
        if a.no_download: raise FileNotFoundError(manifest)
        manifest = download(root, MANIFEST_NAME, MANIFEST_SHA)
    if digest(manifest) != MANIFEST_SHA: raise ValueError("Wrong manifest version/checksum")
    spec = json.loads(manifest.read_text(encoding="utf-8"))
    if spec["archive_sha256"] != ARCHIVE_SHA or spec["part_count"] != len(spec["parts"]): raise ValueError("Invalid archive manifest")
    files = []
    for i, part in enumerate(spec["parts"], 1):
        if part["index"] != i or part["name"] != "v3.2-complete-evidence.zip.part%03d" % i: raise ValueError("Invalid part order/name")
        p = safe(root, part["name"])
        if not p.exists() and not a.no_download: p = download(root, part["name"], part["sha256"])
        if not p.exists() or p.stat().st_size != part["bytes"] or digest(p) != part["sha256"]: raise ValueError("Missing/corrupt part: " + part["name"])
        files.append(p); print("VERIFIED %d/%d %s" % (i, len(spec["parts"]), p.name), flush=True)
    target = safe(root, spec["archive"])
    if not target.exists():
        fd, tmp_name = tempfile.mkstemp(prefix=".join-", dir=root)
        tmp = pathlib.Path(tmp_name).resolve(); tmp.relative_to(root)
        try:
            with os.fdopen(fd, "wb") as out:
                for p in files:
                    with p.open("rb") as inp:
                        for b in iter(lambda: inp.read(1024 * 1024), b""): out.write(b)
            if tmp.stat().st_size != spec["archive_bytes"] or digest(tmp) != ARCHIVE_SHA: raise ValueError("Reassembled archive checksum mismatch")
            if target.exists(): raise FileExistsError(target)
            os.rename(tmp, target)
        finally:
            if tmp.exists(): tmp.unlink()
    if target.stat().st_size != spec["archive_bytes"] or digest(target) != ARCHIVE_SHA: raise ValueError("Existing archive does not match")
    print(json.dumps({"status":"REASSEMBLY_SHA256_VERIFIED","parts":len(files),"archive":str(target),"bytes":target.stat().st_size,"sha256":ARCHIVE_SHA}, ensure_ascii=False))
if __name__ == "__main__": main()
