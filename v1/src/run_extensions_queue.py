"""One bounded posterior-processing worker, fed only by completed current CV receipts."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import subprocess
import time
from atomic_io import atomic_json as publish_json,read_json
from controller_lock import acquire_controller_lock
from extension_script_selection import exporter_name

root=Path("/project/work/ratio_analysis_20260914")
controller_lock=acquire_controller_lock(root,"extensions")
def selected_exporter(cv):
    script=root/"scripts"/exporter_name(cv)
    return script,hashlib.sha256(script.read_bytes()).hexdigest()
env=os.environ.copy();env.update(OMP_NUM_THREADS="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1")
active=None;failed={};done={}
def atomic_json(path,value):
    return publish_json(path,value)
def candidates():
    result={}
    for path in sorted((root/"runs"/"job_receipts").glob("cv__*/status.json")):
        status=read_json(path,missing_ok=True)
        if not status or status.get("status")!="PASS":continue
        key="_".join([status["outcome"],status["cv_type"],status["model"]])
        if key not in result or status["attempt"]>result[key]["attempt"]:result[key]=status
    return result
def parent_file(cv):
    matches=[]
    prefix="__".join([cv["outcome"],cv["model"],"primary"])
    for path in (root/"runs"/"job_receipts").glob(prefix+"__*/status.json"):
        status=read_json(path)
        if status.get("status")=="PASS" and status.get("key")==cv["parent_key"]:
            matches.append(root/"runs"/"formal_20260914_26e686af86fa"/status["relative_file"])
    if len(matches)!=1:raise RuntimeError("Current CV parent is not uniquely selected")
    return matches[0]
def enough_memory():
    # Docker on this host uses cgroup v1; do not use the visible host memory pool.
    limit=Path("/sys/fs/cgroup/memory/memory.limit_in_bytes")
    usage=Path("/sys/fs/cgroup/memory/memory.usage_in_bytes")
    if limit.exists() and usage.exists():return int(limit.read_text())-int(usage.read_text())>=12*1024**3
    # Parent approved one light postprocessor at a 32-GiB limit after measured use below 10 GiB.
    return True
print("CV_EXTENSIONS_QUEUE_STARTED",os.getpid(),flush=True)
while True:
    current=candidates()
    for name,cv in current.items():
        selected_script,selected_hash=selected_exporter(cv)
        manifest=root/"derived"/"cv_extensions"/name/"postprocessing_manifest.json"
        if not manifest.exists():continue
        m=read_json(manifest,missing_ok=True)
        if not m:continue
        helpers_ok=all(hashlib.sha256((root/"scripts"/n).read_bytes()).hexdigest()==h for n,h in m.get("LikelihoodHelperSHA256",{}).items())
        protocol_ok=m.get("NumericalLikelihoodMethod")==cv.get("score_protocol")
        if m.get("status")=="PASS" and m.get("CVKey")==cv["key"] and m.get("FitKey")==cv["parent_key"] and m.get("ScriptSHA256")==selected_hash and helpers_ok and protocol_ok:
            done[name]=dict(CVKey=cv["key"],MCFlaggedFolds=m.get("MCFlaggedFolds",[]),status="PASS")
        else:failed[name]="Existing output has a different identity; preserve it and inspect."
    if active is not None:
        code=active["process"].poll()
        if code is not None:
            active["handle"].close()
            if code!=0:failed[active["name"]]=f"Exit {code}; inspect {active['log']}"
            print("CV_EXTENSIONS_FINISHED",active["name"],code,flush=True)
            active=None
    if active is None and enough_memory():
        eligible=next(((name,cv) for name,cv in current.items() if name not in done and name not in failed),None)
        if eligible:
            name,cv=eligible
            output=root/"derived"/"cv_extensions"/name
            if output.exists() and any(output.iterdir()):failed[name]="Partial existing output needs diagnosis before retry."
            else:
                parent=parent_file(cv)
                script,script_hash=selected_exporter(cv)
                log=root/"logs"/("extensions__"+name+".log")
                handle=log.open("a",encoding="utf-8")
                proc=subprocess.Popen(["Rscript",str(script),cv["cv_file"],str(parent),str(output)],
                                      stdout=handle,stderr=subprocess.STDOUT,cwd=root,env=env)
                active=dict(name=name,pid=proc.pid,log=str(log),process=proc,handle=handle)
                print("CV_EXTENSIONS_STARTED",name,"pid",proc.pid,flush=True)
    cv_queue=root/"provenance"/"cv_queue_status.json"
    cv_snapshot=read_json(cv_queue,missing_ok=True)
    cv_done=bool(cv_snapshot and cv_snapshot.get("status")=="FINISHED")
    complete=cv_done and active is None and all(name in done or name in failed for name in current)
    atomic_json(root/"provenance"/"extensions_queue_status.json",dict(pid=os.getpid(),status="FINISHED" if complete else "RUNNING",
        updated_at=dt.datetime.now(dt.timezone.utc).isoformat(),passed=len(done),expected=40,
        active=None if active is None else {k:v for k,v in active.items() if k not in ["process","handle"]},
        failures=failed,finished=done))
    if complete:break
    time.sleep(10)
print("CV_EXTENSIONS_QUEUE_FINISHED",len(done),"of",40,flush=True)
