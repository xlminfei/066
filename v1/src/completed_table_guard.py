"""Preserve completed R result tables after verifying their immutable manifest and rows."""
from pathlib import Path
import csv
import hashlib
import json


def preserve_completed_table(root, run, path, incoming):
    root, run, path = Path(root).resolve(), Path(run).resolve(), Path(path).resolve()
    if path.parent != run / "results" or not path.name.startswith(("diagnostics_", "parameter_summary_")):
        return False
    phase = "primary" if path.stem.endswith("_primary") else "sensitivity"
    status_path = run / "results" / f"postfit_{phase}_status.json"
    if not status_path.exists():
        return False
    status = json.loads(status_path.read_text(encoding="utf-8"))
    if not str(status.get("status", "")).startswith("COMPLETE_"):
        return False
    manifest_text = str(status["output_manifest"]).replace("\\", "/")
    prefix = "/project/work/ratio_analysis_20260914/"
    manifest_path = root / manifest_text[len(prefix):] if manifest_text.startswith(prefix) else Path(manifest_text)
    manifest_path = manifest_path.resolve()
    if not manifest_path.is_relative_to(root):
        raise RuntimeError("Completed output manifest lies outside the current analysis")
    with manifest_path.open(encoding="utf-8-sig", newline="") as handle:
        manifest = list(csv.DictReader(handle))
    relative = path.relative_to(run).as_posix()
    matches = [r for r in manifest if r["File"].replace("\\", "/") == relative]
    if len(matches) != 1 or not path.is_file():
        raise RuntimeError(f"Completed table is absent from its unique output manifest: {relative}")
    with path.open("rb") as handle:
        actual_sha = hashlib.file_digest(handle, "sha256").hexdigest()
    if actual_sha != matches[0]["SHA256"] or path.stat().st_size != int(matches[0]["Bytes"]):
        raise RuntimeError(f"Completed table changed after its formal postprocessing: {relative}")
    with path.open(encoding="utf-8-sig", newline="") as handle:
        current = list(csv.DictReader(handle))
    keys = ("Model", "Key") if path.name.startswith("diagnostics_") else ("Model", "variable")
    def indexed(rows):
        indexed_rows = {tuple(row[k] for k in keys): row for row in rows}
        if len(indexed_rows) != len(rows):
            raise RuntimeError(f"Repeated completed-table identities: {relative}")
        return indexed_rows
    if indexed(current) != indexed(incoming):
        raise RuntimeError(f"New receipts disagree with the completed table; explicit postfit review required: {relative}")
    return True
