#!/usr/bin/env python3
"""Download and verify the complete v3.4 evidence ZIP; never run model code."""
import argparse, csv, hashlib, io, json, os, pathlib, tempfile, urllib.request, zipfile
NAME = "v3.4-complete-evidence.zip"
URL = "https://github.com/xlminfei/066/releases/download/v3.4/" + NAME
SHA = "abb1db9af70d5bc53b7c958cb599acef85f038344137162767090de4908cf5db"
SIZE = 619833
FILES = 221
def digest(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""): h.update(b)
    return h.hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--directory",default="v3.4-complete-data")
    p.add_argument("--archive",help="Verify a local archive without downloading")
    a=p.parse_args()
    if a.archive: archive=pathlib.Path(a.archive).resolve()
    else:
        root=pathlib.Path(a.directory).resolve();root.mkdir(parents=True,exist_ok=True);archive=root/NAME
        if not archive.exists():
            fd,name=tempfile.mkstemp(prefix=".download-",dir=root);tmp=pathlib.Path(name)
            try:
                request=urllib.request.Request(URL,headers={"User-Agent":"ratio-v3.4-evidence-verifier"})
                with os.fdopen(fd,"wb") as out,urllib.request.urlopen(request,timeout=300) as response:
                    for b in iter(lambda:response.read(1024*1024),b""): out.write(b)
                if tmp.stat().st_size!=SIZE or digest(tmp)!=SHA: raise ValueError("Download checksum mismatch")
                if archive.exists(): raise FileExistsError(archive)
                os.rename(tmp,archive)
            finally:
                if tmp.exists(): tmp.unlink()
    if archive.stat().st_size!=SIZE or digest(archive)!=SHA: raise ValueError("Archive checksum mismatch")
    with zipfile.ZipFile(archive) as z:
        names=z.namelist()
        if len(names)!=len(set(names)): raise ValueError("Duplicated ZIP entry")
        rows=list(csv.DictReader(io.StringIO(z.read("_archive/CONTENTS.csv").decode("utf-8-sig"))))
        if len(rows)!=FILES or len(names)!=FILES+2: raise ValueError("File count mismatch")
        for row in rows:
            name=row["ArchivePath"];parts=pathlib.PurePosixPath(name)
            if parts.is_absolute() or ".." in parts.parts or not name.startswith("v3.4/"): raise ValueError("Unsafe archive path")
            info=z.getinfo(name)
            if info.file_size!=int(row["Bytes"]): raise ValueError("Entry size mismatch: "+name)
            h=hashlib.sha256()
            with z.open(name) as f:
                for b in iter(lambda:f.read(1024*1024),b""): h.update(b)
            if h.hexdigest()!=row["SHA256"]: raise ValueError("Entry checksum mismatch: "+name)
        if z.testzip() is not None: raise ValueError("ZIP CRC failure")
    print(json.dumps({"status":"COMPLETE_ZIP_AND_EVERY_FILE_VERIFIED","archive":str(archive),"source_files":FILES,"bytes":SIZE,"sha256":SHA,"model_computation_started":False}))
if __name__=="__main__": main()
