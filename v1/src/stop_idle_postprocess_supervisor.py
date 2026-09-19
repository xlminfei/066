"""Replace only a verified idle postprocessing supervisor; never signal R tasks."""
from pathlib import Path
import argparse
import json
import os
import signal
import time
from process_identity import identity
from atomic_io import atomic_json

root=Path("/project/work/ratio_analysis_20260914")
parser=argparse.ArgumentParser();parser.add_argument("--pid",type=int,required=True)
args=parser.parse_args()
observed=identity(args.pid)
if not observed or observed["state"]=="Z" or not any(token.endswith("/run_postprocess_supervisor.py") for token in observed["command"]):
    raise RuntimeError("PID is not the expected live postprocessing supervisor")
os.kill(args.pid,signal.SIGSTOP)
try:
    for _ in range(50):
        current=identity(args.pid)
        if current and current["start_ticks"]==observed["start_ticks"] and current["state"] in ["T","t"]:break
        time.sleep(.02)
    else:raise RuntimeError("Cannot verify supervisor pause")
    state=json.loads((root/"provenance"/"postprocess_supervisor_status.json").read_text())
    if state["pid"]!=args.pid or state["status"] not in ["WAITING_FOR_FITS","WAITING_FOR_PRIMARY_FITS"] or state.get("active_pid"):
        raise RuntimeError("Supervisor is not idle before primary postprocessing")
    children=[]
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():continue
        child=identity(int(path.name))
        if child and child["ppid"]==args.pid and child["state"]!="Z":children.append(child)
    if children:raise RuntimeError("Supervisor has live children; do not interrupt")
    atomic_json(root/"provenance"/"postprocess_schedule_upgrade.json",
                dict(status="VERIFIED_IDLE_NO_CHILDREN",process=observed,previous_state=state),critical=True)
except BaseException:
    os.kill(args.pid,signal.SIGCONT)
    raise
os.kill(args.pid,signal.SIGTERM)
try:os.kill(args.pid,signal.SIGCONT)
except ProcessLookupError:pass
for _ in range(100):
    current=identity(args.pid)
    if current is None or current["state"]=="Z" or current["start_ticks"]!=observed["start_ticks"]:break
    time.sleep(.05)
else:raise RuntimeError("Old supervisor did not exit")
print("IDLE_POSTPROCESS_SUPERVISOR_ONLY_STOPPED")
