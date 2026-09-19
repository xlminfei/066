from pathlib import Path
import json
from plan_prerequisites import required_fit_keys,completed_fit_keys
plan=json.loads((Path(__file__).resolve().parents[1]/"provenance"/"fit_plan.json").read_text())
primary=[j for j in plan["main_jobs"] if j["variant"]=="primary"]
sens=[j for j in plan["main_jobs"] if j["variant"]!="primary"]
def state(jobs):return {"finished":[{**j,"status":"PASS"} for j in jobs]}
p=required_fit_keys(plan,True);a=required_fit_keys(plan)
assert len(p)==20 and len(a)==36
assert not p<=completed_fit_keys(state(primary[:19]+sens[:1]))
assert p<=completed_fit_keys(state(primary))
assert not a<=completed_fit_keys(state(primary))
assert a<=completed_fit_keys(state(primary+sens))
bad=state(primary+sens);bad["finished"][-1]["status"]="NEEDS_REVIEW"
assert not a<=completed_fit_keys(bad)
print("PRIMARY_AND_SENSITIVITY_EXACT_PREREQUISITES_PASS")
