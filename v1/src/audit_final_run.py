"""Read-only acceptance of the frozen 20260914 formal run; never starts R or fits.

Writes only review/final_acceptance.{json,csv,md}. Exit: 0 complete (review flags
may remain), 2 incomplete, 1 contradicted requirements. R object-level checks are
reused only when their recorded file hashes and selected keys still correspond.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import math
import statistics
import sys
import time
import traceback
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from numerical_likelihood_contract import (
    STABLE_PROTOCOL, LEGACY_PROTOCOL, COMPAT_CSV, COMPAT_SOURCES, MATH_REVIEW,
    NumericalEvidenceIncomplete, validate_extension_manifest,
    validate_score_receipt_protocol, validate_compatibility, validate_raw_fold_metadata,
)

VERSION = "formal_acceptance_20260914_v1"
MODELS = ["Null_U", "Phylogeny_only_P", "Site315_U", "Site315_P", "M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P"]
SIX = ["M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P"]
OUTCOMES = ["binary", "joint"]
DESIGNS = ["species", "phylo_distance"]
POINT_RULE = "posterior_mean_of_species_expected_ratio_m"
FIXED_INPUT_HASHES = {
    "snapshot": "26e686af86fa5e6f7d6e97813f09a8448a8d13b5f1cb4241d30b10d039573142",
    "observations": "3c886f7f2c11012463296b350a931543542b4e1c0d128ad3c408fda9ae824d79",
    "sites": "0a99692b060f13d1faaa870d06ea7dca9a4f16bc289636bcc88f5d105ebdacb5",
    "tree": "114941169558dc76e15d2e86b50045a7f5ca853ea1491b118c0a966946b3ffde",
    "map": "a7b5e998da5bdf43c0f57177b710d231d0705e089a46e9f0dcc2c4904dd197c8",
}


class MissingEvidence(Exception):
    pass


def number(v):
    if v is None or str(v).strip().lower() in {"", "na", "nan", "null"}:
        return math.nan
    return float(v)


def truth(v):
    if v is True or str(v).upper() in {"TRUE", "1"}:
        return True
    if v is False or str(v).upper() in {"FALSE", "0"}:
        return False
    raise ValueError(f"Missing/invalid boolean: {v!r}")


def close(a, b, tol=1e-10):
    a, b = number(a), number(b)
    return math.isfinite(a) and math.isfinite(b) and abs(a - b) <= tol


def same_cell(a, b):
    if str(a) == str(b):
        return True
    try:
        return close(a, b, 1e-12)
    except (ValueError, TypeError):
        return False


def as_rows(v):
    return [v] if isinstance(v, dict) else (v or [])


def labels(row):
    t = row["Type"]
    if t == "count":
        return "HIGH" if 2 * number(row["Events"]) >= number(row["Total"]) else "LOW"
    if t == "exact":
        return "HIGH" if number(row["Exact"]) >= .5 else "LOW"
    return "LOW" if number(row["Upper"]) <= .5 else ("HIGH" if number(row["Lower"]) >= .5 else "UNCLASSIFIED")


def auc_rank(rows):
    positive = [r for r in rows if int(number(r["High"])) == 1]
    negative = [r for r in rows if int(number(r["High"])) == 0]
    if not positive or not negative:
        return math.nan
    # Exact empirical probability of concordance, half credit for tied scores.
    total = sum((number(p["OOFPrHigh"]) > number(n["OOFPrHigh"])) +
                .5 * (number(p["OOFPrHigh"]) == number(n["OOFPrHigh"]))
                for p in positive for n in negative)
    return total / (len(positive) * len(negative))


def expected_jobs():
    primary = {(o, "primary", m) for o in OUTCOMES for m in MODELS}
    sens = {(o, v, m) for o in OUTCOMES for v in ["b_sd_025", "b_sd_100"] for m in ["M3_U", "M3_P"]}
    sens |= {("joint", "rho_beta22", m) for m in ["M1_U", "M1_P", "M3_U", "M3_P"]}
    sens |= {(o, "beta_binomial", m) for o in OUTCOMES for m in ["M1_U", "M1_P"]}
    return primary, sens


class Audit:
    def __init__(self, base, run_name):
        self.base = Path(base).resolve()
        self.run = self.base / "runs" / run_name
        self.res = self.run / "results"
        self.checks, self.flags, self.states, self.hash_cache = [], [], {}, {}
        self.selected, self.cvs, self.foldmaps, self.foldkeys, self.extensions = {}, {}, {}, {}, {}
        self.known_keys, self.fit_receipts, self.cv_receipts = set(), [], []
        self.model_scopes = set()
        self.primary_expected, self.sens_expected = expected_jobs()
        self.numerical_compatibility = None
        self.numerical_protocols = {}
        self.started = datetime.now(timezone.utc).isoformat()
        self.audit_script_sha = self.sha(Path(__file__).resolve())
        self.numerical_contract_sha = self.sha(Path(__file__).with_name("numerical_likelihood_contract.py"))

    def path(self, value, relative=None):
        s = str(value).replace("\\", "/")
        marker = "/work/ratio_analysis_20260914/"
        if marker in s:
            p = self.base / s.split(marker, 1)[1]
        elif s.rstrip("/").endswith("/work/ratio_analysis_20260914"):
            p = self.base
        else:
            p = Path(s)
            if not p.is_absolute():
                p = (relative or self.base) / p
        p = p.resolve()
        if not p.is_relative_to(self.base):
            raise ValueError(f"Evidence path escapes this analysis root: {p}")
        return p

    def rel(self, p):
        try:
            return str(Path(p).relative_to(self.base)).replace("\\", "/")
        except ValueError:
            return str(p)

    def mark(self, name, status, detail="", paths=()):
        self.checks.append({"Check": name, "Status": status, "Detail": str(detail),
                            "Evidence": " | ".join(self.rel(p) for p in paths)})

    def require(self, ok, name, detail="", paths=()):
        self.mark(name, "PASS" if ok else "FAIL", detail, paths)
        return bool(ok)

    def warn(self, category, **details):
        self.flags.append({"Category": category, **details})

    def track(self, p):
        p = self.path(p)
        if not p.is_file():
            raise MissingEvidence(self.rel(p))
        stat = p.stat()
        state = (stat.st_size, stat.st_mtime_ns)
        if p in self.states and self.states[p] != state:
            raise MissingEvidence(f"INPUT_DRIFT while reading {self.rel(p)}")
        self.states.setdefault(p, state)
        return p

    def sha(self, p):
        p = self.track(p)
        if p not in self.hash_cache:
            h = hashlib.sha256()
            with p.open("rb") as stream:
                for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                    h.update(chunk)
            self.hash_cache[p] = h.hexdigest()
            self.track(p)
        return self.hash_cache[p]

    def read_json(self, p):
        p = self.track(p)
        try:
            ans = json.loads(p.read_text(encoding="utf-8-sig"))
        except json.JSONDecodeError as e:
            raise MissingEvidence(f"JSON not complete/readable: {self.rel(p)}: {e}")
        self.track(p)
        return ans

    def csv(self, p, fields=()):
        p = self.track(p)
        with p.open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if not set(fields) <= set(reader.fieldnames or []):
                raise ValueError(f"{self.rel(p)} lacks fields {sorted(set(fields)-set(reader.fieldnames or []))}")
            rows = list(reader)
        self.track(p)
        return rows

    def section(self, name, fn):
        before = len(self.checks)
        try:
            fn()
        except (MissingEvidence, NumericalEvidenceIncomplete) as e:
            self.mark(name, "INCOMPLETE", str(e))
        except Exception as e:
            self.mark(name, "FAIL", f"{type(e).__name__}: {e}")
        if len(self.checks) == before:
            self.mark(name, "PASS")

    def hash_manifest(self, manifest, relative, required=()):
        rows = self.csv(manifest)
        field = "File" if rows and "File" in rows[0] else "Path"
        listed, ok = {}, True
        for r in rows:
            p = self.path(r[field], relative)
            if p in listed:
                ok = False
            listed[p] = r
            ok &= self.track(p).stat().st_size == int(number(r["Bytes"])) and self.sha(p) == r["SHA256"]
        ok &= all(self.path(p, relative) in listed for p in required)
        self.require(ok and bool(rows), "Hash manifest: " + self.rel(manifest), f"{len(rows)} entries; required membership and bytes/SHA256", [manifest])
        return listed

    def diagnostic(self, rows, name, expected_count=None):
        ok = bool(rows) and (expected_count is None or len(rows) == expected_count)
        for r in rows:
            ok &= r.get("Status") == "PASS"
            ok &= all(math.isfinite(number(r.get(f))) for f in ["MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI"])
            ok &= number(r.get("MaxRhat")) < 1.01 and number(r.get("MinBulkESS")) >= 400 and number(r.get("MinTailESS")) >= 400
            ok &= number(r.get("Divergences")) == 0 and number(r.get("TreeDepthHits")) == 0 and number(r.get("MinEBFMI")) > .3
        self.require(ok, name, "Rhat<1.01; bulk/tail ESS>=400; zero divergences/depth hits; E-BFMI>0.3")
        return ok

    def inputs(self):
        paths = {"snapshot": self.base / "source_snapshot/20260914.xlsx", "observations": self.base / "input/observations.csv",
                 "sites": self.base / "input/sites.csv", "tree": self.base / "input/tree.nwk", "map": self.base / "provenance/observation_source_map.csv"}
        self.require(all(self.sha(p) == FIXED_INPUT_HASHES[n] for n, p in paths.items()), "Frozen input hashes", paths=paths.values())
        proof = self.read_json(self.base / "review/input_independent_evidence.json")
        self.require(proof.get("status") == "PASS" and proof.get("errors") == [] and proof.get("input_drift") is False and
                     proof.get("numeric_cells_verified") == 266 and proof.get("input_hashes") == FIXED_INPUT_HASHES and
                     proof.get("id_contract_status") == "PASS", "Reuse bound independent 153-row XLSX/CSV comparison", paths=[self.base / "review/input_independent_evidence.json"])
        self.obs = self.csv(paths["observations"], ["RecordID", "ExperimentID", "Species", "Type", "Events", "Total", "Exact", "Lower", "Upper", "SourceID"])
        self.sites = self.csv(paths["sites"], ["Species", "Site3", "Site20", "Site117", "Site151", "Site196", "Site315"])
        self.species = [r["Species"] for r in self.sites]
        self.obs_by_id = {r["RecordID"]: r for r in self.obs}
        self.point_ids = {r["RecordID"] for r in self.obs if r["Type"] in {"count", "exact"}}
        self.interval_ids = {r["RecordID"] for r in self.obs if r["Type"] == "interval"}
        self.label_by_id = {r["RecordID"]: labels(r) for r in self.obs}
        self.binary_ids = {i for i, label in self.label_by_id.items() if label != "UNCLASSIFIED"}
        self.observed_species = {r["Species"] for r in self.obs}
        self.binary_species = {self.obs_by_id[i]["Species"] for i in self.binary_ids}
        self.require(len(self.obs) == len(self.obs_by_id) == len({r["ExperimentID"] for r in self.obs}) == 153 and
                     len(self.observed_species) == 51 and len(self.species) == len(set(self.species)) == 365 and
                     self.observed_species <= set(self.species) and len(self.binary_species) == 50,
                     "Input cardinality and ID multiplicity: 153/51/365/50")
        self.require(Counter(r["Type"] for r in self.obs) == Counter(count=105, exact=40, interval=8) and
                     Counter(self.label_by_id.values()) == Counter(HIGH=116, LOW=36, UNCLASSIFIED=1), "Type and classification contract")
        numeric_ok = True
        for r in self.obs:
            fields = {f for f in ["Events", "Total", "Exact", "Lower", "Upper"] if r[f] != ""}
            t = r["Type"]
            expected = {"count": {"Events", "Total"}, "exact": {"Exact"}, "interval": {"Lower", "Upper"}}[t]
            numeric_ok &= fields == expected and all(math.isfinite(number(r[f])) for f in fields)
            if t == "count":
                e, n = number(r["Events"]), number(r["Total"])
                numeric_ok &= 0 <= e <= n and n > 0 and e.is_integer() and n.is_integer()
            elif t == "exact":
                numeric_ok &= 0 < number(r["Exact"]) <= 1
            else:
                numeric_ok &= 0 <= number(r["Lower"]) < number(r["Upper"]) <= 1
        self.require(numeric_ok, "Original numerical types remain exclusive; no invented denominators or interval midpoints")
        mapped = self.csv(paths["map"])
        self.require(len(mapped) == 153 and {r["RecordID"] for r in mapped} == set(self.obs_by_id) and
                     all(r["CanonicalSpecies"] == r["OriginalSpecies"].replace(" ", "_") == self.obs_by_id[r["RecordID"]]["Species"] and
                         r["ExperimentID"] == self.obs_by_id[r["RecordID"]]["ExperimentID"] and r["HighLow"] == self.label_by_id[r["RecordID"]]
                         for r in mapped), "Source-row and species normalization mapping")
        prep = self.csv(self.run / "prepared_species.csv")
        self.require([r["Species"] for r in prep] == self.species, "Prepared panel order")
        pp = {r["Species"]: r for r in prep}
        rare_ok = True
        for site in ["Site3", "Site20", "Site117", "Site151", "Site196", "Site315"]:
            cleaned = {r["Species"]: ("MISSING" if r[site].strip().upper() in {"", "NA", "X", "-", "MISSING", "INDEL"} else r[site].strip().upper()) for r in self.sites}
            freq = Counter(x for x in cleaned.values() if x != "MISSING")
            for sp, aa in cleaned.items():
                expected = "MISSING" if aa == "MISSING" else (aa if freq[aa] >= 4 else "OTHER")
                rare_ok &= pp[sp]["M3_" + site] == expected
        self.require(rare_ok, "Actual prepared M3 encoding: counts1-3 OTHER, >=4 kept, MISSING distinct")
        self.bc = self.csv(self.run / "binary_counts.csv")
        count = defaultdict(Counter)
        for r in self.obs:
            count[r["Species"]][self.label_by_id[r["RecordID"]]] += 1
        self.require([r["Species"] for r in self.bc] == self.species and all(
            int(number(r["HighCount"])) == count[r["Species"]]["HIGH"] and
            int(number(r["LowCount"])) == count[r["Species"]]["LOW"] and
            int(number(r["Trials"])) == count[r["Species"]]["HIGH"] + count[r["Species"]]["LOW"] for r in self.bc), "Derived binary counts against all original records")
        rproof = self.read_json(self.base / "provenance/R_input_check.json")
        self.require(rproof.get("status") == "PASS" and rproof.get("rows") == 153 and rproof.get("panel_species") == 365 and
                     rproof.get("rooted_tree") is True and rproof.get("phylo_matrix_positive_definite") is True and
                     rproof.get("tree_species_set_matches") is True and rproof.get("rare_min") == 4 and
                     set(rproof.get("input_hashes", [])) == {FIXED_INPUT_HASHES[n] for n in ["observations", "sites", "tree"]},
                     "Reuse hash-bound R tree/root/positive-definiteness checks")

    def fit_selection(self):
        primary, sens = expected_jobs()
        plan = self.read_json(self.base / "provenance/fit_plan.json")
        planned = {(r["outcome"], r["variant"], r["model"]) for r in plan["main_jobs"]}
        self.require(planned == primary | sens and len(plan["main_jobs"]) == 36 and plan.get("planned_cv_refits") == 200,
                     "Planned 20 primary + 16 sensitivities + 200 CV folds")
        for p in sorted((self.base / "runs/job_receipts").glob("*/status.json")):
            z = self.read_json(p)
            if z.get("job", "").startswith("cv__"):
                self.cv_receipts.append((p, z))
            else:
                self.fit_receipts.append((p, z))
            if z.get("status") in {"ERROR", "NEEDS_REVIEW"}:
                self.warn("RETAINED_NONSELECTED_ATTEMPT_HISTORY", Receipt=self.rel(p), Job=z.get("job"), Status=z.get("status"))
        index = self.csv(self.run / "fit_index.csv", ["Outcome", "Variant", "Model", "Key", "RelativeFile", "FileSHA256"])
        for r in index:
            self.selected[(r["Outcome"], r["Variant"], r["Model"])] = r
        actual = set(self.selected)
        missing = (primary | sens) - actual
        if missing:
            self.mark("Selected fit completeness", "INCOMPLETE", json.dumps(sorted(missing)))
        self.require(actual <= primary | sens, "No unplanned selected primary/sensitivity structure")
        for item, r in self.selected.items():
            self.section("Selected fit " + "/".join(item), lambda item=item, r=r: self.audit_fit(item, r))
        self.primary_expected, self.sens_expected = primary, sens

    def audit_fit(self, item, r):
        o, v, m = item
        receipt = [(p, z) for p, z in self.fit_receipts if z.get("status") == "PASS" and z.get("key") == r["Key"] and
                   (z.get("outcome"), z.get("variant"), z.get("model")) == item]
        self.require(len(receipt) == 1, "Fit receipt identity " + "/".join(item))
        if len(receipt) != 1:
            return
        p, z = receipt[0]
        fit = self.path(r["RelativeFile"], self.run)
        self.require(self.sha(fit) == r["FileSHA256"] and z.get("relative_file") == r["RelativeFile"] and
                     fit.name == f"{m}_{r['Key'][:16]}.rds", "Fit file hash/name binding " + "/".join(item), paths=[fit, p])
        local_index = self.csv(p.parent / "fit_index.csv")
        self.require(any(all(x.get(k) == r.get(k) for k in ["Outcome", "Variant", "Model", "Key", "RelativeFile", "FileSHA256"]) for x in local_index),
                     "Selected global/local index agreement " + "/".join(item))
        sampling = z["sampling"]
        self.require(sampling["chains"] == 4 and sampling["iter"] >= 4000 and sampling["warmup"] >= 2000 and
                     sampling["iter"] > sampling["warmup"] and sampling["adapt_delta"] >= .99 and sampling["max_treedepth"] >= 12,
                     "Selected sampling settings " + "/".join(item))
        diags = self.csv(p.parent / "results" / f"diagnostics_{o}_{v}.csv")
        self.require(len(diags) == 1 and (diags[0]["Outcome"], diags[0]["Variant"], diags[0]["Model"], diags[0]["Key"]) == (o, v, m, r["Key"]),
                     "Per-job diagnostic identity " + "/".join(item))
        self.diagnostic(diags, "Per-job numerical diagnostics " + "/".join(item), 1)
        merged = self.csv(self.res / f"diagnostics_{o}_{v}.csv")
        use = [x for x in merged if x["Model"] == m]
        self.require(len(use) == 1 and use[0]["Key"] == r["Key"], "Merged diagnostic selection " + "/".join(item))
        self.diagnostic(use, "Merged numerical diagnostics " + "/".join(item), 1)
        if number(diags[0]["Rank"]) < number(diags[0]["DesignColumns"]):
            self.warn("RANK_DEFICIENT_SELECTED_MODEL", Outcome=o, Variant=v, Model=m, FitKey=r["Key"], Rank=diags[0]["Rank"], Columns=diags[0]["DesignColumns"])
        self.known_keys.add(r["Key"])

    def cv_selection(self):
        directories = self.csv(self.base / "provenance/cv_directory_manifest.csv")
        self.require(len(directories) == 4 and {(r["Outcome"], r["CVType"]) for r in directories} == {(o, d) for o in OUTCOMES for d in DESIGNS}, "Four distinct CV designs")
        self.cvdirs = {}
        for r in directories:
            o, d = r["Outcome"], r["CVType"]
            folder = self.path(r["Directory"])
            self.cvdirs[(o, d)] = folder
            self.foldkeys[(o, d)] = r["FoldKey"]
            self.known_keys.add(r["FoldKey"])
            f = self.csv(folder / "folds.csv", ["Species", "Fold"])
            expected = self.binary_species if o == "binary" else self.observed_species
            fmap = {x["Species"]: int(number(x["Fold"])) for x in f}
            self.require(len(f) == len(fmap) == len(expected) and set(fmap) == expected and set(fmap.values()) == set(range(1, 6)), "CV allocation " + o + "/" + d)
            self.foldmaps[(o, d)] = fmap
        entries = self.csv(self.base / "provenance/selected_cv_manifest.csv")
        for r in entries:
            item = r["Outcome"], r["CVType"], r["Model"]
            if item not in self.cvs or int(number(r["Attempt"])) > int(number(self.cvs[item]["Attempt"])):
                self.cvs[item] = r
        expected_cv = {(o, d, m) for o in OUTCOMES for d in DESIGNS for m in MODELS}
        self.require(set(self.cvs) <= expected_cv, "No unplanned CV structure")
        missing = expected_cv - set(self.cvs)
        if missing:
            self.mark("40 selected CV jobs / 200 folds", "INCOMPLETE", json.dumps(sorted(missing)))
        for item, r in self.cvs.items():
            self.section("CV " + "/".join(item), lambda item=item, r=r: self.audit_cv(item, r))
        if len(self.numerical_protocols) == 40:
            counts = Counter(self.numerical_protocols.values())
            self.require(counts == Counter({LEGACY_PROTOCOL: 35, STABLE_PROTOCOL: 5}),
                         "Exactly35 unchanged legacy exports and5 declared numerical repairs", str(dict(counts)))

    def numerical_compatibility_stage(self):
        parent_keys = {m: self.selected[("joint", "primary", m)]["Key"] for m in MODELS
                       if ("joint", "primary", m) in self.selected}
        if len(parent_keys) != 10:
            raise MissingEvidence("All10 selected joint parents are required for numerical compatibility evidence")
        value = validate_compatibility(self.base, parent_keys,
            csv_reader=lambda p: self.csv(p), sha=self.sha)
        self.numerical_compatibility = value
        self.sha(self.base / MATH_REVIEW)
        self.mark("All100 original joint folds meet fixed numerical-compatibility thresholds", "PASS",
            str({k: value[k] for k in ["rows", "original_nonfinite_heldout", "max_training_joint_log_difference", "max_original_finite_elpd_difference", "max_event_probability_difference"]}),
            [self.base / COMPAT_CSV, self.base / COMPAT_SOURCES, self.base / MATH_REVIEW])
        self.warn("FIXED_DRAW_NUMERICAL_SCORING_REPAIR", Method=STABLE_PROTOCOL, SamplingChanged=False,
            OriginalNonfiniteHeldout=value["original_nonfinite_heldout"], CompatibilityFolds=100,
            Scope="Stable evaluation of the same interval probability; original sampling and frozen model retained")

    def audit_cv(self, item, r):
        o, d, m = item
        key, parent_key = r["CVKey"], r["ParentKey"]
        parent = self.selected.get((o, "primary", m))
        if not parent:
            raise MissingEvidence("Missing corresponding selected primary " + str(item))
        cvfile = self.path(r["CVFile"])
        parentfile = self.path(r["ParentFile"])
        self.require(parent_key == parent["Key"] and parentfile == self.path(parent["RelativeFile"], self.run), "CV selected parent " + str(item))
        receipts = [(p, z) for p, z in self.cv_receipts if z.get("status") == "PASS" and z.get("key") == key and
                    (z.get("outcome"), z.get("cv_type"), z.get("model")) == item]
        self.require(len(receipts) == 1, "CV PASS receipt " + str(item))
        if len(receipts) != 1:
            return
        receipt, z = receipts[0]
        self.require(z.get("parent_key") == parent_key and self.path(z["cv_file"]) == cvfile and z["fold_key"] == self.foldkeys[(o, d)] and
                     cvfile.parent == self.cvdirs[(o, d)] and
                     cvfile.name == f"{m}_{key[:16]}.rds", "CV receipt file/key identity " + str(item))
        ix = self.csv(cvfile.parent / "cv_index.csv")
        selected_ix = {x["Model"]: x for x in ix}
        self.require(m in selected_ix and selected_ix[m]["Key"] == key and selected_ix[m]["ParentKey"] == parent_key and selected_ix[m]["Status"] == "PASS", "CV merged index " + str(item))
        diag = self.csv(receipt.parent / "fold_diagnostics.csv")
        self.require(len(diag) == 5 and {int(number(x["Fold"])) for x in diag} == set(range(1, 6)), "Five distinct CV diagnostic folds " + str(item))
        self.diagnostic(diag, "CV numerical diagnostics " + str(item), 5)
        samples = z["sampling"]
        self.require(samples["chains"] == 4 and samples["iter"] >= 4000 and samples["warmup"] >= 2000 and samples["iter"] > samples["warmup"], "CV four-chain sample settings " + str(item))
        ext = self.base / "derived/cv_extensions" / "_".join(item)
        manifest = self.read_json(ext / "postprocessing_manifest.json")
        numerical_method = validate_extension_manifest(self.base, manifest, sha=self.sha)
        validate_score_receipt_protocol(z, numerical_method)
        if numerical_method == STABLE_PROTOCOL:
            if self.numerical_compatibility is None:
                raise NumericalEvidenceIncomplete("The complete100-fold compatibility contract must pass before accepting repaired CV exports")
            validate_raw_fold_metadata(self.base, manifest, self.numerical_compatibility,
                                      cv_directory=cvfile.parent, sha=self.sha)
            self.require(z.get("sampling_changed") is False and
                z.get("likelihood_helper_sha256") == manifest.get("LikelihoodHelperSHA256"),
                "Stable receipt preserves original sampling and exact helper identity " + str(item))
        self.numerical_protocols[item] = numerical_method
        identity = {"Outcome": o, "CVType": d, "Model": m, "CVKey": key, "FitKey": parent_key, "FoldKey": z["fold_key"]}
        self.require(manifest.get("status") == "PASS" and all(manifest.get(k) == v for k, v in identity.items()) and
                     manifest["InputSHA256"]["CV"] == self.sha(cvfile) and manifest["InputSHA256"]["ParentFit"] == self.sha(parentfile),
                     "Extension bound to actual selected files and its exact approved evaluator " + str(item),
                     numerical_method, paths=[cvfile, ext / "postprocessing_manifest.json"])
        self.extensions[item] = {"path": ext, "manifest": manifest, "identity": identity}
        mc = self.csv(ext / "cv_fold_scores_mc.csv")
        scores = {int(number(x["Fold"])): number(x["ELPD"]) for x in self.csv(receipt.parent / "fold_scores.csv")}
        ok = len(mc) == 5 and {int(number(x["Fold"])) for x in mc} == set(range(1, 6))
        flagged = []
        for x in mc:
            f = int(number(x["Fold"]))
            ok &= all(x.get(k) == v for k, v in identity.items()) and close(x["ELPD"], scores[f], 1e-8) and abs(number(x["ELPDReconstructionDifference"])) < 1e-8
            expected_ids = {i for i in (self.binary_ids if o == "binary" else set(self.obs_by_id)) if self.foldmaps[(o, d)][self.obs_by_id[i]["Species"]] == f}
            listed = x["SourceRecordIDs"].split("|")
            ok &= len(listed) == len(set(listed)) == len(expected_ids) and set(listed) == expected_ids
            n_species = len({self.obs_by_id[i]["Species"] for i in expected_ids})
            ok &= (int(number(x["SpeciesCount"])) == n_species and int(number(x["ExperimentRecords"])) == len(expected_ids) and
                int(number(x["LikelihoodRows"])) == (n_species if o == "binary" else len(expected_ids)))
            reasons = []
            se = number(x["DeltaMethod_MCSE_LogPredictive"])
            if not math.isfinite(se): reasons.append("MCSE_NOT_FINITE")
            if math.isfinite(se) and se > .1: reasons.append("DELTA_LOG_MCSE_GT_0.1")
            if number(x["MaxNormalizedContribution"]) > .1: reasons.append("MAX_CONTRIBUTION_GT_0.1")
            if number(x["EffectiveContributionCount"]) < 100: reasons.append("EFFECTIVE_CONTRIBUTIONS_LT_100")
            if number(x["ChainLogPredictiveRange"]) > .5: reasons.append("CHAIN_LOG_SCORE_RANGE_GT_0.5")
            ok &= x["MCReviewStatus"] == ("REVIEW_REQUIRED" if reasons else "NO_SCREEN_FLAG") and x["MCReviewReasons"] == ";".join(reasons)
            if reasons:
                flagged.append(f)
                self.warn("CV_MC_REVIEW_RETAINED", Outcome=o, CVType=d, Model=m, Fold=f, CVKey=key, Reasons=reasons,
                          LogMCSE=se if math.isfinite(se) else None, EffectiveContributions=number(x["EffectiveContributionCount"]))
        self.require(ok, "Whole-fold ELPD/source coverage and unchanged MC flags " + str(item))
        mf = manifest.get("MCFlaggedFolds", [])
        mf = [mf] if isinstance(mf, (int, float)) else mf
        self.require(sorted(mf) == sorted(flagged), "Manifest preserves flagged CV folds " + str(item))
        segments = self.csv(ext / "cv_mc_chain_segments.csv")
        expected_segments = {(f, c, s) for f in range(1, 6) for c in range(5) for s in ["full", "first_half", "second_half"]}
        self.require(len(segments) == 75 and {(int(number(x["Fold"])), int(number(x["Chain"])), x["Segment"]) for x in segments} == expected_segments and
                     all(all(x.get(k) == v for k, v in identity.items()) and math.isfinite(number(x["LogPredictive"])) for x in segments), "Every chain/half-chain MC score retained " + str(item))
        checks = self.csv(ext / "source_draw_order_checks.csv")
        self.require(len(checks) == 5 and {int(number(x["Fold"])) for x in checks} == set(range(1, 6)) and all(
            all(x.get(k) == v for k, v in identity.items()) and x["NativeIterationChainMapping"] == "PASS" and x["HeldoutSourceOrder"] == "PASS" and
            number(x["MeanReconstructionMaxAbsError"]) < 1e-10 and number(x["OriginalMeanMedianMaxAbsError"]) < 1e-10 and
            number(x["OriginalMeanIntervalMaxAbsError"]) < 1e-10 and number(x["OriginalWholeFoldELPDAbsError"]) < 1e-7 for x in checks),
            "Reuse current-file source-draw and R-object checks " + str(item))
        self.track(ext / "oof_prediction_and_score_draws.rds")
        if o == "joint":
            self.audit_quant(item, identity, ext)
        self.known_keys.update([key, parent_key, z["fold_key"]])

    def audit_quant(self, item, identity, ext):
        o, d, m = item
        records = self.csv(ext / "quantitative_metrics_by_record.csv")
        predictive = self.csv(ext / "oof_predictive_summary.csv")
        intervals = self.csv(ext / "oof_interval_probability.csv")
        rp, pp = {x["RecordID"]: x for x in records}, {x["RecordID"]: x for x in predictive}
        ok = len(records) == len(rp) == len(predictive) == len(pp) == 145 and set(rp) == set(pp) == self.point_ids
        for i, r in rp.items():
            source, p = self.obs_by_id[i], pp[i]
            y = number(source["Events"]) / number(source["Total"]) if source["Type"] == "count" else number(source["Exact"])
            expected_fold = self.foldmaps[(o, d)][source["Species"]]
            ok &= all(r.get(k) == v and p.get(k) == v for k, v in identity.items())
            ok &= r["Species"] == p["Species"] == source["Species"] and r["Type"] == p["Type"] == source["Type"]
            ok &= int(number(r["Fold"])) == int(number(p["Fold"])) == expected_fold and r["PointRule"] == POINT_RULE
            ok &= close(r["ObservedRatio"], y, 1e-12) and close(r["PointPrediction"], p["OOFMeanPosteriorMean"], 1e-12)
            ok &= close(r["AbsoluteError"], abs(number(r["PointPrediction"]) - y), 1e-12) and close(r["SquaredError"], (number(r["PointPrediction"]) - y)**2, 1e-12)
            ok &= math.isfinite(number(r["CRPS"])) and 0 <= number(r["CRPS"]) <= 1 + 1e-12
            for level in [50, 95]:
                lo, hi = number(p[f"PredictiveLower{level}"]), number(p[f"PredictiveUpper{level}"])
                # R CSV output rounds some rational count quantiles (e.g.25/30)
                # at the final decimal. This tolerance only reconciles CSV
                # serialization, not a change to the source predictive interval.
                inside = (lo <= y or close(lo, y, 1e-12)) and (y <= hi or close(y, hi, 1e-12))
                ok &= 0 <= lo <= hi <= 1 and truth(r[f"Covered{level}"]) == inside and close(r[f"PredictiveWidth{level}"], hi - lo, 1e-12)
            ok &= r["LevelSeenInTraining"] == p["LevelSeenInTraining"] and r["FixedEffectEstimable"] == p["FixedEffectEstimable"]
        self.require(ok, "145 count/exact OOF identities, mean(m), losses, and future coverage " + str(item))
        interval_ok = len(intervals) == 8 and {x["RecordID"] for x in intervals} == self.interval_ids
        for x in intervals:
            source = self.obs_by_id[x["RecordID"]]
            interval_ok &= (all(x.get(k) == v for k, v in identity.items()) and x["Type"] == "interval" and
                close(x["Lower"], source["Lower"], 1e-12) and close(x["Upper"], source["Upper"], 1e-12) and
                0 <= number(x["PredictiveEventProbability"]) <= 1 and x["Status"] == "EVENT_PROBABILITY_ONLY_NO_POINT_SCORE")
        self.require(interval_ok, "Eight original intervals have event probability only " + str(item))
        for filename, by_fold in [("quantitative_metrics_summary.csv", False), ("quantitative_metrics_by_fold.csv", True)]:
            summaries = self.csv(ext / filename)
            expected = {(f, t) for f in (range(1, 6) if by_fold else [None]) for t in ["count+exact", "count", "exact"]
                        if any((f is None or int(number(x["Fold"])) == f) and (t == "count+exact" or x["Type"] == t) for x in records)}
            actual = {(int(number(x["Fold"])) if by_fold else None, x["Type"]) for x in summaries}
            aggregate_ok = len(summaries) == len(expected) and actual == expected
            for row in summaries:
                f = int(number(row["Fold"])) if by_fold else None
                z = [x for x in records if (f is None or int(number(x["Fold"])) == f) and (row["Type"] == "count+exact" or x["Type"] == row["Type"])]
                ids = row["SourceRecordIDs"].split("|")
                aggregate_ok &= all(row.get(k) == v for k, v in identity.items()) and row["PointRule"] == POINT_RULE and row["Weighting"] == "equal_weight_per_experiment"
                aggregate_ok &= len(ids) == len(set(ids)) == len(z) and set(ids) == {x["RecordID"] for x in z} and int(number(row["NRecords"])) == len(z) and int(number(row["NSpecies"])) == len({x["Species"] for x in z})
                if z:
                    expected_values = {"MAE": statistics.mean(number(x["AbsoluteError"]) for x in z), "RMSE": math.sqrt(statistics.mean(number(x["SquaredError"]) for x in z)),
                                       "CRPS": statistics.mean(number(x["CRPS"]) for x in z), "Coverage50": statistics.mean(truth(x["Covered50"]) for x in z), "Coverage95": statistics.mean(truth(x["Covered95"]) for x in z)}
                    aggregate_ok &= all(close(row[k], v, 1e-12) for k, v in expected_values.items())
            self.require(aggregate_ok, "Recomputed experiment-weighted quantitative summaries " + str(item) + "/" + filename)

    def primary_outputs(self):
        state_file = self.res / "postfit_primary_status.json"
        state = self.read_json(state_file)
        if state.get("status") not in {"COMPLETE_ALL_PREDICTION_AND_LOO_GATES_PASS", "COMPLETE_WITH_GROUPED_CV_REQUIRED"}:
            raise MissingEvidence("Primary postfit not complete: " + str(state.get("status")))
        self.require(state.get("formal_output_gate") == "PASS_ALL_20_IDENTITIES_AND_DIAGNOSTICS" and
                     state.get("primary_models") == state.get("ppc_models") == 20 and state.get("species_long_rows") == 2190 and state.get("species_wide_rows") == 365,
                     "Primary postfit explicit gates/counts")
        self.require(state["prepared_sha256"] == self.sha(self.run / "prepared.rds") and
                     all(self.sha(self.path(p)) == h for p, h in state["script_sha256"].items()), "Primary postfit bound prepared object and runner code")
        audit_dir = self.path(state["audit_directory"])
        selection = self.csv(audit_dir / "selected_primary_fits.csv")
        self.require(len(selection) == 20 and {(r["Outcome"], r["Variant"], r["Model"]) for r in selection} == self.primary_expected and all(
            self.selected.get((r["Outcome"], r["Variant"], r["Model"]), {}).get("Key") == r["Key"] and
            self.selected.get((r["Outcome"], r["Variant"], r["Model"]), {}).get("FileSHA256") == r["FileSHA256"] for r in selection),
            "Reused primary R-object verification uses current20 selections")
        required = [self.res / n for n in ["diagnostics_all_primary.csv", "species_predictions_long.csv", "species_predictions_wide.csv", "expected_value_draws.rds",
                    "model_comparison_status_primary.csv", "ppc_summary_all_primary.csv", "ppc_observed_plot_data_primary.csv", "ppc_statistic_plot_data_primary.csv", "ppc_ecdf_plot_data_primary.csv", "interval_check_all_primary.csv"]]
        self.hash_manifest(self.path(state["output_manifest"]), self.run, required)
        ds = self.csv(self.res / "diagnostics_all_primary.csv")
        self.require({(x["Outcome"], x["Variant"], x["Model"]) for x in ds} == self.primary_expected and all(
            x["Key"] == self.selected[(x["Outcome"], x["Variant"], x["Model"])]["Key"] for x in ds), "Primary final diagnostic key coverage")
        self.diagnostic(ds, "All20 final primary numerical summaries", 20)
        for o in OUTCOMES:
            self.section("LOO gate " + o, lambda o=o: self.loo_gate(o))
        self.ppc_outputs("primary", self.primary_expected)
        long = self.csv(self.res / "species_predictions_long.csv")
        wide = self.csv(self.res / "species_predictions_wide.csv")
        indexed = {(r["Model"], r["Species"]): r for r in long}
        expected = {(m, s) for m in SIX for s in self.species}
        self.require(len(long) == len(indexed) == 2190 and set(indexed) == expected and len(wide) == 365 and [r["Species"] for r in wide] == self.species,
                     "07 complete long2190/wide365 universe")
        correct = True
        for r in long:
            for prefix, columns, seen in [("Binary", ["PrHighLower95", "PrHigh", "PrHighUpper95"], self.binary_species),
                                           ("Ratio", ["RatioLower95", "PredictedRatio", "RatioUpper95"], self.observed_species)]:
                values = [number(r[c]) for c in columns]
                supported = truth(r[prefix + "Supported"])
                correct &= (all(math.isfinite(x) for x in values) and 0 <= values[0] <= values[1] <= values[2] <= 1) if supported else all(math.isnan(x) for x in values)
                correct &= r[prefix + "DataStatus"] == ("observed" if r["Species"] in seen else "unlabelled_projection")
                note = "unseen_level_no_numeric_prediction" if not supported else (
                    "prior_dependent_unidentified_direction" if not truth(r[prefix + "FixedEffectEstimable"]) else
                    ("observed_combination" if truth(r[prefix + "CombinationSeen"]) else "new_combination"))
                correct &= r[prefix + "PredictionNote"] == note
        for w in wide:
            for m in SIX:
                r = indexed[(m, w["Species"])]
                correct &= all(m + "_" + c in w and same_cell(w[m + "_" + c], v) for c, v in r.items() if c not in {"Species", "Model"})
        self.require(correct, "07 probability bounds, unsupported masks, evidence flags and every wide/long cell")

    def loo_gate(self, outcome):
        status = self.csv(self.res / f"loo_status_{outcome}_primary.csv")
        source = self.csv(self.res / f"loo_source_means_{outcome}_primary.csv")
        expected_ids = {"binary:" + s for s in self.binary_species} if outcome == "binary" else set(self.obs_by_id)
        ok = len(status) == 10 and {x["Model"] for x in status} == set(MODELS)
        bad_models = []
        for r in status:
            z = [x for x in source if x["Model"] == r["Model"]]
            k_limit = number(r["KLimit"])
            bad = sum(not math.isfinite(number(x["ParetoK"])) or number(x["ParetoK"]) > k_limit for x in z)
            ok &= len(z) == len(expected_ids) and {x["RecordID"] for x in z} == expected_ids
            ok &= int(number(r["ProblemRows"])) == bad and r["Status"] == ("USE_GROUPED_CV" if bad else "PASS")
            if bad:
                bad_models.append(r["Model"])
        routes = self.csv(self.res / "model_comparison_status_primary.csv")
        chosen = [r for r in routes if r["Outcome"] == outcome]
        ok &= len(chosen) == 1 and chosen[0]["RankingStatus"] == ("REFUSED_USE_GROUPED_CV" if bad_models else "PASS")
        ranking = self.res / f"model_comparison_{outcome}_primary.csv"
        if bad_models:
            ok &= not ranking.exists()
            self.warn("LOO_RANKING_REFUSED_AS_REQUIRED", Outcome=outcome, Models=bad_models)
        else:
            tab = self.csv(ranking)
            ok &= len(tab) == 10 and {r["Model"] for r in tab} == set(MODELS)
        self.require(ok, "PSIS failures retained and unreliable ranking refused " + outcome)

    def ppc_outputs(self, suffix, jobs):
        summary = self.csv(self.res / f"ppc_summary_all_{suffix}.csv")
        observed = self.csv(self.res / f"ppc_observed_plot_data_{suffix}.csv")
        statistics_rows = self.csv(self.res / f"ppc_statistic_plot_data_{suffix}.csv")
        ecdf = self.csv(self.res / f"ppc_ecdf_plot_data_{suffix}.csv")
        intervals = self.csv(self.res / f"interval_check_all_{suffix}.csv")
        expected_groups = {(o, v, m, t) for o, v, m in jobs for t in (["HighFraction"] if o == "binary" else ["count", "exact"])}
        group = lambda r: (r["Outcome"], r["Variant"], r["Model"], r["Subset"])
        ok = len(summary) == len(expected_groups) and {group(r) for r in summary} == expected_groups
        bc = {"binary:" + r["Species"]: r for r in self.bc if number(r["Trials"]) > 0}
        for o, v, m, t in expected_groups:
            key = self.selected.get((o, v, m), {}).get("Key")
            rows = [r for r in observed if group(r) == (o, v, m, t)]
            expected_ids = set(bc) if o == "binary" else {i for i, r in self.obs_by_id.items() if r["Type"] == t}
            ok &= len(rows) == len(expected_ids) and {r["RecordID"] for r in rows} == expected_ids and all(r["Key"] == key for r in rows)
            for r in rows:
                sr = bc[r["RecordID"]] if o == "binary" else self.obs_by_id[r["RecordID"]]
                y = number(sr["HighCount"]) / number(sr["Trials"]) if o == "binary" else (
                    number(sr["Events"]) / number(sr["Total"]) if t == "count" else number(sr["Exact"]))
                ok &= close(r["Observed"], y, 1e-12) and r["Species"] == sr["Species"]
            ss = [r for r in statistics_rows if group(r) == (o, v, m, t)]
            ok &= len(ss) == 500 and {int(number(r["Replicate"])) for r in ss} == set(range(1, 501)) and all(
                r["Key"] == key and all(math.isfinite(number(r[c])) for c in ["Mean", "SD", "ZeroFraction", "OneFraction"]) for r in ss)
            ee = [r for r in ecdf if group(r) == (o, v, m, t)]
            ok &= {int(number(r["Replicate"])) for r in ee} == set(range(51)) and all(
                r["Key"] == key and 0 <= number(r["X"]) <= 1 and 0 <= number(r["ECDF"]) <= 1 for r in ee)
        expected_int = {(o, v, m, i) for o, v, m in jobs if o == "joint" for i in self.interval_ids}
        ok &= len(intervals) == len(expected_int) and {(r["Outcome"], r["Variant"], r["Model"], r["RecordID"]) for r in intervals} == expected_int
        ok &= all(r["Key"] == self.selected[(r["Outcome"], r["Variant"], r["Model"])]["Key"] and
                  close(r["Lower"], self.obs_by_id[r["RecordID"]]["Lower"], 1e-12) and close(r["Upper"], self.obs_by_id[r["RecordID"]]["Upper"], 1e-12) and
                  0 <= number(r["PosteriorMeanIntervalProbability"]) <= 1 for r in intervals)
        self.require(ok, "Complete keyed training PPC/ECDF and original interval checks " + suffix)

    def sensitivity_outputs(self):
        state = self.read_json(self.res / "postfit_sensitivity_status.json")
        if state.get("status") != "COMPLETE_DIAGNOSTICS_AND_TRAINING_PPC":
            raise MissingEvidence("Sensitivity postfit not complete: " + str(state.get("status")))
        self.require(state.get("comparison_rows") == 5840 and state.get("ppc_models") == 16 and
                     state.get("fit_plan_sha256") == self.sha(self.base / "provenance/fit_plan.json"), "Sensitivity postfit explicit coverage/plan identity")
        required = [self.res / n for n in ["sensitivity_expected_values_long.csv", "diagnostics_all_sensitivity.csv", "ppc_summary_all_sensitivity.csv",
                    "ppc_observed_plot_data_sensitivity.csv", "ppc_statistic_plot_data_sensitivity.csv", "ppc_ecdf_plot_data_sensitivity.csv", "interval_check_all_sensitivity.csv"]]
        self.hash_manifest(self.path(state["output_manifest"]), self.run, required)
        selection = self.csv(self.path(state["audit_directory"]) / "selected_fits.csv")
        self.require(all(self.selected[(r["Outcome"], r["Variant"], r["Model"])]["Key"] == r["Key"] and
                         self.selected[(r["Outcome"], r["Variant"], r["Model"])]["FileSHA256"] == r["FileSHA256"] for r in selection) and
                     self.sens_expected <= {(r["Outcome"], r["Variant"], r["Model"]) for r in selection}, "Sensitivity R verification uses current16 fits and their current primaries")
        ds = self.csv(self.res / "diagnostics_all_sensitivity.csv")
        self.require({(r["Outcome"], r["Variant"], r["Model"]) for r in ds} == self.sens_expected and all(
            r["Key"] == self.selected[(r["Outcome"], r["Variant"], r["Model"])]["Key"] for r in ds), "Sensitivity final diagnostic key coverage")
        self.diagnostic(ds, "All16 sensitivity numerical summaries", 16)
        rows = self.csv(self.res / "sensitivity_expected_values_long.csv")
        expected = {(o, v, m, s) for o, v, m in self.sens_expected for s in self.species}
        ok = len(rows) == 5840 and {(r["Outcome"], r["Variant"], r["Model"], r["Species"]) for r in rows} == expected
        for r in rows:
            item = r["Outcome"], r["Variant"], r["Model"]
            ok &= r["AlternativeKey"] == self.selected[item]["Key"] and r["PrimaryKey"] == self.selected[(item[0], "primary", item[2])]["Key"]
            fields = ["PrimaryMedian", "AlternativeMedian", "MedianShift", "PrimaryLower", "PrimaryUpper", "AlternativeLower", "AlternativeUpper"]
            if truth(r["Supported"]):
                ok &= all(math.isfinite(number(r[c])) for c in fields) and close(r["MedianShift"], number(r["AlternativeMedian"]) - number(r["PrimaryMedian"]), 1e-12)
                ok &= 0 <= number(r["PrimaryLower"]) <= number(r["PrimaryMedian"]) <= number(r["PrimaryUpper"]) <= 1
                ok &= 0 <= number(r["AlternativeLower"]) <= number(r["AlternativeMedian"]) <= number(r["AlternativeUpper"]) <= 1
            else:
                ok &= all(math.isnan(number(r[c])) for c in fields)
        self.require(ok, "16x365 sensitivity means, intervals, masks and parent/alternative keys")
        self.ppc_outputs("sensitivity", self.sens_expected)

    def comparison_outputs(self):
        state = self.read_json(self.base / "derived/cv_comparisons/postfit_cv_status.json")
        if state.get("status") != "COMPLETE_KEEP_MC_AND_AUC_LIMITATIONS":
            raise MissingEvidence("All-design CV postprocessing not complete")
        self.require(state.get("cv_designs") == 4 and state.get("cv_models") == 40 and state.get("fold_fits") == 200 and state.get("point_metric_rule") == POINT_RULE,
                     "CV aggregate explicit40/200 scope and estimand")
        if self.numerical_compatibility is None:
            raise NumericalEvidenceIncomplete("Final CV comparison lacks completed numerical compatibility evidence")
        self.require(state.get("numerical_likelihood_method") == STABLE_PROTOCOL and state.get("numerical_compatibility_folds") == 100 and
                     state.get("legacy_score_exports") == 35 and state.get("stable_score_exports") == 5 and
                     state.get("compatibility_manifest_sha256") == self.numerical_compatibility["manifest_sha256"],
                     "Final CV status retains explicit35/5 numerical protocols and unchanged target")
        methods = self.csv(self.base / "derived/cv_comparisons/cv_numerical_protocols.csv")
        self.require(len(methods) == 40 and len({(r["Outcome"],r["CVType"],r["Model"]) for r in methods}) == 40 and all(
            r["NumericalLikelihoodMethod"] == self.numerical_protocols.get((r["Outcome"],r["CVType"],r["Model"])) and
            r["CVKey"] == self.cvs[(r["Outcome"],r["CVType"],r["Model"])]["CVKey"] for r in methods),
            "Current score-protocol table covers every CV key")
        for o in OUTCOMES:
            for d in DESIGNS:
                self.section("Comparison " + o + "/" + d, lambda o=o, d=d: self.audit_comparison(o, d))
        for d in DESIGNS:
            self.section("ROC/AUC/calibration/Brier " + d, lambda d=d: self.audit_auc(d))

    def audit_comparison(self, o, d):
        folder = self.base / "derived/cv_comparisons" / (o + "_" + d)
        comp = self.csv(folder / "cv_model_comparison_with_mc.csv")
        mc = self.csv(folder / "cv_fold_scores_with_mc.csv")
        self.require(len(comp) == 10 and {r["Model"] for r in comp} == set(MODELS) and len(mc) == 50 and
                     {(r["Model"], int(number(r["Fold"]))) for r in mc} == {(m, f) for m in MODELS for f in range(1, 6)}, "Ten-model/fifty-fold comparison coverage " + o + "/" + d)
        bymodel = {m: sorted([r for r in mc if r["Model"] == m], key=lambda x: number(x["Fold"])) for m in MODELS}
        totals = {m: sum(number(r["ELPD"]) for r in bymodel[m]) for m in MODELS}
        zero = max(totals, key=totals.get)
        ok = True
        any_flags = any(r["MCReviewStatus"] != "NO_SCREEN_FLAG" for r in mc)
        for r in comp:
            m = r["Model"]
            extension = self.extensions.get((o, d, m))
            if extension is None:
                raise MissingEvidence("Missing audited extension " + str((o, d, m)))
            src = self.csv(extension["path"] / "cv_fold_scores_mc.csv")
            srcmap = {int(number(x["Fold"])): x for x in src}
            ok &= all(all(x.get(c) == srcmap[int(number(x["Fold"]))].get(c) for c in ["CVKey", "FitKey", "FoldKey", "MCReviewStatus", "MCReviewReasons"]) and
                      close(x["ELPD"], srcmap[int(number(x["Fold"]))]["ELPD"], 1e-10) for x in bymodel[m])
            delta = [number(a["ELPD"]) - number(b["ELPD"]) for a, b in zip(bymodel[m], bymodel[zero])]
            ok &= close(r["ELPD"], totals[m], 1e-8) and close(r["ELPD_Difference"], sum(delta), 1e-8) and close(r["PairedSE"], math.sqrt(5 * statistics.variance(delta)), 1e-8)
            ok &= r["ReferenceModel"] == zero and int(number(r["MCFlaggedFolds"])) == sum(x["MCReviewStatus"] != "NO_SCREEN_FLAG" for x in src)
            ok &= truth(r["AnyModelMCReview"]) == any_flags and ("NO_DEFINITIVE_RANK" in r["Interpretation"] if any_flags else "NOT_PROOF_OF_UNIQUE_BEST" in r["Interpretation"])
        self.require(ok, "Original paired whole-fold scores and all MC flags retained " + o + "/" + d)
        diag = self.csv(folder / "cv_fold_diagnostics.csv")
        self.require(len(diag) == 50 and all(r["CVKey"] == self.cvs[(o, d, r["Model"])]["CVKey"] and
                     r["ParentKey"] == self.cvs[(o, d, r["Model"])]["ParentKey"] for r in diag), "Aggregate CV diagnostic identities " + o + "/" + d)
        self.diagnostic(diag, "Aggregate50 fold diagnostics " + o + "/" + d, 50)

    def audit_auc(self, design):
        folder = self.base / "derived/cv_comparisons" / ("binary_" + design)
        data = self.csv(folder / "roc_oof_experiments.csv")
        byfold = self.csv(folder / "auc_by_fold.csv")
        summaries = self.csv(folder / "auc_summary.csv")
        coords = self.csv(folder / "roc_coordinates_by_fold.csv")
        bins = self.csv(folder / "calibration_bins.csv")
        species_rows = self.csv(folder / "calibration_species.csv")
        briers = self.csv(folder / "brier_scores.csv")
        self.require(len(data) == 1520 and len({(r["Model"], r["RecordID"]) for r in data}) == 1520 and len(byfold) == 50 and len(summaries) == 10,
                     "AUC ten-model record/fold coverage " + design)
        ok = True
        keys = {r["AUCKey"] for r in data}
        ok &= len(keys) == 1
        self.known_keys.update(keys)
        source_dirs = {r["SourceDirectory"] for r in data}
        if len(source_dirs) != 1:
            raise ValueError("AUC tables mix source directories")
        source_dir = self.path(next(iter(source_dirs)))
        receipts = self.csv(source_dir / "auc_source_receipts.csv")
        ok &= len(receipts) == 10 and {r["Model"] for r in receipts} == set(MODELS)
        for receipt in receipts:
            cv = self.cvs[("binary", design, receipt["Model"])]
            ok &= receipt["CVKey"] == cv["CVKey"] and receipt["ParentKey"] == cv["ParentKey"] and receipt["CVFileSHA256"] == self.sha(self.path(cv["CVFile"]))
        for m in MODELS:
            rows = [r for r in data if r["Model"] == m]
            ok &= len(rows) == 152 and {r["RecordID"] for r in rows} == self.binary_ids
            for r in rows:
                sr = self.obs_by_id[r["RecordID"]]
                ok &= r["Species"] == sr["Species"] and r["SourceID"] == sr["SourceID"] and int(number(r["High"])) == (self.label_by_id[r["RecordID"]] == "HIGH")
                ok &= int(number(r["Fold"])) == self.foldmaps[("binary", design)][r["Species"]] and 0 <= number(r["OOFPrHigh"]) <= 1
            values = []
            for f in range(1, 6):
                part = [r for r in rows if int(number(r["Fold"])) == f]
                actual = [r for r in byfold if r["Model"] == m and int(number(r["Fold"])) == f]
                score = auc_rank(part); values.append(score)
                if len(actual) != 1:
                    ok = False; continue
                a = actual[0]
                nh = sum(int(number(r["High"])) for r in part); nl = len(part) - nh
                ok &= int(number(a["Records"])) == len(part) and int(number(a["High"])) == nh and int(number(a["Low"])) == nl
                if math.isfinite(score):
                    ok &= a["Status"] == "DEFINED" and close(a["AUC"], score, 1e-12)
                else:
                    ok &= a["Status"] == "NOT_DEFINED_ONE_CLASS" and math.isnan(number(a["AUC"]))
                    ok &= not any(x["Model"] == m and int(number(x["Fold"])) == f for x in coords)
            summary = [r for r in summaries if r["Model"] == m]
            if len(summary) != 1:
                ok = False; continue
            s = summary[0]
            defined = all(math.isfinite(v) for v in values)
            ok &= s["Status"] == ("DEFINED" if defined else "NOT_DEFINED_ONE_CLASS_FOLD") and int(number(s["ValidFolds"])) == sum(math.isfinite(v) for v in values)
            ok &= close(s["CV_AUC"], statistics.mean(values), 1e-12) if defined else math.isnan(number(s["CV_AUC"]))
            ok &= defined == (design == "species")
            for b in range(1, 6):
                part = [r for r in rows if min(5, 1 + sum(number(r["OOFPrHigh"]) >= edge for edge in [.2, .4, .6, .8])) == b]
                actual = [r for r in bins if r["Model"] == m and int(number(r["Bin"])) == b]
                if len(actual) != 1:
                    ok = False; continue
                a = actual[0]
                ok &= int(number(a["Records"])) == len(part) and int(number(a["Species"])) == len({r["Species"] for r in part}) and truth(a["UpperInclusive"]) == (b == 5)
                ok &= close(a["Lower"], [0, .2, .4, .6, .8][b-1], 1e-12) and close(a["Upper"], [.2, .4, .6, .8, 1][b-1], 1e-12)
                ok &= close(a["MeanForecastScore"], statistics.mean(number(r["OOFPrHigh"]) for r in part), 1e-12) if part else math.isnan(number(a["MeanForecastScore"]))
                ok &= close(a["ObservedHighFraction"], statistics.mean(number(r["High"]) for r in part), 1e-12) if part else math.isnan(number(a["ObservedHighFraction"]))
            for f in [None, 1, 2, 3, 4, 5]:
                part = rows if f is None else [r for r in rows if int(number(r["Fold"])) == f]
                actual = [r for r in briers if r["Model"] == m and ((math.isnan(number(r["Fold"])) and f is None) or (f is not None and number(r["Fold"]) == f))]
                if len(actual) != 1:
                    ok = False; continue
                a = actual[0]
                loss = statistics.mean((number(r["OOFPrHigh"]) - number(r["High"]))**2 for r in part)
                ok &= close(a["BrierScore"], loss, 1e-12) and a["Weighting"] == "equal_weight_per_experiment" and int(number(a["Records"])) == len(part)
        self.require(ok, "Exact tied-rank AUC, single-class NA, calibration boundaries/counts, and experiment-weighted Brier " + design)
        self.require(len(species_rows) == 500 and {(r["Model"], r["Species"]) for r in species_rows} == {(m, s) for m in MODELS for s in self.binary_species}, "Species calibration retains500 model/species rows " + design)
        if design == "phylo_distance":
            self.warn("PHYLOGENETIC_AUC_UNDEFINED_AS_REQUIRED", SingleClassFolds=[3, 4], Reason="Only HIGH in two fixed blocks; total CV_AUC stays NA")

    def matrices(self):
        for o in OUTCOMES:
            self.section("Matrix check " + o, lambda o=o: self.matrix(o))

    def matrix(self, outcome):
        parent = self.selected.get((outcome, "primary", "M3_P"))
        if not parent:
            raise MissingEvidence("Selected M3_P parent not complete")
        root = self.run / "matrix_checks" / (outcome + "_M3_P") / ("parent_" + parent["Key"][:16])
        attempts = [(p, self.read_json(p)) for p in sorted(root.glob("attempt_*/status.json"))]
        for p, s in attempts:
            if s.get("status") in {"ERROR", "NEEDS_REVIEW"}:
                self.warn("RETAINED_MATRIX_ATTEMPT_HISTORY", Outcome=outcome, Receipt=self.rel(p), Status=s.get("status"), Attempt=s.get("attempt"))
        completed = [(p, s) for p, s in attempts if s.get("status") in {"COMPLETE_WITH_REVIEW_DIFFERENCES", "COMPLETE_WITHIN_2_MCSE"}]
        if not completed:
            raise MissingEvidence("No completed current-parent matrix check; attempts=" + str([(s.get("attempt"), s.get("status")) for _, s in attempts]))
        self.require(len(completed) == 1, "One selected matrix completion " + outcome)
        path, state = completed[-1]
        check_key = state["check_key"]
        self.known_keys.add(check_key)
        expected_sp = self.binary_species if outcome == "binary" else self.observed_species
        self.require(state["parent_key"] == parent["Key"] and state["model"] == "M3_P" and state["outcome"] == outcome and
                     state["full_species"] == 365 and state["submatrix_species"] == len(expected_sp) and
                     set(state["check_request"]["species"]) == expected_sp and state["check_request"]["parent_key"] == parent["Key"] and
                     state["check_request"]["seed"] == 20260817 + 100001 and state.get("retry_eligible") is False,
                     "Matrix selected parent/submatrix universe/fixed-seed identity " + outcome)
        source_hashes = state["input_hashes"]
        source_hashes = source_hashes.values() if isinstance(source_hashes, dict) else source_hashes
        self.require(set(source_hashes) == {FIXED_INPUT_HASHES[n] for n in ["observations", "sites", "tree"]}, "Matrix source input hashes " + outcome)
        self.require(self.sha(self.path(state["submatrix_file"])) == state["submatrix_file_sha256"], "Matrix subfit file hash " + outcome)
        self.hash_manifest(path.parent / "output_manifest.csv", path.parent,
                           [path.parent / n for n in ["matrix_diagnostics_status.csv", "matrix_diagnostics_chains.csv", "matrix_diagnostics_parameters.csv", "matrix_diagnostics_quantities.csv", "matrix_comparison_plot_data.csv", "matrix_comparison_evidence.rds", "request_identity.rds"]])
        ds = self.csv(path.parent / "matrix_diagnostics_status.csv")
        self.require(len(ds) == 2 and {r["Side"] for r in ds} == {"full", "sub"}, "Both full/submatrix diagnostic sides " + outcome)
        self.diagnostic(ds, "Matrix full/sub selected numerical diagnostics " + outcome, 2)
        self.require(all(number(r["MaxComparisonRhat"]) < 1.01 and number(r["MinComparisonBulkESS"]) >= 400 and number(r["MinComparisonTailESS"]) >= 400 and
                         number(r["MinimumComparisonMCSE"]) > 0 and truth(r["AllFinite"]) for r in ds), "Matrix comparison-quantity precision " + outcome)
        comp = self.csv(self.path(state["plot_data_file"]))
        ok = bool(comp) and len({r["Quantity"] for r in comp}) == len(comp)
        flagged = []
        for r in comp:
            diff, mcse = number(r["Difference"]), number(r["JointMCSE"])
            expected_flag = "within_2_MCSE" if abs(diff) <= 2 * mcse else "review_difference"
            ok &= r["Outcome"] == outcome and r["Model"] == "M3_P" and r["ParentKey"] == parent["Key"] and r["CheckKey"] == check_key
            ok &= math.isfinite(diff) and math.isfinite(mcse) and mcse > 0 and close(diff, number(r["FullMean"]) - number(r["SubmatrixMean"]), 1e-12) and r["ReviewFlag"] == expected_flag
            if expected_flag == "review_difference":
                flagged.append(r["Quantity"])
        ok &= state["review_differences"] == len(flagged) and state["status"] == ("COMPLETE_WITH_REVIEW_DIFFERENCES" if flagged else "COMPLETE_WITHIN_2_MCSE")
        self.require(ok, "Original2xMCSE differences and completion flags retained " + outcome)
        if flagged:
            self.warn("MATRIX_REVIEW_DIFFERENCES_RETAINED_NOT_FAILURE", Outcome=outcome, ParentKey=parent["Key"], CheckKey=check_key, Quantities=flagged)

    def finish(self):
        drift = []
        for p, state in self.states.items():
            if not p.exists() or (p.stat().st_size, p.stat().st_mtime_ns) != state:
                drift.append(self.rel(p))
        if drift:
            self.mark("Evidence remained stable during acceptance", "INCOMPLETE", json.dumps(drift))
        else:
            self.mark("Evidence remained stable during acceptance", "PASS", f"{len(self.states)} read files")
        counts = Counter(x["Status"] for x in self.checks)
        status = "FAIL" if counts["FAIL"] else ("INCOMPLETE" if counts["INCOMPLETE"] else "PASS")
        result = {"version": VERSION, "audit_script_sha256": self.audit_script_sha,
                  "numerical_contract_sha256": self.numerical_contract_sha, "status": status, "complete": status.startswith("PASS"), "started_at": self.started,
                  "finished_at": datetime.now(timezone.utc).isoformat(), "analysis_root": str(self.base), "run": self.rel(self.run),
                  "check_counts": dict(counts), "checks": self.checks, "retained_review_flags": self.flags,
                  "files_hashed": {self.rel(p): h for p, h in self.hash_cache.items()},
                  "scope": "Read-only artifact, numerical-summary, selection, coverage, and hash audit; does not rerun models or recompute raw-chain Rhat",
                  "new_models_started": False, "input_files_modified": False}
        result["complete_with_retained_review_flags"] = status == "PASS" and bool(self.flags)
        result["review_flag_count"] = len(self.flags)
        target = self.base / "review"
        target.mkdir(parents=True, exist_ok=True)
        (target / "final_acceptance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
        with (target / "final_acceptance.csv").open("w", encoding="utf-8-sig", newline="") as stream:
            w = csv.DictWriter(stream, fieldnames=["Check", "Status", "Detail", "Evidence"]); w.writeheader(); w.writerows(self.checks)
        pending = [x for x in self.checks if x["Status"] != "PASS"]
        lines = ["# 本次完整运行验收", "", f"**状态：{status}。**", "", f"检查数：{dict(counts)}。只读核查，没有启动或重跑模型。", "",
                 "MC稳定性复核、秩亏以及矩阵2倍MCSE差异如实保留；这些科学/数值解释标记不因计算完成而被清除。", "", "## 未满足或待补证据", ""]
        lines += [f"- {x['Status']}：{x['Check']} — {x['Detail']}" for x in pending] or ["未发现未满足的本次验收项。"]
        lines += ["", f"保留复核标志 {len(self.flags)} 项，完整内容和逐文件哈希见 final_acceptance.json。", "",
                  "PASS只表示本合同所列计算和产物完成；不证明模型假设、实验独立性或跨物种因果解释成立。"]
        (target / "final_acceptance.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(json.dumps({"status": status, "checks": dict(counts), "review_flags": len(self.flags), "report": str(target / "final_acceptance.md")}, ensure_ascii=False))
        return 0 if status.startswith("PASS") else (1 if status == "FAIL" else 2)

    def figures(self, kind):
        folder = self.base / "figures" / kind
        index = self.csv(folder / "FIGURE_INDEX.csv")
        model = kind == "model"
        if model:
            final = self.read_json(folder / "final_figure_checks.json")
            if final.get("status") != "PASS_MODEL_FIGURES" or final.get("manual_visual_review_confirmed") is not True:
                raise MissingEvidence("Model figures not completely generated and visually reviewed")
            state_rows = self.csv(folder / "FIGURE_STATUS.csv")
            expected_scopes = {(g, o) for o in OUTCOMES for g in ["coefficients", "diagnostics", "pareto", "ppc", "ppc_ecdf", "sensitivity_ppc", "matrix_check"]}
            expected_scopes |= {(g, o + "_" + d) for o in OUTCOMES for d in DESIGNS for g in ["cv_elpd", "cv_mc", "cv_diagnostics"]}
            expected_scopes |= {(g, d) for d in DESIGNS for g in ["roc_calibration", "quantitative", "predictive_bands", "metrics"]}
            expected_scopes |= {("species_predictions", "both"), ("sensitivity", "both"), ("folds", "all")}
            self.require(len(state_rows) == 37 and {(r["Group"], r["Scope"]) for r in state_rows} == expected_scopes and
                         all(r["Status"] == "GENERATED_AWAITING_VISUAL_REVIEW" for r in state_rows) and
                         {(r["Group"], r["Scope"]) for r in index} == expected_scopes,
                         "All37 model figure group/scope contracts represented")
            self.require(all(r["VisualReview"] == "COMPLETED_BY_REVIEWER" for r in index) and final.get("pending_scopes") == [],
                         "Every model figure has recorded visual review; none pending")
            metadata = self.read_json(folder / "metadata_checks.json")
            self.require(metadata.get("input_changes_during_read") == [] and metadata.get("new_fits_started") is False and metadata.get("simulated_data_created_by_plotter") is False and
                         metadata.get("point_rule_for_quantitative_MAE_RMSE") == POINT_RULE and
                         all(self.sha(self.path(p)) == v["SHA256"] for p, v in metadata.get("source_files", {}).items()),
                         "Model figure input provenance and estimand unchanged")
            checks = {r["FigureID"]: r for r in final.get("exports", [])}
            png_field = "PNG"
        else:
            metadata = self.read_json(folder / "metadata_checks.json")
            if metadata.get("status") != "PASS_DESCRIPTIVE_FIGURES" or not metadata.get("manual_visual_review", {}).get("completed"):
                raise MissingEvidence("Descriptive figures not visually reviewed")
            self.require(metadata.get("records") == 153 and metadata.get("observed_species") == 51 and metadata.get("panel_species") == 365 and
                         metadata.get("interval_midpoints") == "none" and all(self.sha(self.path(v["path"])) == v["sha256"] for v in metadata["inputs"].values()),
                         "Descriptive figures use exact frozen input and no interval midpoints")
            self.require(len(index) == 21 and len({r["FigureID"] for r in index}) == 21, "All21 descriptive figure pages")
            checks = {r["FigureID"]: r for r in metadata.get("existing_export_audit", [])}
            png_field = "PNG_600dpi"
            final = {"figures": len(index), "pdf_files": len({r["PDF"] for r in index}), "pdf_pages": len(index)}
        self.require(bool(index) and len({r["FigureID"] for r in index}) == len(index) and set(checks) == {r["FigureID"] for r in index},
                     "Figure index and individual QA entry coverage " + kind)
        needed = [folder / "FIGURE_INDEX.csv", folder / "metadata_checks.json", self.base / "scripts" / ("plot_models.py" if model else "plot_descriptive.py")]
        if model:
            needed += [folder / "final_figure_checks.json", folder / "FIGURE_STATUS.csv"]
        for r in index:
            needed += [folder / r[c] for c in ["PDF", "SVG", png_field, "Preview"]] + [self.path(r["SourceCSV"])]
        manifest = self.hash_manifest(folder / "MANIFEST.csv", self.base, needed)
        sha_lines = self.track(folder / "MANIFEST.sha256").read_text(encoding="utf-8-sig").splitlines()
        listed = {}
        for line in sha_lines:
            digest, rel = line.split(None, 1)
            listed[self.path(rel.strip())] = digest
        self.require(set(listed) == set(manifest) and all(listed[p] == row["SHA256"] for p, row in manifest.items()), "Plain SHA manifest matches CSV manifest " + kind)
        runtime = self.base / "figures/descriptive/_runtime"
        if runtime.is_dir():
            sys.path.insert(0, str(runtime))
        try:
            from PIL import Image
            from pypdf import PdfReader
        except ImportError as e:
            raise MissingEvidence(f"Need installed Pillow/pypdf for independent figure structural audit: {e}")
        pdf_rows = defaultdict(list)
        source_models, record_coverage = defaultdict(set), defaultdict(set)
        images_ok, source_ok = True, True
        for r in index:
            pdf_rows[r["PDF"]].append(r)
            fid = r["FigureID"]
            width, height = number(r["WidthMM"]), number(r["HeightMM"])
            with Image.open(self.track(folder / r[png_field])) as im:
                dpi = im.info.get("dpi", [0, 0])
                opaque = "A" not in im.getbands() or im.getchannel("A").getextrema() == (255, 255)
                images_ok &= min(dpi) >= 599 and opaque and abs(im.width - width / 25.4 * 600) < 2 and abs(im.height - height / 25.4 * 600) < 2
                extrema = im.convert("RGB").getextrema()
                images_ok &= any(a != b for a, b in extrema)
            with Image.open(self.track(folder / r["Preview"])) as im:
                images_ok &= abs(im.width - width / 25.4 * 150) < 2 and abs(im.height - height / 25.4 * 150) < 2
            svg = ET.parse(self.track(folder / r["SVG"])).getroot()
            w = float(svg.attrib["width"].removesuffix("pt")) / 72 * 25.4
            h = float(svg.attrib["height"].removesuffix("pt")) / 72 * 25.4
            images_ok &= abs(w-width) < .03 and abs(h-height) < .03 and bool(svg.findall(".//{http://www.w3.org/2000/svg}text"))
            source = self.path(r["SourceCSV"])
            rows = self.csv(source)
            source_ok &= bool(rows)
            qa = checks.get(fid, {})
            hash_recorded = qa.get("CSV_SHA256") or qa.get("SourceSHA256")
            if hash_recorded:
                source_ok &= hash_recorded == self.sha(source)
            if model:
                scope = r["Group"], r["Scope"]
                for x in rows:
                    if x.get("Model"):
                        source_models[scope].add(x["Model"])
                    if x.get("RecordID") and x.get("Model"):
                        record_coverage[(scope, x["Model"])].add(x["RecordID"])
                    for key_field in ["Key", "FitKey", "CVKey", "ParentKey", "PrimaryKey", "AlternativeKey", "FoldKey", "CheckKey", "AUCKey"]:
                        if x.get(key_field):
                            source_ok &= x[key_field] in self.known_keys
                if r["Group"] in {"cv_elpd", "cv_mc"}:
                    out, design = next((o, d) for o in OUTCOMES for d in DESIGNS if r["Scope"] == o + "_" + d)
                    has_flags = any(f.get("Category") == "CV_MC_REVIEW_RETAINED" and f.get("Outcome") == out and f.get("CVType") == design for f in self.flags)
                    source_ok &= r["ScientificStatus"] == ("REVIEW_REQUIRED" if has_flags else "NO_MC_SCREEN_FLAG")
            else:
                if fid.startswith("S01B_raw_records_page"):
                    record_coverage[("descriptive", "raw")].update(x["RecordID"] for x in rows if x.get("RecordID"))
        self.require(images_ok, "Independent PNG dimensions/dpi/nonblank/opacity and SVG text/size " + kind)
        self.require(source_ok, "Per-figure source rows, hashes, known fit/CV keys and retained scientific flags " + kind)
        fonts = 0
        pdf_ok = True
        for name, rows in pdf_rows.items():
            reader = PdfReader(str(self.track(folder / name)))
            pdf_ok &= len(reader.pages) == len(rows)
            for page, r in zip(reader.pages, rows):
                pdf_ok &= bool((page.extract_text() or "").strip())
                pdf_ok &= abs(float(page.mediabox.width) / 72 * 25.4 - number(r["WidthMM"])) < .03 and abs(float(page.mediabox.height) / 72 * 25.4 - number(r["HeightMM"])) < .03
                resources = page.get("/Resources", {})
                if hasattr(resources, "get_object"): resources = resources.get_object()
                for ref in resources.get("/Font", {}).values():
                    font = ref.get_object()
                    descriptors = []
                    for child in font.get("/DescendantFonts", [font]):
                        obj = child.get_object() if hasattr(child, "get_object") else child
                        if "/FontDescriptor" in obj: descriptors.append(obj["/FontDescriptor"].get_object())
                    pdf_ok &= bool(descriptors) and all(any(k in fd for k in ["/FontFile", "/FontFile2", "/FontFile3"]) for fd in descriptors)
                    fonts += 1
        self.require(pdf_ok and final.get("figures") == len(index) and final.get("pdf_files") == len(pdf_rows) and final.get("pdf_pages") == len(index),
                     "Independent PDF pages/dimensions/text/embedded-font checks " + kind, f"{len(index)} pages; {fonts} font entries")
        if model:
            for scope in {(r["Group"], r["Scope"]) for r in index}:
                group, which = scope
                expected_models = set(SIX) if group in {"coefficients", "species_predictions"} else (
                    {"M1_U", "M1_P"} if group == "predictive_bands" else
                    {"M1_U", "M1_P", "M3_U", "M3_P"} if group in {"sensitivity", "sensitivity_ppc"} else
                    ({"M3_P"} if group == "matrix_check" else (set() if group == "folds" else set(MODELS))))
                self.require(source_models[scope] == expected_models, "Figure source model coverage " + str(scope))
                if group in {"roc_calibration", "quantitative", "predictive_bands"}:
                    expected_ids = self.binary_ids if group == "roc_calibration" else (set(self.obs_by_id) if group == "quantitative" else self.point_ids)
                    self.require(all(record_coverage[(scope, m)] == expected_ids for m in expected_models), "Figure source complete record coverage " + str(scope))
        else:
            self.require(record_coverage[("descriptive", "raw")] == set(self.obs_by_id), "Descriptive raw-record pages cover all153 source IDs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--run", default="formal_20260914_26e686af86fa")
    args = parser.parse_args()
    audit = Audit(args.root, args.run)
    audit.section("Frozen inputs", audit.inputs)
    audit.section("Main and sensitivity selection", audit.fit_selection)
    if hasattr(audit, "obs_by_id"):
        audit.section("Fixed-draw numerical likelihood compatibility", audit.numerical_compatibility_stage)
        audit.section("CV selection, extensions, source identity and scores", audit.cv_selection)
        audit.section("Primary postfit, PPC, LOO gates and07", audit.primary_outputs)
        audit.section("Sensitivity postfit and16x365 comparison", audit.sensitivity_outputs)
        audit.section("Final CV/AUC/quantitative aggregates", audit.comparison_outputs)
        audit.section("Both matrix comparisons", audit.matrices)
        audit.section("Descriptive figures", lambda: audit.figures("descriptive"))
        audit.section("Complete model figures", lambda: audit.figures("model"))
    return audit.finish()


if __name__ == "__main__":
    raise SystemExit(main())
