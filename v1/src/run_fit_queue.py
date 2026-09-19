"""Bounded local fit queue with per-job logs, explicit retries, and no shared CSV writes."""
from pathlib import Path
import argparse
import datetime as dt
import json
import os
import subprocess
import time
from atomic_io import atomic_json as publish_json

root=Path("/project/work/ratio_analysis_20260914")
parser=argparse.ArgumentParser()
parser.add_argument("--workers",type=int,default=2)
options=parser.parse_args()
assert 1<=options.workers<=2
manifest_path=root/"provenance"/"fit_plan.json"
models=["Null_U","M1_U","M1_P","Site315_U","Site315_P","M2_U","M2_P","M3_U","M3_P","Phylogeny_only_P"]
jobs=[dict(outcome=outcome,model=model,variant="primary") for model in models for outcome in ["binary","joint"]]
for variant in ["b_sd_025","b_sd_100"]:
    jobs += [dict(outcome=outcome,model=model,variant=variant) for model in ["M3_U","M3_P"] for outcome in ["binary","joint"]]
jobs += [dict(outcome="joint",model=model,variant="rho_beta22") for model in ["M1_U","M1_P","M3_U","M3_P"]]
jobs += [dict(outcome=outcome,model=model,variant="beta_binomial") for model in ["M1_U","M1_P"] for outcome in ["binary","joint"]]
plan=dict(primary_fits=20,sensitivity_fits=16,main_jobs=jobs,
          planned_cv_types=["species","phylo_distance"],cv_folds=5,cv_primary_model_jobs=40,
          planned_cv_refits=200,planned_optional_matrix_checks=["binary_M3_P","joint_M3_P"],
          default_sampling=dict(chains=4,iter=4000,warmup=2000,adapt_delta=.99,max_treedepth=12),
          retry_policy="NEEDS_REVIEW: 8000/4000,.999,depth15 then 16000/8000,.9995,depth15; errors require diagnosis",
          exclusions="No additional data exclusions, no automatic numerical deduplication, no empirical model selection before fit")
def write_json(path,value):
    return publish_json(path,value,critical=path.name=="fit_plan.json")
if manifest_path.exists():
    assert json.loads(manifest_path.read_text())==plan,"Fit plan changed; do not silently redefine a run."
else: write_json(manifest_path,plan)

env=os.environ.copy()
env.update(OMP_NUM_THREADS="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1",STAN_NUM_THREADS="1")
pending=[]; finished=[]; active=[]
for job in jobs:
    found_pass=False
    for attempt in [1,2,3]:
        job_id="__".join([job["outcome"],job["model"],job["variant"],f"attempt{attempt}"])
        status_path=root/"runs"/"job_receipts"/job_id/"status.json"
        if status_path.exists():
            status=json.loads(status_path.read_text())
            if status["status"]=="PASS":
                finished.append(dict(**job,attempt=attempt,status="PASS",job_id=job_id));found_pass=True;break
            if status["status"]=="RUNNING":
                pid=status.get("pid")
                if pid and Path(f"/proc/{pid}").exists():
                    raise RuntimeError(f"Job is already live: {job_id} pid={pid}")
                raise RuntimeError(f"Unresolved interrupted job: {job_id}; inspect before restarting")
    if not found_pass: pending.append(dict(**job,attempt=1))

def snapshot():
    return dict(pid=os.getpid(),updated_at=dt.datetime.now(dt.timezone.utc).isoformat(),
                status="RUNNING" if active or pending else "FINISHED",
                planned_main_jobs=len(jobs),passed=sum(x["status"]=="PASS" for x in finished),
                needs_attention=[x for x in finished if x["status"]!="PASS"],
                active=[{k:v for k,v in x.items() if k not in ["process","handle"]} for x in active],
                pending=len(pending),finished=finished)
print("FIT_QUEUE_STARTED",os.getpid(),len(pending),flush=True)
while pending or active:
    while pending and len(active)<options.workers:
        job=pending.pop(0)
        job_id="__".join([job["outcome"],job["model"],job["variant"],f"attempt{job['attempt']}"])
        log_path=root/"logs"/(job_id+".log")
        handle=log_path.open("a",encoding="utf-8")
        command=["Rscript",str(root/"scripts"/"fit_job.R"),job["outcome"],job["model"],job["variant"],str(job["attempt"])]
        process=subprocess.Popen(command,stdout=handle,stderr=subprocess.STDOUT,cwd=root,env=env)
        active.append(dict(**job,job_id=job_id,pid=process.pid,started_at=dt.datetime.now(dt.timezone.utc).isoformat(),
                           log=str(log_path),process=process,handle=handle))
        print("FIT_STARTED",job_id,"pid",process.pid,flush=True)
    for running in list(active):
        returncode=running["process"].poll()
        if returncode is None: continue
        running["handle"].close()
        status_path=root/"runs"/"job_receipts"/running["job_id"]/"status.json"
        result=json.loads(status_path.read_text()) if status_path.exists() else dict(status="ERROR",message="No job receipt")
        state=result["status"] if returncode==0 else "ERROR"
        base={k:running[k] for k in ["outcome","model","variant","attempt","job_id"]}
        print("FIT_FINISHED",running["job_id"],state,"exit",returncode,flush=True)
        if state=="NEEDS_REVIEW" and running["attempt"]<3:
            retry={k:running[k] for k in ["outcome","model","variant"]}
            retry["attempt"]=running["attempt"]+1
            pending.append(retry)
        else: finished.append(dict(**base,status=state,exit_code=returncode))
        active.remove(running)
    write_json(root/"provenance"/"fit_queue_status.json",snapshot())
    if pending or active: time.sleep(5)
print("FIT_QUEUE_FINISHED",sum(x["status"]=="PASS" for x in finished),"of",len(jobs),flush=True)
