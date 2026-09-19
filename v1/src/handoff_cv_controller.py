"""Stop only the verified scheduling process; keep its R fits alive for adoption."""
from pathlib import Path
import argparse
import json
import os
import re
import signal
import time
from atomic_io import atomic_json
from process_identity import identity,same_live_process

root=Path("/project/work/ratio_analysis_20260914")
parser=argparse.ArgumentParser();parser.add_argument("--pid",type=int,required=True)
parser.add_argument("--record-prefix",default="cv_scheduler_handoff")
options=parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9_-]+",options.record_prefix):
    raise RuntimeError("The evidence prefix must be a plain filename component")
before_path=root/"provenance"/(options.record_prefix+"_before.json")
after_path=root/"provenance"/(options.record_prefix+"_after.json")
if before_path.exists() or after_path.exists():
    raise RuntimeError("Handoff evidence already exists; choose a new prefix and preserve it")
controller=identity(options.pid)
if not controller or controller["state"]=="Z" or not any(token.endswith("/run_cv_queue.py") for token in controller["command"]):
    raise RuntimeError("The requested PID is not the live CV controller")
os.kill(options.pid,signal.SIGSTOP)
stopped=False
for _ in range(50):
    now=identity(options.pid)
    if now and now["start_ticks"]==controller["start_ticks"] and now["state"] in ["T","t"]:
        stopped=True;break
    time.sleep(.02)
if not stopped:raise RuntimeError("Could not verify the controller was paused")
try:
    status=json.loads((root/"provenance"/"cv_queue_status.json").read_text())
    if status["pid"]!=options.pid:raise RuntimeError("Status belongs to another controller")
    actual_children=[]
    for process_path in Path("/proc").iterdir():
        if not process_path.name.isdigit():continue
        observed=identity(int(process_path.name))
        if observed and observed["state"]!="Z" and observed["ppid"]==options.pid:actual_children.append(observed)
    listed_pids={int(job["pid"]) for job in status.get("active",[])}
    if any(child["pid"] not in listed_pids for child in actual_children):
        raise RuntimeError("A newly launched child is not yet in telemetry; resume controller and retry after it publishes")
    children=[]
    for job in status.get("active",[]):
        observed=identity(job["pid"])
        receipt_path=root/"runs"/"job_receipts"/job["job_id"]/"status.json"
        receipt=json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
        if observed and observed["state"]!="Z":
            expected=[job["outcome"],job["model"],job["cv_type"],str(job["attempt"])]
            if observed["command"][-4:]!=expected or not any(token.endswith("/cv_job.R") for token in observed["command"]):
                raise RuntimeError("A listed child does not match its exact R job")
            children.append(dict(job_id=job["job_id"],identity=observed,receipt_status=receipt.get("status")))
        elif receipt.get("status") not in ["PASS","NEEDS_REVIEW","ERROR"]:
            raise RuntimeError("A missing child lacks a terminal receipt")
    before=dict(controller=controller,queue_status=status,children=children,all_live_direct_children=actual_children,
                reason="Increase only CV scheduling concurrency; preserve running R jobs")
    atomic_json(before_path,before,critical=True)
except BaseException:
    os.kill(options.pid,signal.SIGCONT)
    raise
os.kill(options.pid,signal.SIGTERM)
try:os.kill(options.pid,signal.SIGCONT)
except ProcessLookupError:pass
for _ in range(100):
    now=identity(options.pid)
    if now is None or now["state"]=="Z" or now["start_ticks"]!=controller["start_ticks"]:break
    time.sleep(.05)
else:raise RuntimeError("Old controller has not terminated")
after=[]
for child in children:
    live=same_live_process(child["identity"])
    receipt_path=root/"runs"/"job_receipts"/child["job_id"]/"status.json"
    receipt=json.loads(receipt_path.read_text())
    if not live and receipt.get("status") not in ["PASS","NEEDS_REVIEW","ERROR"]:
        raise RuntimeError("Child neither live nor durably finished after controller handoff")
    after.append(dict(job_id=child["job_id"],pid=child["identity"]["pid"],live=live,status=receipt.get("status")))
atomic_json(after_path,dict(status="PASS_CONTROLLER_ONLY_STOPPED",children=after),critical=True)
print(json.dumps(dict(status="PASS_CONTROLLER_ONLY_STOPPED",children=after)),flush=True)
