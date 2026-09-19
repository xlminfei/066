"""Prepare local CV-figure review assets; never declares manual visual review passed."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE / "figures" / "descriptive" / "_runtime"))
from PIL import Image, ImageDraw, ImageFont
import pypdfium2 as pdfium

FIG = BASE / "figures" / "model"
QA = FIG / "_visual_review_cv_20260916"
GROUPS = ["cv_diagnostics", "cv_elpd", "cv_mc", "roc_calibration", "quantitative", "predictive_bands", "metrics"]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def contact(paths, labels, target):
    cols = min(2, len(paths))
    width, height = 1180, 1280
    image = Image.new("RGB", (cols * width, math.ceil(len(paths) / cols) * height), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 24)
    for i, (path, label) in enumerate(zip(paths, labels)):
        with Image.open(path) as source:
            thumb = source.convert("RGB")
        thumb.thumbnail((width - 24, height - 54), Image.Resampling.LANCZOS)
        x, y = (i % cols) * width, (i // cols) * height
        draw.text((x + 12, y + 9), label, font=font, fill="#182C3B")
        image.paste(thumb, (x + (width - thumb.width) // 2, y + 44))
    image.save(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--groups", nargs="+", choices=GROUPS, default=GROUPS)
    parser.add_argument("--contacts", action="store_true")
    parser.add_argument("--render-pdfs", action="store_true")
    args = parser.parse_args()
    QA.mkdir(exist_ok=True)
    rows = list(csv.DictReader((FIG / "FIGURE_INDEX.csv").open(encoding="utf-8-sig")))
    rows = [r for r in rows if r["Group"] in args.groups]
    by_scope = defaultdict(list)
    for row in rows:
        by_scope[(row["Group"], row["Scope"])].append(row)
    records = []
    if args.contacts:
        for (group, scope), figures in by_scope.items():
            for start in range(0, len(figures), 4):
                part = figures[start:start + 4]
                target = QA / f"{group}_{scope}_contact_{start // 4 + 1:02d}.png"
                contact([FIG / r["PNG"] for r in part], [r["FigureID"] for r in part], target)
                for cell, row in enumerate(part, 1):
                    records.append({"FigureID": row["FigureID"], "Group": group, "Scope": scope,
                                    "PNG_SHA256": sha(FIG / row["PNG"]), "Contact": str(target.relative_to(BASE)),
                                    "ContactCell": cell, "Status": "AWAITING_MANUAL_VISUAL_REVIEW"})
        path = QA / "contact_manifest.json"
        previous = json.loads(path.read_text(encoding="utf-8")) if path.exists() else []
        previous = [r for r in previous if r["Group"] not in args.groups]
        path.write_text(json.dumps(previous + records, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Prepared contacts for {len(records)} figures.", flush=True)
    if args.render_pdfs:
        pdfs = defaultdict(list)
        for row in rows:
            pdfs[row["PDF"]].append(row)
        renders = []
        for name, figures in pdfs.items():
            group = figures[0]["Group"]
            if group == "cv_diagnostics" and not (name.endswith("fold1.pdf") or name.endswith("fold5.pdf")):
                continue
            doc = pdfium.PdfDocument(str(FIG / name))
            pages = sorted({0, len(doc) // 2, len(doc) - 1})
            for index in pages:
                page = doc[index]
                bitmap = page.render(scale=150 / 72)
                target = QA / f"{Path(name).stem}_pdf_p{index + 1:02d}.png"
                bitmap.to_pil().save(target)
                renders.append({"PDF": name, "PDF_SHA256": sha(FIG / name), "Page": index + 1,
                                "Group": group, "FigureID": figures[index]["FigureID"],
                                "Render": str(target.relative_to(BASE)), "Status": "AWAITING_MANUAL_VISUAL_REVIEW"})
                bitmap.close()
                page.close()
            doc.close()
        path = QA / "pdf_render_manifest.json"
        previous = json.loads(path.read_text(encoding="utf-8")) if path.exists() else []
        previous = [r for r in previous if r["Group"] not in args.groups]
        path.write_text(json.dumps(previous + renders, ensure_ascii=False, indent=2), encoding="utf-8")
        grouped = defaultdict(list)
        for row in renders:
            grouped[row["Group"]].append(row)
        for group, entries in grouped.items():
            for start in range(0, len(entries), 4):
                part = entries[start:start + 4]
                target = QA / f"pdf_{group}_contact_{start // 4 + 1:02d}.png"
                contact([BASE / r["Render"] for r in part], [f"{r['PDF']} | p{r['Page']}" for r in part], target)
                for row in part:
                    row["Contact"] = str(target.relative_to(BASE))
        path.write_text(json.dumps(previous + renders, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Rendered {len(renders)} PDF pages for manual inspection.", flush=True)


if __name__ == "__main__":
    main()
