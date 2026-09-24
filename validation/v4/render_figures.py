import json, subprocess, sys
from pathlib import Path
from pypdf import PdfReader
from PIL import Image, ImageOps, ImageDraw
root=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
records=[];all_images=[]
for i,pdf in enumerate(sorted(root.glob("*.pdf")),1):
    pages=len(PdfReader(pdf).pages);prefix=out/f"figure_{i:02d}"
    result=subprocess.run(["pdftoppm","-r","85","-png",str(pdf),str(prefix)],capture_output=True,text=True)
    if result.returncode:raise RuntimeError(result.stderr)
    images=sorted(out.glob(prefix.name+"-*.png"),key=lambda p:int(p.stem.split("-")[-1]))
    assert len(images)==pages
    for n,img in enumerate(images,1):
        with Image.open(img) as im:assert im.width>200 and im.height>200
        all_images.append((pdf.name,n,img))
    records.append({"file":pdf.name,"pages":pages,"rendered":len(images),"stderr":result.stderr})
for sheet,start in enumerate(range(0,len(all_images),6),1):
    canvas=Image.new("RGB",(1280,1380),"#eef1f4");draw=ImageDraw.Draw(canvas)
    for j,(name,page,img) in enumerate(all_images[start:start+6]):
        x=(j%2)*640;y=(j//2)*460
        with Image.open(img) as im:thumb=ImageOps.contain(im.convert("RGB"),(628,425))
        canvas.paste(thumb,(x+(640-thumb.width)//2,y+26))
        draw.text((x+6,y+6),f"{name} | page {page}",fill="black")
    canvas.save(out/f"contact_sheet_{sheet}.png")
status={"status":"RENDERED_FOR_VISUAL_REVIEW","pdf_files":len(records),"pages":sum(x["pages"] for x in records),"files":records}
(out/"render_status.json").write_text(json.dumps(status,indent=2),encoding="utf-8")
print(json.dumps(status,indent=2))
