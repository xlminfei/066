"""Read-only identity/threshold contract for the two allowed CV evaluators.

This module never evaluates a likelihood, loads R, or changes source artifacts.
Legacy outputs must match their original exporter; numerical repairs must match
the one explicitly named stable exporter, both actual R helpers, unchanged-draw
provenance, and the complete100-fold compatibility audit.
"""
from __future__ import annotations
import csv
import hashlib
import math
import re
from pathlib import Path

STABLE_PROTOCOL = "stable_beta_logtails_20260916_v1"
LEGACY_PROTOCOL = "legacy_stan_generated_log_lik"
LEGACY_EXPORTER = "export_cv_extensions.R"
STABLE_EXPORTER = "export_cv_extensions_stable.R"
HELPERS = ("stable_beta_interval.R", "stable_cv_likelihood.R")
COMPAT_CSV = "review/likelihood_diagnosis_20260916/stable_compatibility_all.csv"
COMPAT_SOURCES = "review/likelihood_diagnosis_20260916/stable_compatibility_sources.csv"
MATH_REVIEW = "review/likelihood_math_review_20260916.md"
MODELS = ("Null_U", "Phylogeny_only_P", "Site315_U", "Site315_P", "M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P")
REPAIRED_MODELS = frozenset(("Phylogeny_only_P", "Site315_P", "M1_P", "M2_P", "M3_P"))
RUN_NAME = "formal_20260914_26e686af86fa"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class NumericalContractError(ValueError):
    pass


class NumericalEvidenceIncomplete(RuntimeError):
    pass


def need(ok, detail):
    if not ok:
        raise NumericalContractError(detail)


