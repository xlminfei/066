"""Describe existing training PPC draws; never fit, redraw, or alter model results."""
from pathlib import Path
import argparse
import csv
import hashlib
import json

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--phase", choices=("primary", "sensitivity"), default="primary")
phase = parser.parse_args().phase
results = root / "runs/formal_20260914_26e686af86fa/results"
status_path = results / f"postfit_{phase}_status.json"
status = json.loads(status_path.read_text(encoding="utf-8"))
if not status.get("status", "").startswith("COMPLETE_"):
    raise RuntimeError("The selected formal PPC postprocessing phase is not complete")
summary_path = results / f"ppc_summary_all_{phase}.csv"
draws_path = results / f"ppc_statistic_plot_data_{phase}.csv"

def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))

def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()

sources = [status_path, summary_path, draws_path]
before = {p.relative_to(root).as_posix(): digest(p) for p in sources}
summaries = read_csv(summary_path)
groups = {}
for row in read_csv(draws_path):
    identity = (row["Outcome"], row["Model"], row["Variant"], row["Key"], row["Subset"])
    groups.setdefault(identity, []).append(row)

def q7(values, probability):
    values = sorted(values)
    position = (len(values) - 1) * probability
    index = int(position)
    return values[index] + (position - index) * (values[min(index + 1, len(values) - 1)] - values[index])

rows = []
for summary in summaries:
    identity = (summary["Outcome"], summary["Model"], summary["Variant"], summary["Key"], summary["Subset"])
    draws = groups[identity]
    if len(draws) != 500 or len({row["Replicate"] for row in draws}) != 500:
        raise RuntimeError("Expected the unchanged 500 formal PPC replicates for each subset")
    for statistic, observed_column in (("Mean", "ObservedMean"), ("ZeroFraction", "ObservedZeroFraction"), ("OneFraction", "ObservedOneFraction")):
        values = [float(row[statistic]) for row in draws]
        observed = float(summary[observed_column])
        lower, upper = q7(values, .025), q7(values, .975)
        outside = observed < lower - 1e-12 or observed > upper + 1e-12
        rows.append(dict(Outcome=summary["Outcome"], Model=summary["Model"], Variant=summary["Variant"], Key=summary["Key"],
                         Subset=summary["Subset"], Statistic=statistic, Observed=observed,
                         ReplicatedLower95=lower, ReplicatedMedian=q7(values, .5), ReplicatedUpper95=upper,
                         Replicates=500, DescriptiveFlag="OBSERVED_OUTSIDE_REPLICATE_CENTRAL95" if outside else "WITHIN_REPLICATE_CENTRAL95",
                         Scope="training posterior predictive check, not a calibrated test or held-out validation"))
expected_rows = 90 if phase == "primary" else 78
if len(rows) != expected_rows or len(groups) != len(summaries):
    raise RuntimeError("Formal PPC subset coverage changed")
if before != {p.relative_to(root).as_posix(): digest(p) for p in sources}:
    raise RuntimeError("Formal PPC sources changed during the descriptive summary")
target = root / "review" / f"{phase}_ppc_descriptive_flags.csv"
with target.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
manifest = dict(phase=phase, rows=len(rows), source_sha256=before, script_sha256=digest(Path(__file__)),
                output=target.relative_to(root).as_posix(), output_sha256=digest(target),
                interpretation="Descriptive training PPC interval flags; not a calibrated hypothesis test or CV assessment")
target.with_suffix(".json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(dict(output=str(target), rows=len(rows), outside_flags=sum(r["DescriptiveFlag"].startswith("OBSERVED_OUTSIDE") for r in rows))))
