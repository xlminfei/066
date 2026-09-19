"""Merge completed job receipts into the manual's append-index schemas."""
from pathlib import Path
from collections import defaultdict
import csv
import json
import time
from completed_table_guard import preserve_completed_table

root=Path(__file__).resolve().parents[1]
run=root/"runs"/"formal_20260914_26e686af86fa"
receipt_root=root/"runs"/"job_receipts"
preserved_tables=[]
def read_csv(path):
    with path.open(encoding="utf-8-sig",newline="") as f:return list(csv.DictReader(f))
def atomic_csv(path,rows,fields=None):
    if not rows and fields is None:return
    if preserve_completed_table(root,run,path,rows):
        preserved_tables.append(path.relative_to(root).as_posix())
        return
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix(path.suffix+".tmp")
    with temp.open("w",encoding="utf-8",newline="") as f:
        writer=csv.DictWriter(f,fieldnames=fields or list(rows[0]));writer.writeheader();writer.writerows(rows)
    for attempt in range(100):
        try:
            temp.replace(path)
            break
        except PermissionError:
            if attempt==99:raise
            time.sleep(.1)
fit_rows=[];cv_by_dir=defaultdict(list);history=[];diagnostics=defaultdict(list);parameters=defaultdict(list)
for status_path in sorted(receipt_root.glob("*/status.json")):
    status=json.loads(status_path.read_text(encoding="utf-8"))
    job_dir=status_path.parent
    history.append({k:status.get(k,"") for k in ["job","status","outcome","model","variant","cv_type","attempt","key","parent_key","started_at","finished_at","message"]})
    if status.get("status")!="PASS":continue
    if status.get("job","").startswith("cv__"):
        records=read_csv(job_dir/"cv_index.csv")
        row=records[-1]
        assert row["Key"]==status["key"] and row["Model"]==status["model"]
        relative=Path(status["cv_dir"]).name
        cv_by_dir[run/"cv"/relative].append((int(status["attempt"]),row,status))
    else:
        records=read_csv(job_dir/"fit_index.csv")
        row=records[-1]
        assert row["Key"]==status["key"] and row["Model"]==status["model"] and row["Outcome"]==status["outcome"]
        assert (run/row["RelativeFile"]).is_file()
        fit_rows.append((int(status["attempt"]),row))
        pair=(status["outcome"],status["variant"])
        diagnostics[pair].extend(read_csv(job_dir/"results"/f"diagnostics_{pair[0]}_{pair[1]}.csv"))
        parameters[pair].extend(read_csv(job_dir/"results"/f"parameter_summary_{pair[0]}_{pair[1]}.csv"))
fit_rows.sort(key=lambda item:(item[1]["Outcome"],item[1]["Variant"],item[1]["Model"],item[0]))
chosen={(r["Outcome"],r["Variant"],r["Model"]):r for _,r in fit_rows}
atomic_csv(run/"fit_index.csv",[row for _,row in fit_rows])
for pair,rows in diagnostics.items():
    keymap={row["Model"]:chosen[(pair[0],pair[1],row["Model"])]["Key"] for row in rows}
    keep=[row for row in rows if row["Key"]==keymap[row["Model"]]]
    atomic_csv(run/"results"/f"diagnostics_{pair[0]}_{pair[1]}.csv",keep)
for pair,rows in parameters.items():
    # Each primary/sensitivity job stops retrying after PASS, so the passing term table is unique.
    if len({(r["Model"],r["variable"]) for r in rows})!=len(rows):
        raise RuntimeError("Multiple passing parameter versions need explicit selection")
    atomic_csv(run/"results"/f"parameter_summary_{pair[0]}_{pair[1]}.csv",rows)
cv_manifest=[]
for folder,entries in cv_by_dir.items():
    entries.sort(key=lambda item:(item[1]["Model"],item[0]))
    for _,row,status in entries:
        parent=chosen.get((status["outcome"],"primary",status["model"]))
        assert parent is not None and parent["Key"]==row["ParentKey"],"CV parent selection changed"
        assert (folder/row["File"]).is_file()
        cv_manifest.append(dict(Outcome=status["outcome"],CVType=status["cv_type"],Model=status["model"],
            Attempt=status["attempt"],CVKey=status["key"],ParentKey=status["parent_key"],CVDirectory=folder.relative_to(root).as_posix(),
            CVFile=(folder/row["File"]).relative_to(root).as_posix(),ParentFile=(run/parent["RelativeFile"]).relative_to(root).as_posix()))
    atomic_csv(folder/"cv_index.csv",[row for _,row,_ in entries])
atomic_csv(root/"provenance"/"execution_history.csv",history)
atomic_csv(root/"provenance"/"selected_cv_manifest.csv",cv_manifest)
summary=dict(selected_fits=len(chosen),primary_fits=sum(key[1]=="primary" for key in chosen),
    selected_cv_jobs=len({(r["Outcome"],r["CVType"],r["Model"]) for r in cv_manifest}),
    job_history_rows=len(history),attention=[r for r in history if r["status"] in ["ERROR","NEEDS_REVIEW"]],
    preserved_completed_result_tables=preserved_tables)
(root/"provenance"/"merged_receipts_status.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(summary,ensure_ascii=False,indent=2))