def actual_sha(path):
    path = Path(path)
    if not path.is_file():
        raise NumericalEvidenceIncomplete(f"Missing numerical contract source: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_path(root, value, relative=None):
    root = Path(root).resolve()
    text = str(value).replace("\\", "/")
    marker = "/work/ratio_analysis_20260914/"
    if marker in text:
        p = root / text.split(marker, 1)[1]
    else:
        p = Path(text)
        if not p.is_absolute(): p = (relative or root) / p
    p = p.resolve()
    need(p.is_relative_to(root), f"Numerical evidence path outside current analysis root: {p}")
    return p


def finite_number(value, field):
    try: value = float(value)
    except (TypeError, ValueError) as e: raise NumericalContractError(f"Invalid {field}: {value!r}") from e
    need(math.isfinite(value), f"Nonfinite {field}: {value}")
    return value


def validate_protocol_fields(manifest, actual_hashes):
    """Pure checks; actual_hashes must be made from the fixed paths by caller."""
    if "NumericalLikelihoodMethod" not in manifest:
        need(manifest.get("ScriptSHA256") == actual_hashes[LEGACY_EXPORTER], "Legacy exporter SHA256 mismatch")
        need(not any(k in manifest for k in ("LikelihoodHelperSHA256", "RawFoldFiles", "CompatibilityManifest", "ScoringUnchangedModel")),
             "Stable-only metadata cannot be disguised as an untagged legacy output")
        return LEGACY_PROTOCOL
    need(manifest["NumericalLikelihoodMethod"] == STABLE_PROTOCOL, "Unknown numerical likelihood protocol")
    need(manifest.get("Outcome") == "joint" and manifest.get("CVType") == "phylo_distance" and manifest.get("Model") in REPAIRED_MODELS,
         "Stable protocol is limited to the five declared joint/P/phylo_distance repairs")
    need(manifest.get("ScriptSHA256") == actual_hashes[STABLE_EXPORTER], "Stable exporter SHA256 mismatch")
    need(manifest.get("ScoringUnchangedModel") is True, "Stable score must explicitly preserve the target model")
    helpers = manifest.get("LikelihoodHelperSHA256")
    need(isinstance(helpers, dict) and set(helpers) == set(HELPERS), "Stable helper hash map must contain exactly the two declared helpers")
    need(all(helpers[n] == actual_hashes[n] for n in HELPERS), "Actual stable helper SHA256 mismatch")
    need(manifest.get("CompatibilityManifest") == COMPAT_SOURCES, "Unexpected compatibility source-manifest path")
    need(bool(HEX64.fullmatch(str(manifest.get("CompatibilityManifestSHA256", "")))), "Missing compatibility source-manifest SHA256")
    return STABLE_PROTOCOL


def validate_extension_manifest(root, manifest, sha=actual_sha):
    root = Path(root).resolve()
    names = [LEGACY_EXPORTER] if "NumericalLikelihoodMethod" not in manifest else [STABLE_EXPORTER, *HELPERS]
    hashes = {n: sha(root / "scripts" / n) for n in names}
    return validate_protocol_fields(manifest, hashes)


def validate_score_receipt_protocol(receipt, protocol):
    if protocol == STABLE_PROTOCOL:
        need(receipt.get("score_protocol") == STABLE_PROTOCOL, "Stable CV receipt lacks its exact score_protocol")
    else:
        need("score_protocol" not in receipt, "A tagged score receipt cannot be accepted by the legacy path")


def validate_compatibility_rows(rows, parent_keys=None):
    if len(rows) < 100:
        raise NumericalEvidenceIncomplete(f"Joint compatibility audit has {len(rows)}/100 folds")
    need(len(rows) == 100, f"Joint compatibility audit must contain exactly100 rows, found {len(rows)}")
    expected = {(m, d, k) for m in MODELS for d in ("species", "phylo_distance") for k in range(1, 6)}
    seen, keys, violations = set(), {}, []
    max_train = max_old_elpd = max_event = 0.0
    nonfinite = 0
    for row in rows:
        fold_value = finite_number(row.get("Fold"), "Fold")
        need(fold_value.is_integer(), "Fold must be an integer")
        ident = row.get("Model"), row.get("CVType"), int(fold_value)
        need(ident in expected and ident not in seen, f"Duplicate or unexpected compatibility fold: {ident}")
        seen.add(ident)
        key = row.get("ParentKey", "")
        need(bool(HEX64.fullmatch(key)), f"Missing parent key: {ident}")
        need(keys.setdefault(ident[0], key) == key, f"Mixed parent keys for {ident[0]}")
        if parent_keys is not None:
            need(parent_keys.get(ident[0]) == key, f"Compatibility parent differs from selected model: {ident}")
        old_bad = finite_number(row.get("OriginalNonfiniteHeldout"), "OriginalNonfiniteHeldout")
        need(old_bad >= 0 and old_bad.is_integer(), f"Invalid nonfinite count: {ident}")
        nonfinite += int(old_bad)
        train_bad = finite_number(row.get("OriginalNonfiniteTraining"), "OriginalNonfiniteTraining")
        corrected_bad = finite_number(row.get("CorrectedNonfinite"), "CorrectedNonfinite")
        train = finite_number(row.get("MaxAbsTrainingJointLogDifference"), "MaxAbsTrainingJointLogDifference")
        event = finite_number(row.get("MaxAbsHeldoutEventProbabilityDifference"), "MaxAbsHeldoutEventProbabilityDifference")
        stable_elpd = finite_number(row.get("StableELPD"), "StableELPD")
        need(train >= 0 and event >= 0, f"Negative maximum absolute difference: {ident}")
        max_train, max_event = max(max_train, train), max(max_event, event)
        if train_bad != 0 or corrected_bad != 0 or train > 1e-8:
            violations.append({"Identity": ident, "TrainingNonfinite": train_bad, "CorrectedNonfinite": corrected_bad, "TrainingJointDifference": train})
        if old_bad == 0:
            delta = finite_number(row.get("ELPDDifference"), "ELPDDifference")
            original_elpd = finite_number(row.get("OriginalELPDAllowingNegativeInfinity"), "OriginalELPDAllowingNegativeInfinity")
            need(abs((stable_elpd-original_elpd)-delta) <= 1e-9, f"ELPD difference arithmetic mismatch: {ident}")
            max_old_elpd = max(max_old_elpd, abs(delta))
            if abs(delta) > 1e-8 or event > 1e-9:
                violations.append({"Identity": ident, "FiniteOriginalELPDDifference": delta, "EventProbabilityDifference": event})
    need(seen == expected, "Joint compatibility audit does not cover the required100 folds")
    need(not violations, "Numerical compatibility threshold exceeded; do not relax: " + repr(violations))
    return {"rows": 100, "original_nonfinite_heldout": nonfinite, "max_training_joint_log_difference": max_train,
            "max_original_finite_elpd_difference": max_old_elpd, "max_event_probability_difference": max_event,
            "parent_keys": keys, "thresholds": {"TrainingJointLog": 1e-8, "OriginalFiniteELPD": 1e-8, "OriginalFiniteEventProbability": 1e-9}}


def read_csv(path):
    path = Path(path)
    if not path.is_file(): raise NumericalEvidenceIncomplete(f"Missing numerical audit: {path}")
    with path.open(encoding="utf-8-sig", newline="") as stream: return list(csv.DictReader(stream))


def validate_compatibility_sources(root, rows, summary, sha=actual_sha):
    root = Path(root).resolve()
    required = {root / p for p in (COMPAT_CSV, "input/observations.csv", "input/sites.csv", "input/tree.nwk",
                "scripts/audit_stable_cv_likelihood.R", *("scripts/"+n for n in HELPERS))}
    entries, raw, parents, folds = {}, {}, {}, set()
    for row in rows:
        text = str(row.get("File", "")).replace("\\", "/")
        need(text and not text.startswith("/") and not re.match(r"^[A-Za-z]:", text), "Compatibility File must be relative to analysis_root")
        p = safe_path(root, text)
        need(p not in entries, f"Duplicate compatibility source path: {text}")
        digest = str(row.get("SHA256", ""))
        need(bool(HEX64.fullmatch(digest)), f"Invalid compatibility source hash: {text}")
        if not p.is_file(): raise NumericalEvidenceIncomplete(f"Missing compatibility source: {p}")
        need(p.stat().st_size == int(finite_number(row.get("Bytes"), "Bytes")) and sha(p) == digest,
             f"Compatibility source bytes/SHA256 mismatch: {text}")
        entries[p] = digest
        parts = p.relative_to(root).parts
        if len(parts) == 5 and parts[:3] == ("runs", RUN_NAME, "cv"):
            directory = re.fullmatch(r"joint_(species|phylo_distance)_[0-9a-f]{12}", parts[3])
            if directory:
                if parts[4] == "folds.csv": folds.add(directory.group(1))
                for m in MODELS:
                    match = re.fullmatch(re.escape(m)+r"_[0-9a-f]{16}_fold([1-5])[.]rds", parts[4])
                    if match:
                        ident = m, directory.group(1), int(match.group(1))
                        need(ident not in raw, f"Multiple raw folds for {ident}")
                        raw[ident] = p
        if len(parts) == 6 and parts[:5] == ("runs", RUN_NAME, "fits", "joint", "primary"):
            for m, key in summary["parent_keys"].items():
                if parts[5] == f"{m}_{key[:16]}.rds":
                    need(m not in parents, f"Multiple selected parents for {m}")
                    parents[m] = p
    expected_raw = {(m, d, k) for m in MODELS for d in ("species", "phylo_distance") for k in range(1, 6)}
    need(required <= entries.keys(), "Compatibility source manifest omits a required input/helper/audit/result")
    need(set(raw) == expected_raw and set(parents) == set(MODELS) and folds == {"species", "phylo_distance"},
         "Compatibility source manifest must bind100 raw folds,10 selected parents and both fold allocations")
    return {"entries": entries, "raw_folds": raw, "parents": parents}


def validate_compatibility(root, parent_keys=None, csv_reader=read_csv, sha=actual_sha):
    root = Path(root).resolve()
    summary = validate_compatibility_rows(csv_reader(root / COMPAT_CSV), parent_keys)
    sources = validate_compatibility_sources(root, csv_reader(root / COMPAT_SOURCES), summary, sha)
    return {**summary, **sources, "manifest_sha256": sha(root / COMPAT_SOURCES), "method": STABLE_PROTOCOL}


def validate_raw_fold_metadata(root, manifest, compatibility, cv_directory=None, sha=actual_sha):
    need(manifest.get("NumericalLikelihoodMethod") == STABLE_PROTOCOL, "Raw-draw contract requires the stable protocol")
    need(manifest.get("CompatibilityManifestSHA256") == compatibility["manifest_sha256"], "Stable extension uses another compatibility source manifest")
    rows = manifest.get("RawFoldFiles")
    need(isinstance(rows, list) and len(rows) == 5, "Stable extension must expose exactly5 raw fold identities")
    seen = set()
    for row in rows:
        fold = finite_number(row.get("Fold"), "RawFoldFiles.Fold")
        need(fold.is_integer() and int(fold) in range(1, 6) and int(fold) not in seen, "Raw folds missing or duplicated")
        k = int(fold); seen.add(k)
        ident = manifest["Model"], manifest["CVType"], k
        p = safe_path(root, row.get("File", ""), relative=cv_directory)
        need(p == compatibility["raw_folds"][ident], f"Raw fold path differs from the100-fold audit: {ident}")
        need(row.get("SHA256") == compatibility["entries"].get(p) == sha(p), f"Raw fold hash differs: {ident}")
        need(bool(HEX64.fullmatch(str(row.get("DataKey", "")))), f"Missing immutable R data_key: {ident}")
    return True
