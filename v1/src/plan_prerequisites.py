"""Select exact required fit identities; aggregate counters cannot satisfy a stage."""
def required_fit_keys(plan,primary_only=False):
    jobs=[job for job in plan["main_jobs"] if not primary_only or job["variant"]=="primary"]
    keys={(job["outcome"],job["model"],job["variant"]) for job in jobs}
    if len(keys)!=len(jobs):raise ValueError("Duplicate planned fit identity")
    return keys

def completed_fit_keys(state):
    return {(job["outcome"],job["model"],job["variant"]) for job in (state or {}).get("finished",[]) if job.get("status")=="PASS"}
