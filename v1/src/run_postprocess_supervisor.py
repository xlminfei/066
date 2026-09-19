"""Complete the R postprocessing stages after their real fitting prerequisites finish."""
from pathlib import Path
import datetime as dt
import json
import os
import subprocess
import time
from atomic_io import atomic_json,read_json
from controller_lock import acquire_controller_lock
from process_identity import identity
from plan_prerequisites import required_fit_keys,completed_fit_keys

root=Path("/project/work/ratio_analysis_20260914")
run=root/"runs"/"formal_20260914_26e686af86fa"
env=os.environ.copy();env.update(OMP_NUM_THREADS="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1",RATIO_POST_CORES="1")
controller_lock=acquire_controller_lock(root,"postprocess")
plan=json.loads((root/"provenance"/"fit_plan.json").read_text())
primary_required=required_fit_keys(plan,primary_only=True)
all_required=required_fit_keys(plan)
assert len(primary_required)==20 and len(all_required)==36
state_path=root/"provenance"/"postprocess_supervisor_status.json"
state=dict(pid=os.getpid(),status="WAITING_FOR_FITS",stages={},started_at=dt.datetime.now(dt.timezone.utc).isoformat())
if state_path.exists():
    previous=read_json(state_path)
    if previous.get("status") not in ["FINISHED","ERROR"] and Path(f"/proc/{previous.get('pid',0)}").exists():
        raise RuntimeError("A postprocessing supervisor is already live.")
    child=identity(previous.get("active_pid",0) or 0)
    if child and child["state"]!="Z":raise RuntimeError("Previous postprocessing child is still live; inspect it instead of duplicating it")
    state["stages"]=previous.get("stages",{})
def publish(status,**fields):
    state.update(status=status,updated_at=dt.datetime.now(dt.timezone.utc).isoformat(),**fields)
    atomic_json(state_path,state)
def read(path):
    return read_json(path,missing_ok=True)
def run_command(stage,command,allowed=(0,)):
    if state["stages"].get(stage,{}).get("status")=="PASS":return
    log_path=root/"logs"/(stage+".log")
    publish("RUNNING_STAGE",active_stage=stage)
    with log_path.open("a",encoding="utf-8") as handle:
        process=subprocess.Popen(command,stdout=handle,stderr=subprocess.STDOUT,cwd=root,env=env)
        publish("RUNNING_STAGE",active_stage=stage,active_pid=process.pid)
        print("POSTPROCESS_STAGE_STARTED",stage,"pid",process.pid,flush=True)
        while process.poll() is None:
            time.sleep(10)
            publish("RUNNING_STAGE",active_stage=stage,active_pid=process.pid)
        code=process.returncode
    state["stages"][stage]=dict(status="PASS" if code in allowed else "ERROR",exit_code=code,log=str(log_path),
                                finished_at=dt.datetime.now(dt.timezone.utc).isoformat())
    state["active_pid"]=None
    state["active_stage"]=None
    print("POSTPROCESS_STAGE_FINISHED",stage,code,flush=True)
    if code not in allowed:
        publish("ERROR",message=f"Stage {stage} failed with exit {code}")
        raise RuntimeError(f"{stage} failed; inspect its log before retrying")
    return code
print("POSTPROCESS_SUPERVISOR_STARTED",os.getpid(),flush=True)
try:
    while True:
        fits=read(root/"provenance"/"fit_queue_status.json")
        completed=completed_fit_keys(fits)
        if primary_required<=completed:break
        if fits and fits.get("status")=="FINISHED":
            raise RuntimeError("Fit queue finished without all 20 required primary PASS jobs")
        if fits and not Path(f"/proc/{fits['pid']}").exists():
            publish("WAITING_FOR_CONTROLLER_RECOVERY",missing_controller="fit",passed=fits.get("passed"))
        else:publish("WAITING_FOR_PRIMARY_FITS",passed_primary=len(primary_required&completed),passed_fits=len(completed))
        time.sleep(30)
    run_command("merge_before_postfit",["python3",str(root/"scripts"/"merge_receipts.py")])
    run_command("postfit_primary",["Rscript",str(root/"scripts"/"postfit_primary.R")])
    primary=read(run/"results"/"postfit_primary_status.json")
    if not primary:raise RuntimeError("No primary postprocessing status")
    while True:
        fits=read(root/"provenance"/"fit_queue_status.json")
        completed=completed_fit_keys(fits)
        if all_required<=completed:break
        if fits and fits.get("status")=="FINISHED":raise RuntimeError("Fit queue finished without all 36 required PASS jobs")
        publish("WAITING_FOR_SENSITIVITY_FITS",passed_primary=len(primary_required&completed),passed_fits=len(completed))
        time.sleep(30)
    run_command("merge_before_sensitivity_postfit",["python3",str(root/"scripts"/"merge_receipts.py")])
    run_command("postfit_sensitivity",["Rscript",str(root/"scripts"/"postfit_sensitivity.R")])
    # One four-chain matrix check plus seven four-chain CV jobs use at most 32 fitting CPUs,
    # within the current 36-CPU quota; lightweight postprocessing remains single-core.
    for outcome in ["binary","joint"]:
        matrix_pass=False
        for attempt in [1,2,3]:
            stage=f"matrix_{outcome}_attempt{attempt}"
            code=run_command(stage,["Rscript",str(root/"scripts"/"matrix_job.R"),outcome,str(attempt)],allowed=(0,2))
            if code is None:code=state["stages"][stage]["exit_code"]
            if code==0:matrix_pass=True;break
            state["stages"][stage]["status"]="NEEDS_REVIEW"
        if not matrix_pass:raise RuntimeError(f"Matrix check {outcome} still needs numerical review")
    while True:
        cv=read(root/"provenance"/"cv_queue_status.json")
        extensions=read(root/"provenance"/"extensions_queue_status.json")
        if cv and cv.get("status")=="FINISHED" and cv.get("passed")!=40:
            raise RuntimeError("CV queue finished without all 40 required PASS jobs")
        if extensions and extensions.get("failures"):
            raise RuntimeError("CV extension outputs need error review")
        if cv and extensions and cv.get("passed")==40 and extensions.get("passed")==40:
            break
        publish("WAITING_FOR_CV",passed_cv=cv.get("passed",0) if cv else 0,
                passed_extensions=extensions.get("passed",0) if extensions else 0)
        time.sleep(30)
    run_command("merge_before_cv_postfit",["python3",str(root/"scripts"/"merge_receipts.py")])
    run_command("postfit_cv",["Rscript",str(root/"scripts"/"postfit_cv.R")])
    publish("FINISHED",active_stage=None,active_pid=None,next_required="Generate and visually verify model figures; integrate deliverables and audit goal completion")
    print("FORMAL_R_POSTPROCESSING_FINISHED_MODEL_FIGURES_STILL_REQUIRED",flush=True)
except Exception as error:
    publish("ERROR",message=str(error))
    raise
