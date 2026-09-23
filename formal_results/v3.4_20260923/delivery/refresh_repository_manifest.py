import csv,hashlib,io,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]);files=subprocess.check_output(['git','-C',str(root),'ls-files','-z']).decode('utf-8').split('\0');files=sorted(x for x in files if x and x not in ('MANIFEST.csv','MANIFEST.sha256'))
rows=[]
for rel in files:
 p=root/rel;b=p.read_bytes();rows.append({'Path':rel,'Bytes':len(b),'SHA256':hashlib.sha256(b).hexdigest()})
s=io.StringIO(newline='');w=csv.DictWriter(s,fieldnames=['Path','Bytes','SHA256'],quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(rows);b=s.getvalue().encode('utf-8');(root/'MANIFEST.csv').write_bytes(b);(root/'MANIFEST.sha256').write_text(hashlib.sha256(b).hexdigest()+'  MANIFEST.csv\n',encoding='ascii');print(json.dumps({'tracked_file_rows':len(rows),'manifest_sha256':hashlib.sha256(b).hexdigest()}))
