"""Review completed fitting/PPC/matrix phases only; never issue a full-run acceptance."""
from pathlib import Path
import json
from collections import Counter
from audit_final_run import Audit

root = Path(__file__).resolve().parents[1]
audit = Audit(root, "formal_20260914_26e686af86fa")
audit.section("Frozen inputs", audit.inputs)
for p in sorted((root / "runs/job_receipts").glob("*/status.json")):
    if p.parent.name.startswith("cv__"):
        continue
    state = audit.read_json(p)
    audit.fit_receipts.append((p, state))
for row in audit.csv(audit.run / "fit_index.csv"):
    audit.selected[(row["Outcome"], row["Variant"], row["Model"])] = row
audit.require(set(audit.selected) == audit.primary_expected | audit.sens_expected,
              "Exact 20 primary and 16 sensitivity identities")
for item, row in audit.selected.items():
    audit.section("Selected fit " + "/".join(item), lambda item=item, row=row: audit.audit_fit(item, row))
audit.section("Primary formal outputs", audit.primary_outputs)
audit.section("Sensitivity formal outputs", audit.sensitivity_outputs)
audit.section("Both matrix checks", audit.matrices)
counts = dict(Counter(row["Status"] for row in audit.checks))
result = dict(version="completed_phase_review_v1", scope="frozen inputs; 36 fits; primary and sensitivity PPC/predictions; two matrix checks",
              full_goal_complete=False, not_final_acceptance=True,
              status="PASS_SELECTED_SCOPE" if all(r["Status"] == "PASS" for r in audit.checks) else "REVIEW_REQUIRED",
              counts=counts, checks=audit.checks, retained_flags=audit.flags)
target = root / "review/completed_phases_20260915.json"
target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"status": result["status"], "counts": counts, "flag_count": len(audit.flags),
                  "issues": [r for r in audit.checks if r["Status"] != "PASS"], "report": str(target)}, ensure_ascii=False))
raise SystemExit(0 if result["status"] == "PASS_SELECTED_SCOPE" else 1)
