"""CV queue: wait for each actual passing primary fit, never reuse historical fits."""
from pathlib import Path
import argparse
import datetime as dt
import json
import os
import subprocess
import time
from atomic_io import atomic_json as publish_json,read_json
from process_identity import AdoptedProcess,NullLogHandle,identity,same_live_process,matching_processes
from controller_lock import acquire_controller_lock

root=Path("/project/work/ratio_analysis_20260914")
parser=argparse.ArgumentParser();parser.add_argument("--workers",type=int,default=2)
parser.add_argument("--adopt-live",action="store_true")
options=parser.parse_args();assert 1<=options.workers<=8
controller_lock=acquire_controller_lock(root,"cv")
old_state_path=root/"provenance"/"cv_queue_status.json"
if old_state_path.exists():
    old_state=read_json(old_state_path,missing_ok=True) or {}
    old_process=identity(old_state.get("pid",0))
    if old_state.get("status")=="RUNNING" and old_process and old_process["state"]!="Z" and any("run_cv_queue.py" in token for token in old_process["command"]):
        raise RuntimeError("The previous CV controller is still live; do not duplicate it")
models=["Null_U","M1_U","M1_P","Site315_U","Site315_P","M2_U","M2_P","M3_U","M3_P","Phylogeny_only_P"]
pending=[dict(outcome=route,model=model,cv_type=design,attempt=1) for design in ["species","phylo_distance"]
         for model in models for route in ["binary","joint"]]
active=[];finished=[]
env=os.environ.copy();env.update(OMP_NUM_THREADS="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1",STAN_NUM_THREADS="1")
def atomic_json(path,value):
    return publish_json(path,value)
def parent_pass(job):
    for attempt in [1,2,3]:
        path=root/"runs"/"job_receipts"/"__".join([job["outcome"],job["model"],"primary",f"attempt{attempt}"])/"status.json"
        if path.exists() and (read_json(path,missing_ok=True) or {}).get("status")=="PASS":return True
    return False
for job in list(pending):
    statuses=[]
    for attempt in [1,2,3]:
        jid="__".join(["cv",job["outcome"],job["model"],job["cv_type"],f"attempt{attempt}"])
        path=root/"runs"/"job_receipts"/jid/"status.json"
        claim_path=path.parent/"launch_claim.json"
        if not path.exists():
            if not claim_path.exists():continue
            claim=read_json(claim_path)
            expected=[job["outcome"],job["model"],job["cv_type"],str(attempt)]
            observed=matching_processes(str(root/"scripts"/"cv_job.R"),expected)
            if len(observed)!=1:raise RuntimeError(f"Unresolved launch claim {jid}; found {len(observed)} exact processes, do not relaunch")
            status=dict(status="RUNNING",pid=observed[0]["pid"],started_at=claim["created_at"])
        else:status=read_json(path)
        statuses.append((attempt,jid,status))
    passed=[s for s in statuses if s[2]["status"]=="PASS"]
    if passed:
        attempt,jid,status=passed[-1]
        finished.append({**job,"attempt":attempt,"job_id":jid,"status":"PASS"});pending.remove(job)
    elif statuses:
        attempt,jid,status=statuses[-1]
        if status["status"]=="RUNNING":
            if not options.adopt_live:raise RuntimeError(f"Live or unresolved job {jid}; explicit adoption is required")
            try:
                proc=AdoptedProcess(status["pid"],str(root/"scripts"/"cv_job.R"),
                                    [job["outcome"],job["model"],job["cv_type"],str(attempt)])
            except RuntimeError:
                again_path=root/"runs"/"job_receipts"/jid/"status.json"
                again=read_json(again_path,missing_ok=True) or {}
                if again.get("status")=="PASS":
                    finished.append({**job,"attempt":attempt,"job_id":jid,"status":"PASS"});pending.remove(job);continue
                if again.get("status")=="NEEDS_REVIEW" and attempt<3:
                    job["attempt"]=attempt+1;continue
                if again.get("status") in ["ERROR","NEEDS_REVIEW"]:
                    finished.append({**job,"attempt":attempt,"job_id":jid,"status":again["status"]});pending.remove(job);continue
                raise
            active.append({**job,"attempt":attempt,"job_id":jid,"pid":proc.pid,"process":proc,
                           "handle":NullLogHandle(),"adopted":True,"process_identity":proc.expected,
                           "log":str(root/"logs"/(jid+".log")),"started_at":status["started_at"]})
            pending.remove(job)
            print("CV_ADOPTED_LIVE",jid,"pid",proc.pid,flush=True)
        elif status["status"]=="NEEDS_REVIEW" and attempt<3:
            job["attempt"]=attempt+1
        else:
            finished.append({**job,"attempt":attempt,"job_id":jid,"status":status["status"]});pending.remove(job)
if len(active)>options.workers:raise RuntimeError("More live jobs than the requested worker budget")
print("CV_QUEUE_STARTED",os.getpid(),len(pending),flush=True)
while pending or active:
    while len(active)<options.workers:
        eligible=next((job for job in pending if parent_pass(job)),None)
        if eligible is None:break
        job=eligible;pending.remove(job)
        jid="__".join(["cv",job["outcome"],job["model"],job["cv_type"],f"attempt{job['attempt']}"])
        job_dir=root/"runs"/"job_receipts"/jid
        job_dir.mkdir(parents=True,exist_ok=True)
        claim_path=job_dir/"launch_claim.json"
        if claim_path.exists():raise RuntimeError(f"Launch claim already exists for {jid}; do not launch twice")
        log_path=root/"logs"/(jid+".log");handle=log_path.open("a",encoding="utf-8")
        command=["Rscript",str(root/"scripts"/"cv_job.R"),job["outcome"],job["model"],job["cv_type"],str(job["attempt"])]
        claim=dict(status="STARTING",job=jid,command=command,controller_pid=os.getpid(),created_at=dt.datetime.now(dt.timezone.utc).isoformat())
        publish_json(claim_path,claim,critical=True)
        proc=subprocess.Popen(command,stdout=handle,stderr=subprocess.STDOUT,cwd=root,env=env)
        claim.update(status="LAUNCHED",pid=proc.pid)
        publish_json(claim_path,claim,critical=True)
        active.append(dict(**job,job_id=jid,pid=proc.pid,process=proc,handle=handle,log=str(log_path),
            started_at=dt.datetime.now(dt.timezone.utc).isoformat()))
        print("CV_STARTED",jid,"pid",proc.pid,flush=True)
    for running in list(active):
        code=running["process"].poll()
        if code is None:continue
        running["handle"].close()
        path=root/"runs"/"job_receipts"/running["job_id"]/"status.json"
        result=read_json(path,missing_ok=True) or {"status":"ERROR"}
        status=result["status"] if code==0 and result.get("status") in ["PASS","NEEDS_REVIEW","ERROR"] else "ERROR"
        print("CV_FINISHED",running["job_id"],status,"exit",code,flush=True)
        if status=="NEEDS_REVIEW" and running["attempt"]<3:
            pending.append({**{k:running[k] for k in ["outcome","model","cv_type"]},"attempt":running["attempt"]+1})
        else:finished.append({**{k:running[k] for k in ["outcome","model","cv_type","attempt","job_id"]},"status":status,"exit_code":code})
        active.remove(running)
    parent_state_path=root/"provenance"/"fit_queue_status.json"
    parent_snapshot=read_json(parent_state_path,missing_ok=True)
    parent_done=bool(parent_snapshot and parent_snapshot.get("status")=="FINISHED")
    if parent_done and not active and pending and not any(parent_pass(job) for job in pending):
        finished += [{**job,"status":"PARENT_NOT_PASS"} for job in pending];pending=[]
    atomic_json(root/"provenance"/"cv_queue_status.json",dict(pid=os.getpid(),status="RUNNING" if active or pending else "FINISHED",
        updated_at=dt.datetime.now(dt.timezone.utc).isoformat(),planned_cv_jobs=40,worker_limit=options.workers,
        passed=sum(r["status"]=="PASS" for r in finished),pending=len(pending),
        active=[{k:v for k,v in r.items() if k not in ["process","handle"]} for r in active],
        needs_attention=[r for r in finished if r["status"]!="PASS"],finished=finished))
    if pending or active:time.sleep(5)
# Also publish when startup found every receipt complete and the scheduling loop was skipped.
atomic_json(root/"provenance"/"cv_queue_status.json",dict(pid=os.getpid(),status="FINISHED",
    updated_at=dt.datetime.now(dt.timezone.utc).isoformat(),planned_cv_jobs=40,worker_limit=options.workers,
    passed=sum(r["status"]=="PASS" for r in finished),pending=0,active=[],
    needs_attention=[r for r in finished if r["status"]!="PASS"],finished=finished))
print("CV_QUEUE_FINISHED",sum(r["status"]=="PASS" for r in finished),"of",40,flush=True)
