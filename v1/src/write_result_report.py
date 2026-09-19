"""Generate a source-bound Chinese report only when this formal run is complete.

No model fitting, simulation, plotting, or invocation of the final auditor occurs.
--check-inputs writes only review/result_report_readiness.json. Missing/conflicting
evidence never creates the final Markdown or its source manifest.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from numerical_likelihood_contract import (
    STABLE_PROTOCOL, LEGACY_PROTOCOL, MATH_REVIEW, COMPAT_CSV, COMPAT_SOURCES,
    NumericalEvidenceIncomplete, validate_extension_manifest, validate_compatibility,
    validate_raw_fold_metadata, validate_score_receipt_protocol, actual_sha,
)

VERSION = "result_report_20260914_v1"
MODELS = ["Null_U", "Phylogeny_only_P", "Site315_U", "Site315_P", "M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P"]
SIX = ["M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P"]
OUTCOMES = ["binary", "joint"]
DESIGNS = ["species", "phylo_distance"]
POINT_RULE = "posterior_mean_of_species_expected_ratio_m"
DESIGN_NAME = {"species": "普通物种分组", "phylo_distance": "系统发育距离分块"}
OUTCOME_NAME = {"binary": "High/Low分类", "joint": "定量比率"}
INPUT_HASHES = {"observations.csv": "3c886f7f2c11012463296b350a931543542b4e1c0d128ad3c408fda9ae824d79",
                "sites.csv": "0a99692b060f13d1faaa870d06ea7dca9a4f16bc289636bcc88f5d105ebdacb5",
                "tree.nwk": "114941169558dc76e15d2e86b50045a7f5ca853ea1491b118c0a966946b3ffde"}


class NotReady(Exception):
    pass


class Conflict(Exception):
    pass


def ensure(ok, message):
    if not ok:
        raise Conflict(message)


def num(v):
    return math.nan if v is None or str(v).strip().lower() in {"", "na", "nan", "null"} else float(v)


def boolean(v):
    if str(v).lower() in {"true", "1"}: return True
    if str(v).lower() in {"false", "0"}: return False
    raise Conflict(f"非法布尔值：{v!r}")


def near(a, b, tol=1e-10):
    a, b = num(a), num(b)
    return math.isfinite(a) and math.isfinite(b) and abs(a-b) <= tol


def fmt(v, digits=3, scale=1):
    value = num(v)
    return "NA" if not math.isfinite(value) else f"{value*scale:.{digits}f}"


def q7(values, p):
    values = sorted(values)
    ensure(bool(values), "没有可汇总的既有PPC抽样")
    position = (len(values)-1)*p
    k = int(position)
    return values[k] + (position-k)*(values[min(k+1, len(values)-1)]-values[k])


def table(headers, rows):
    esc = lambda v: str(v).replace("|", "\\|").replace("\n", " ")
    return "\n".join(["| " + " | ".join(map(esc, headers)) + " |", "| " + " | ".join(["---"]*len(headers)) + " |"] +
                     ["| " + " | ".join(map(esc, row)) + " |" for row in rows])


def expected_jobs():
    primary = {(o, "primary", m) for o in OUTCOMES for m in MODELS}
    sens = {(o, v, m) for o in OUTCOMES for v in ["b_sd_025", "b_sd_100"] for m in ["M3_U", "M3_P"]}
    sens |= {("joint", "rho_beta22", m) for m in ["M1_U", "M1_P", "M3_U", "M3_P"]}
    sens |= {(o, "beta_binomial", m) for o in OUTCOMES for m in ["M1_U", "M1_P"]}
    return primary, sens


def diagnostic_ok(rows):
    return bool(rows) and all(r["Status"] == "PASS" and num(r["MaxRhat"]) < 1.01 and num(r["MinBulkESS"]) >= 400 and
                             num(r["MinTailESS"]) >= 400 and num(r["Divergences"]) == 0 and num(r["TreeDepthHits"]) == 0 and
                             num(r["MinEBFMI"]) > .3 for r in rows)


class Builder:
    def __init__(self, root, run):
        self.root = Path(root).resolve()
        self.run = self.root / "runs" / run
        self.res = self.run / "results"
        self.sources, self.cache, self.gates = {}, {}, []
        self.selected, self.cvs, self.extensions = {}, {}, {}
        self.phase, self.diags, self.ppc, self.matrices = {}, {}, {}, {}
        self.numerical_compatibility = None
        self.numerical_protocols = {}
        self.primary_jobs, self.sensitivity_jobs = expected_jobs()
        self.started = datetime.now(timezone.utc).isoformat()

    def path(self, value, relative=None):
        text = str(value).replace("\\", "/")
        marker = "/work/ratio_analysis_20260914/"
        if marker in text:
            result = self.root / text.split(marker, 1)[1]
        else:
            result = Path(text)
            if not result.is_absolute(): result = (relative or self.root) / result
        result = result.resolve()
        ensure(result.is_relative_to(self.root), "来源或输出路径越出本次分析目录：" + str(result))
        return result

    def read(self, p, kind="csv", columns=()):
        p = self.path(p)
        if not p.is_file(): raise NotReady("缺少文件：" + str(p.relative_to(self.root)))
        if p not in self.cache:
            before = p.stat()
            data = p.read_bytes()
            after = p.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise NotReady("读取过程中来源改变：" + str(p))
            sha = hashlib.sha256(data).hexdigest()
            self.sources[p] = {"RelativePath": p.relative_to(self.root).as_posix(), "AbsolutePath": str(p), "Bytes": len(data),
                               "SHA256": sha, "MtimeNS": after.st_mtime_ns, "Use": "直接读取的报告来源"}
            text = data.decode("utf-8-sig")
            if kind == "json":
                try: value = json.loads(text)
                except json.JSONDecodeError as e: raise NotReady("JSON仍未稳定可读：" + str(p)) from e
            elif kind == "text": value = text
            else:
                import io
                reader = csv.DictReader(io.StringIO(text))
                value = list(reader)
            self.cache[p] = value
        value = self.cache[p]
        if kind == "csv" and columns:
            ensure(value and set(columns) <= set(value[0]), "字段不完整：" + str(p) + " / " + str(columns))
        return value

    def sha(self, p):
        p = self.path(p)
        if p in self.sources: return self.sources[p]["SHA256"]
        if not p.is_file(): raise NotReady("缺少哈希来源：" + str(p))
        before = p.stat()
        digest = actual_sha(p)
        after = p.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise NotReady("哈希核对期间来源改变：" + str(p))
        self.sources[p] = {"RelativePath": p.relative_to(self.root).as_posix(), "AbsolutePath": str(p),
            "Bytes": after.st_size, "SHA256": digest, "MtimeNS": after.st_mtime_ns, "Use": "仅核对SHA256的固定来源；未重新计算其拟合或评分"}
        return digest

    def stage(self, name, fn):
        try:
            fn()
            self.gates.append({"Stage": name, "Status": "READY", "Detail": "当前来源与字段检查通过"})
        except (NotReady, NumericalEvidenceIncomplete) as e:
            self.gates.append({"Stage": name, "Status": "INCOMPLETE", "Detail": str(e)})
        except Exception as e:
            self.gates.append({"Stage": name, "Status": "CONFLICT", "Detail": f"{type(e).__name__}: {e}"})

    def input_stage(self):
        for filename, expected in INPUT_HASHES.items():
            if filename.endswith(".csv"): self.read(self.root / "input" / filename)
            else: self.read(self.root / "input" / filename, "text")
            ensure(self.sha(self.root / "input" / filename) == expected, "输入不属于本次冻结版本：" + filename)
        self.obs = self.read(self.root / "input/observations.csv", columns=["RecordID", "Species", "Type", "SourceID", "Events", "Total", "Exact", "Lower", "Upper"])
        self.sites = self.read(self.root / "input/sites.csv", columns=["Species", "Site151"])
        self.obs_by_id = {r["RecordID"]: r for r in self.obs}
        self.species = [r["Species"] for r in self.sites]
        self.observed_species = {r["Species"] for r in self.obs}
        self.points = [r for r in self.obs if r["Type"] in {"count", "exact"}]
        self.point_ids = {r["RecordID"] for r in self.points}
        self.interval_ids = {r["RecordID"] for r in self.obs if r["Type"] == "interval"}
        self.binary_counts = self.read(self.run / "binary_counts.csv", columns=["Species", "HighCount", "LowCount", "Trials"])
        ensure(len(self.obs) == len(self.obs_by_id) == 153 and len(self.observed_species) == 51 and len(self.species) == len(set(self.species)) == 365, "153/51/365输入范围不一致")
        ensure(len(self.points) == 145 and len({r["Species"] for r in self.points}) == 48 and len(self.interval_ids) == 8, "145条/48物种点值或8条区间范围不一致")
        ensure(Counter(r["Type"] for r in self.obs) == Counter(count=105, exact=40, interval=8), "观测类型数量不符")
        ensure(sum(num(r["HighCount"]) for r in self.binary_counts) == 116 and sum(num(r["LowCount"]) for r in self.binary_counts) == 36 and
               sum(num(r["Trials"]) > 0 for r in self.binary_counts) == 50, "分类范围不符")
        sites_by_name = {r["Species"]: r for r in self.sites}
        ensure(self.observed_species <= sites_by_name.keys(), "观测物种缺少位点资料")
        self.site151_panel = Counter(r["Site151"] for r in self.sites)
        self.site151_observed = Counter(sites_by_name[s]["Site151"] for s in self.observed_species)
        self.blueprints = self.read(self.root / "provenance/blueprint_summary.csv", columns=["Blueprint", "Rank", "ParameterColumns"])
        self.read(self.root / "模型与图表阅读说明.md", "text")
        self.read(self.root / "服务器手动复核说明.md", "text")

    def selection_stage(self):
        plan = self.read(self.root / "provenance/fit_plan.json", "json")
        ensure({(r["outcome"], r["variant"], r["model"]) for r in plan["main_jobs"]} == self.primary_jobs | self.sensitivity_jobs and len(plan["main_jobs"]) == 36,
               "既定20主+16敏感性计划改变")
        index = self.read(self.run / "fit_index.csv", columns=["Outcome", "Variant", "Model", "Key", "RelativeFile", "FileSHA256"])
        for r in index: self.selected[(r["Outcome"], r["Variant"], r["Model"])] = r
        missing = (self.primary_jobs | self.sensitivity_jobs) - self.selected.keys()
        ensure(set(self.selected) <= self.primary_jobs | self.sensitivity_jobs, "出现计划外的选用拟合")
        for item, r in self.selected.items():
            o, v, m = item
            ensure(self.path(r["RelativeFile"], self.run).is_file(), "选用模型RDS缺失：" + str(item))
            ds = self.read(self.res / f"diagnostics_{o}_{v}.csv", columns=["Model", "Key", "Status", "MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI"])
            part = [x for x in ds if x["Model"] == m and x["Key"] == r["Key"]]
            ensure(len(part) == 1 and diagnostic_ok(part), "选用拟合未通过对应数值诊断：" + str(item))
        if missing: raise NotReady("选用拟合未齐：" + str(sorted(missing)))

    def phase_stage(self, phase):
        state = self.read(self.res / f"postfit_{phase}_status.json", "json")
        permitted = {"COMPLETE_ALL_PREDICTION_AND_LOO_GATES_PASS", "COMPLETE_WITH_GROUPED_CV_REQUIRED"} if phase == "primary" else {"COMPLETE_DIAGNOSTICS_AND_TRAINING_PPC"}
        if state.get("status") not in permitted: raise NotReady(f"{phase}后处理状态：{state.get('status')}")
        jobs = self.primary_jobs if phase == "primary" else self.sensitivity_jobs
        ds = self.read(self.res / f"diagnostics_all_{phase}.csv", columns=["Outcome", "Variant", "Model", "Key", "Rank", "DesignColumns"])
        ensure(len(ds) == len(jobs) and {(r["Outcome"], r["Variant"], r["Model"]) for r in ds} == jobs and diagnostic_ok(ds), phase + "最终诊断覆盖不完整")
        ensure(all(self.selected.get((r["Outcome"], r["Variant"], r["Model"]), {}).get("Key") == r["Key"] for r in ds), phase + "后处理与选用模型key不同")
        self.phase[phase], self.diags[phase] = state, ds
        if phase == "primary":
            ensure(state.get("formal_output_gate") == "PASS_ALL_20_IDENTITIES_AND_DIAGNOSTICS" and state.get("primary_models") == 20 and state.get("ppc_models") == 20,
                   "主后处理总门槛不完整")
            self.long = self.read(self.res / "species_predictions_long.csv", columns=["Species", "Model", "PrHigh", "PredictedRatio", "BinarySupported", "RatioSupported"])
            wide = self.read(self.res / "species_predictions_wide.csv", columns=["Species"])
            ensure(len(self.long) == 2190 and {(r["Model"], r["Species"]) for r in self.long} == {(m, s) for m in SIX for s in self.species} and
                   len(wide) == 365 and {r["Species"] for r in wide} == set(self.species), "07长2190/宽365输出不完整")
            self.loo = self.read(self.res / "model_comparison_status_primary.csv", columns=["Outcome", "RankingStatus", "ModelsWithProblemRows", "ProblemRows"])
            ensure(len(self.loo) == 2 and {r["Outcome"] for r in self.loo} == set(OUTCOMES), "两路线PSIS状态不完整")
            for r in self.loo:
                ensure(r["RankingStatus"] in {"PASS", "REFUSED_USE_GROUPED_CV"}, "未知PSIS排名状态")
                if r["RankingStatus"] != "PASS": ensure(not (self.res / f"model_comparison_{r['Outcome']}_primary.csv").exists(), "不可靠PSIS仍留有当前排名文件")
            self.parameters = {o: self.read(self.res / f"parameter_summary_{o}_primary.csv", columns=["Model", "OriginalTerm", "mean", "Lower95", "Upper95"]) for o in OUTCOMES}
            self.term_map = self.read(self.root / "provenance/blueprint_term_map.csv", columns=["Outcome", "Group", "OriginalTerm", "ReferenceLevel"])
        else:
            self.sens = self.read(self.res / "sensitivity_expected_values_long.csv", columns=["Outcome", "Model", "Variant", "Species", "Supported", "MedianShift", "PrimaryKey", "AlternativeKey"])
            ensure(len(self.sens) == 5840 and {(r["Outcome"], r["Variant"], r["Model"], r["Species"]) for r in self.sens} ==
                   {(o, v, m, s) for o, v, m in jobs for s in self.species}, "16×365敏感性不完整")
            ensure(all(r["PrimaryKey"] == self.selected[(r["Outcome"], "primary", r["Model"])]["Key"] and
                       r["AlternativeKey"] == self.selected[(r["Outcome"], r["Variant"], r["Model"])]["Key"] for r in self.sens), "敏感性来源key错配")

    def ppc_stage(self, phase):
        if phase not in self.phase: raise NotReady(phase + "后处理尚未就绪")
        summaries = self.read(self.res / f"ppc_summary_all_{phase}.csv", columns=["Outcome", "Model", "Variant", "Key", "Subset", "ObservedOneFraction"])
        draws = self.read(self.res / f"ppc_statistic_plot_data_{phase}.csv", columns=["Outcome", "Model", "Variant", "Key", "Subset", "Replicate", "OneFraction"])
        groups = defaultdict(list)
        for r in draws: groups[(r["Outcome"], r["Model"], r["Variant"], r["Key"], r["Subset"])].append(r)
        ensure(len(summaries) == (30 if phase == "primary" else 26), "PPC模型/类型范围不完整")
        counts = [r for r in self.obs if r["Type"] == "count"]
        actual_ones = sum(num(r["Events"]) == num(r["Total"]) for r in counts)
        result = {}
        for s in summaries:
            identity = s["Outcome"], s["Model"], s["Variant"], s["Key"], s["Subset"]
            rows = groups[identity]
            ensure(len(rows) == 500 and len({r["Replicate"] for r in rows}) == 500, "既有500次PPC复制缺失或重复")
            ensure(s["Key"] == self.selected[(s["Outcome"], s["Variant"], s["Model"])]["Key"], "PPC与选用模型不一致")
            if s["Outcome"] == "joint" and s["Subset"] == "count":
                ensure(near(s["ObservedOneFraction"], actual_ones/len(counts), 1e-12), "PPC的100%记录比例与原始count资料不同")
                values = [num(r["OneFraction"]) for r in rows]
                ensure(all(math.isfinite(v) and 0 <= v <= 1 for v in values), "PPC复制比例无效")
                result[(s["Model"], s["Variant"])] = {"Observed": actual_ones/len(counts), "Lower": q7(values, .025),
                    "Median": q7(values, .5), "Upper": q7(values, .975), "Key": s["Key"], "Count": len(counts), "Ones": actual_ones}
        self.ppc[phase] = result
        if phase == "primary":
            flag_path = self.root / "review/primary_ppc_descriptive_flags.csv"
            flags = self.read(flag_path, columns=["Outcome", "Model", "Variant", "Key", "Subset", "Statistic", "Observed", "ReplicatedLower95", "ReplicatedUpper95", "DescriptiveFlag"])
            receipt = self.read(flag_path.with_suffix(".json"), "json")
            ensure(len(flags) == receipt.get("rows") == 90 and receipt.get("output_sha256") == self.sha(flag_path), "90项主PPC描述标记/哈希不一致")
            ensure(receipt.get("script_sha256") == self.sha(self.root / "scripts/summarize_ppc_checks.py"), "PPC描述脚本改变，需刷新描述输出")
            for rel, digest in receipt["source_sha256"].items(): ensure(self.sha(self.path(rel)) == digest, "PPC描述来源已改变：" + rel)
            for m in MODELS:
                row = [r for r in flags if r["Outcome"] == "joint" and r["Model"] == m and r["Subset"] == "count" and r["Statistic"] == "OneFraction"]
                ensure(len(row) == 1, "缺少某模型100%记录比例PPC标记")
                v = result[(m, "primary")]
                ensure(row[0]["Key"] == v["Key"] and near(row[0]["Observed"], v["Observed"], 1e-12) and
                       near(row[0]["ReplicatedLower95"], v["Lower"], 1e-12) and near(row[0]["ReplicatedUpper95"], v["Upper"], 1e-12), "主PPC描述标记与既有复制数据不一致")
        else:
            ensure(all((m, "beta_binomial") in result for m in ["M1_U", "M1_P"]), "缺少joint M1_U/P beta-binomial既有PPC")

    def cv_selection_stage(self):
        rows = self.read(self.root / "provenance/selected_cv_manifest.csv", columns=["Outcome", "CVType", "Model", "CVKey", "ParentKey", "CVFile", "ParentFile", "Attempt"])
        for r in rows:
            key = r["Outcome"], r["CVType"], r["Model"]
            if key not in self.cvs or num(r["Attempt"]) > num(self.cvs[key]["Attempt"]): self.cvs[key] = r
        expected = {(o, d, m) for o in OUTCOMES for d in DESIGNS for m in MODELS}
        ensure(set(self.cvs) <= expected, "CV清单出现计划外结构")
        for key, r in self.cvs.items():
            ensure(self.selected.get((key[0], "primary", key[2]), {}).get("Key") == r["ParentKey"], "CV与当前主模型不一致：" + str(key))
            ensure(self.path(r["CVFile"]).is_file() and self.path(r["ParentFile"]).is_file(), "CV或父拟合RDS不存在")
        missing = expected - self.cvs.keys()
        if missing: raise NotReady("40套CV未齐：" + str(sorted(missing)))

    def numerical_compatibility_stage(self):
        parent_keys = {m: self.selected[("joint", "primary", m)]["Key"] for m in MODELS
                       if ("joint", "primary", m) in self.selected}
        if len(parent_keys) != 10: raise NotReady("数值兼容性需要十个当前joint主拟合")
        self.numerical_compatibility = validate_compatibility(self.root, parent_keys,
            csv_reader=lambda p: self.read(p), sha=self.sha)
        self.read(self.root / MATH_REVIEW, "text")

    def extension_stage(self, key):
        o, d, m = key
        if key not in self.cvs: raise NotReady("该CV尚未选用PASS：" + "/".join(key))
        folder = self.root / "derived/cv_extensions" / "_".join(key)
        state = self.read(folder / "postprocessing_manifest.json", "json")
        ensure(state.get("status") == "PASS" and all(state.get(k) == v for k, v in {"Outcome": o, "CVType": d, "Model": m,
            "CVKey": self.cvs[key]["CVKey"], "FitKey": self.cvs[key]["ParentKey"]}.items()), "扩展输出身份不符：" + str(key))
        method = validate_extension_manifest(self.root, state, sha=self.sha)
        receipts = []
        for p in (self.root / "runs/job_receipts").glob("cv__*/status.json"):
            receipt = self.read(p, "json")
            if (receipt.get("status") == "PASS" and receipt.get("key") == state["CVKey"] and
                    (receipt.get("outcome"), receipt.get("cv_type"), receipt.get("model")) == key):
                receipts.append(receipt)
        ensure(len(receipts) == 1, "扩展未对应唯一PASS CV receipt")
        validate_score_receipt_protocol(receipts[0], method)
        if method == STABLE_PROTOCOL:
            if self.numerical_compatibility is None: raise NotReady("完整100折数值兼容性尚未通过")
            validate_raw_fold_metadata(self.root, state, self.numerical_compatibility,
                cv_directory=self.path(self.cvs[key]["CVFile"]).parent, sha=self.sha)
            ensure(receipts[0].get("sampling_changed") is False and receipts[0].get("likelihood_helper_sha256") == state["LikelihoodHelperSHA256"],
                   "数值修复不得改变抽样或混用helper")
        self.numerical_protocols[key] = method
        mc = self.read(folder / "cv_fold_scores_mc.csv", columns=["Fold", "ELPD", "CVKey", "FitKey", "MCReviewStatus", "DeltaMethod_MCSE_LogPredictive", "MaxNormalizedContribution", "EffectiveContributionCount"])
        ensure(len(mc) == 5 and {int(num(r["Fold"])) for r in mc} == set(range(1, 6)) and all(r["SamplingStatus"] == "PASS" and
            r["CVKey"] == state["CVKey"] and r["FitKey"] == state["FitKey"] and math.isfinite(num(r["ELPD"])) for r in mc), "五折MC/身份表不完整")
        source_checks = self.read(folder / "source_draw_order_checks.csv", columns=["Fold", "CVKey", "FitKey", "NativeIterationChainMapping", "HeldoutSourceOrder"])
        ensure(len(source_checks) == 5 and all(r["CVKey"] == state["CVKey"] and r["FitKey"] == state["FitKey"] and
            r["NativeIterationChainMapping"] == "PASS" and r["HeldoutSourceOrder"] == "PASS" for r in source_checks), "缺少源抽样顺序检查")
        payload = {"manifest": state, "mc": mc}
        if o == "joint":
            metrics = self.read(folder / "quantitative_metrics_by_record.csv", columns=["RecordID", "Species", "Type", "PointRule", "CVKey", "FitKey"])
            summaries = self.read(folder / "quantitative_metrics_summary.csv", columns=["Type", "NRecords", "NSpecies", "MAE", "RMSE", "CRPS", "Coverage50", "Coverage95", "MeanPredictiveWidth50", "MeanPredictiveWidth95", "SourceRecordIDs", "PointRule", "Weighting"])
            intervals = self.read(folder / "oof_interval_probability.csv", columns=["RecordID", "Lower", "Upper", "PredictiveEventProbability"])
            ensure(len(metrics) == 145 and {r["RecordID"] for r in metrics} == self.point_ids and len({r["Species"] for r in metrics}) == 48,
                   "定量点评价未覆盖145记录/48物种")
            ensure(len(intervals) == 8 and {r["RecordID"] for r in intervals} == self.interval_ids, "区间事件评价未覆盖8条原区间")
            ensure(len(summaries) == 3 and {r["Type"] for r in summaries} == {"count+exact", "count", "exact"}, "定量分层汇总不齐")
            for tab in [metrics, summaries]:
                ensure(all(r["CVKey"] == state["CVKey"] and r["FitKey"] == state["FitKey"] and r["PointRule"] == POINT_RULE for r in tab), "定量来源或点预测规则不一致")
            for row in summaries:
                expected = self.points if row["Type"] == "count+exact" else [r for r in self.points if r["Type"] == row["Type"]]
                ids = row["SourceRecordIDs"].split("|")
                ensure(len(ids) == len(set(ids)) == len(expected) and set(ids) == {r["RecordID"] for r in expected} and
                       num(row["NRecords"]) == len(expected) and num(row["NSpecies"]) == len({r["Species"] for r in expected}) and
                       row["Weighting"] == "equal_weight_per_experiment", "定量共同记录范围/权重不一致")
                ensure(all(math.isfinite(num(row[c])) for c in ["MAE", "RMSE", "CRPS", "Coverage50", "Coverage95", "MeanPredictiveWidth50", "MeanPredictiveWidth95"]), "定量指标含非有限值")
            payload.update(metrics=metrics, summaries={r["Type"]: r for r in summaries})
        self.extensions[key] = payload

    def cv_aggregate_stage(self):
        folder = self.root / "derived/cv_comparisons"
        state = self.read(folder / "postfit_cv_status.json", "json")
        if state.get("status") != "COMPLETE_KEEP_MC_AND_AUC_LIMITATIONS": raise NotReady("完整CV后处理尚未完成")
        ensure(state.get("cv_designs") == 4 and state.get("cv_models") == 40 and state.get("fold_fits") == 200 and
               state.get("point_metric_rule") == POINT_RULE and len(self.extensions) == 40, "40CV/200折/40扩展尚未同时齐全")
        ensure(self.numerical_compatibility is not None and Counter(self.numerical_protocols.values()) == Counter({LEGACY_PROTOCOL: 35, STABLE_PROTOCOL: 5}) and
               state.get("numerical_likelihood_method") == STABLE_PROTOCOL and state.get("numerical_compatibility_folds") == 100 and
               state.get("compatibility_manifest_sha256") == self.numerical_compatibility["manifest_sha256"],
               "必须同时保留35份旧导出、5份明确数值修复和100折兼容性证据")
        methods = self.read(folder / "cv_numerical_protocols.csv", columns=["Outcome", "CVType", "Model", "CVKey", "NumericalLikelihoodMethod"])
        ensure(len(methods) == 40 and all(r["NumericalLikelihoodMethod"] == self.numerical_protocols.get((r["Outcome"],r["CVType"],r["Model"])) and
               r["CVKey"] == self.cvs[(r["Outcome"],r["CVType"],r["Model"])]["CVKey"] for r in methods), "最终数值协议表与当前CV不一致")
        self.comparisons, self.aucs, self.briers, self.auc_folds = {}, {}, {}, {}
        for o in OUTCOMES:
            for d in DESIGNS:
                part = folder / (o + "_" + d)
                comparison = self.read(part / "cv_model_comparison_with_mc.csv", columns=["Outcome", "CVType", "Model", "ELPD", "MCFlaggedFolds", "Interpretation"])
                diags = self.read(part / "cv_fold_diagnostics.csv", columns=["Outcome", "CVType", "Model", "Fold", "CVKey", "ParentKey", "Status"])
                ensure(len(comparison) == 10 and {r["Model"] for r in comparison} == set(MODELS) and len(diags) == 50 and
                       {(r["Model"], int(num(r["Fold"]))) for r in diags} == {(m, f) for m in MODELS for f in range(1, 6)} and diagnostic_ok(diags), "CV十模型/五十折覆盖或诊断不足")
                for row in comparison:
                    key = o, d, row["Model"]
                    mc = self.extensions[key]["mc"]
                    ensure(near(row["ELPD"], sum(num(r["ELPD"]) for r in mc), 1e-8) and num(row["MCFlaggedFolds"]) == sum(r["MCReviewStatus"] != "NO_SCREEN_FLAG" for r in mc), "ELPD或MC标记与扩展不一致")
                self.comparisons[(o, d)] = {r["Model"]: r for r in comparison}
                if o == "binary":
                    aucs = self.read(part / "auc_summary.csv", columns=["Model", "CV_AUC", "Status", "Records", "Species"])
                    folds = self.read(part / "auc_by_fold.csv", columns=["Model", "Fold", "High", "Low", "AUC", "Status"])
                    brier = self.read(part / "brier_scores.csv", columns=["Model", "Fold", "Records", "Species", "BrierScore", "Weighting"])
                    overall = [r for r in brier if not math.isfinite(num(r["Fold"]))]
                    ensure(len(aucs) == len(overall) == 10 and {r["Model"] for r in aucs} == set(MODELS) and
                           {r["Model"] for r in overall} == set(MODELS) and len(folds) == 50, "分类AUC/Brier覆盖不足")
                    for r in aucs:
                        f = [x for x in folds if x["Model"] == r["Model"]]
                        all_defined = all(math.isfinite(num(x["AUC"])) for x in f)
                        ensure(num(r["Records"]) == 152 and num(r["Species"]) == 50 and all_defined == (d == "species"), "分类评分范围或单类别状态不同")
                        ensure(near(r["CV_AUC"], statistics.mean(num(x["AUC"]) for x in f), 1e-12) if all_defined else
                               (r["Status"] == "NOT_DEFINED_ONE_CLASS_FOLD" and math.isnan(num(r["CV_AUC"]))), "AUC未沿用全部折平均/NA规则")
                    ensure(all(num(r["Records"]) == 152 and r["Weighting"] == "equal_weight_per_experiment" and 0 <= num(r["BrierScore"]) <= 1 for r in overall), "Brier范围或权重不符")
                    self.aucs[d], self.briers[d], self.auc_folds[d] = {r["Model"]: r for r in aucs}, {r["Model"]: r for r in overall}, folds

    def matrix_stage(self, outcome):
        parent = self.selected.get((outcome, "primary", "M3_P"))
        if not parent: raise NotReady("M3_P父拟合尚未完成")
        folder = self.run / "matrix_checks" / (outcome + "_M3_P") / ("parent_" + parent["Key"][:16])
        completed = []
        for p in sorted(folder.glob("attempt_*/status.json")):
            state = self.read(p, "json")
            if state.get("status") in {"COMPLETE_WITHIN_2_MCSE", "COMPLETE_WITH_REVIEW_DIFFERENCES"}: completed.append((p, state))
        if not completed: raise NotReady(outcome + "矩阵检查尚未完成")
        ensure(len(completed) == 1, "同一父拟合有多个矩阵完成版本")
        p, state = completed[0]
        ds = self.read(p.parent / "matrix_diagnostics_status.csv", columns=["Side", "Status", "MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI"])
        rows = self.read(self.path(state["plot_data_file"]), columns=["Quantity", "Difference", "JointMCSE", "ReviewFlag", "ParentKey", "CheckKey"])
        ensure(len(ds) == 2 and {r["Side"] for r in ds} == {"full", "sub"} and diagnostic_ok(ds) and state["parent_key"] == parent["Key"], "矩阵来源或抽样诊断不符")
        for row in rows:
            expected = "within_2_MCSE" if abs(num(row["Difference"])) <= 2*num(row["JointMCSE"]) else "review_difference"
            ensure(row["ParentKey"] == parent["Key"] and row["CheckKey"] == state["check_key"] and row["ReviewFlag"] == expected, "矩阵差异标记改变")
        ensure(state["review_differences"] == sum(r["ReviewFlag"] == "review_difference" for r in rows), "矩阵复核数量不一致")
        self.matrices[outcome] = state, rows

    def figure_stage(self):
        dfolder, mfolder = self.root / "figures/descriptive", self.root / "figures/model"
        dqa = self.read(dfolder / "metadata_checks.json", "json")
        mqa = self.read(mfolder / "final_figure_checks.json", "json")
        if dqa.get("status") != "PASS_DESCRIPTIVE_FIGURES" or not dqa.get("manual_visual_review", {}).get("completed"):
            raise NotReady("描述图视觉复核尚未完成")
        if mqa.get("status") != "PASS_MODEL_FIGURES" or not mqa.get("manual_visual_review_confirmed") or mqa.get("pending_scopes"):
            raise NotReady("模型图未全部完成并通过既有视觉复核")
        didx = self.read(dfolder / "FIGURE_INDEX.csv", columns=["FigureID", "PDF", "SVG", "PNG_600dpi", "SourceCSV"])
        midx = self.read(mfolder / "FIGURE_INDEX.csv", columns=["FigureID", "Group", "Scope", "PDF", "SVG", "PNG", "SourceCSV", "VisualReview"])
        scopes = self.read(mfolder / "FIGURE_STATUS.csv", columns=["Group", "Scope", "Status"])
        expected = {(g, o) for o in OUTCOMES for g in ["coefficients", "diagnostics", "pareto", "ppc", "ppc_ecdf", "sensitivity_ppc", "matrix_check"]}
        expected |= {(g, o+"_"+d) for o in OUTCOMES for d in DESIGNS for g in ["cv_elpd", "cv_mc", "cv_diagnostics"]}
        expected |= {(g, d) for d in DESIGNS for g in ["roc_calibration", "quantitative", "predictive_bands", "metrics"]}
        expected |= {("species_predictions", "both"), ("sensitivity", "both"), ("folds", "all")}
        ensure(len(didx) == 21 and len({r["FigureID"] for r in didx}) == 21 and len(scopes) == 37 and
               {(r["Group"], r["Scope"]) for r in scopes} == expected and {(r["Group"], r["Scope"]) for r in midx} == expected,
               "21描述页/37模型scope未齐")
        ensure(all(r["Status"] == "GENERATED_AWAITING_VISUAL_REVIEW" for r in scopes) and all(r["VisualReview"] == "COMPLETED_BY_REVIEWER" for r in midx), "有未完成/未复核图页")
        ensure(mqa.get("figures") == len(midx) and {r["FigureID"] for r in mqa.get("exports", [])} == {r["FigureID"] for r in midx}, "模型图逐页QA覆盖不符")
        for folder, index, png in [(dfolder, didx, "PNG_600dpi"), (mfolder, midx, "PNG")]:
            for r in index:
                ensure(all((folder / r[c]).is_file() for c in ["PDF", "SVG", png]) and self.path(r["SourceCSV"]).is_file(), "图索引指向缺失文件")
        self.figures = {"descriptive": didx, "model": midx, "model_qa": mqa}

    def load_all(self):
        self.read(Path(__file__).resolve(), "text")
        self.read(Path(__file__).with_name("numerical_likelihood_contract.py"), "text")
        self.stage("固定输入、145/48与Site151事实", self.input_stage)
        self.stage("20主拟合+16敏感性选用及诊断", self.selection_stage)
        for phase in ["primary", "sensitivity"]:
            self.stage(phase + "完整后处理", lambda phase=phase: self.phase_stage(phase))
            self.stage(phase + "既有PPC事实", lambda phase=phase: self.ppc_stage(phase))
        self.stage("固定抽样的100折稳定数值兼容性", self.numerical_compatibility_stage)
        self.stage("40CV选用", self.cv_selection_stage)
        for o in OUTCOMES:
            for d in DESIGNS:
                for m in MODELS: self.stage("扩展：" + "/".join([o, d, m]), lambda key=(o, d, m): self.extension_stage(key))
        self.stage("40CV/200折最终评分后处理", self.cv_aggregate_stage)
        for o in OUTCOMES: self.stage("矩阵：" + o, lambda o=o: self.matrix_stage(o))
        self.stage("全部模型图和描述图完成情况", self.figure_stage)

    def unchanged(self):
        changed = []
        for p, row in self.sources.items():
            if not p.is_file() or p.stat().st_size != row["Bytes"] or p.stat().st_mtime_ns != row["MtimeNS"] or actual_sha(p) != row["SHA256"]:
                changed.append(row["RelativePath"])
        return changed

    def readiness(self):
        changed = self.unchanged()
        if changed: self.gates.append({"Stage": "读取期间来源稳定", "Status": "INCOMPLETE", "Detail": str(changed)})
        counts = Counter(r["Status"] for r in self.gates)
        status = "CONFLICT" if counts["CONFLICT"] else ("INCOMPLETE" if counts["INCOMPLETE"] else "READY_TO_GENERATE")
        return {"version": VERSION, "status": status, "root": str(self.root), "run": self.run.relative_to(self.root).as_posix(),
                "checked_at": datetime.now(timezone.utc).isoformat(), "gates": self.gates, "gate_counts": dict(counts),
                "source_files_read": len(self.sources), "extensions_ready": len(self.extensions), "final_report_written": False,
                "not_final_acceptance": True, "new_fits_or_draws": False}

    def render(self):
        return render_report(self)


def render_report(b):
    lines = ["# 计算结果报告", "", "本报告汇总本次固定输入的实际计算和图件结果。指标及图件的基础读法见同目录《模型与图表阅读说明》，服务器复核步骤见《服务器手动复核说明》。", "",
        "**计算与图件的规定范围已经齐全，但数值计算通过不等于模型适合解释这些资料。尤其要保留计数资料中100%记录比例的PPC不合、部分整折积分的MC精度限制及M3共线性。** 本报告不选定唯一最佳模型，不把site315设为统一参照，也不替代audit_final_run.py的独立最终文件验收。", "",
        "## 本次结果范围", "", table(["项目", "实际范围"], [["输入", "153条记录；51个有比率资料物种；63个来源；365物种位点/树面板"],
        ["分类留出评价", "152条可分类实验、50个物种：116 HIGH、36 LOW"], ["定量点评价", "145条count/exact记录、48个物种；105 count、40 exact；8个区间另作事件概率评价"],
        ["主拟合与敏感性", "20个主拟合＋16个预定敏感性拟合"], ["留出计算", "两种设计×两路线×十模型＝40套CV、200次留出重拟合"], ["矩阵核查", "binary和joint的M3_P，共两项，保留原2×MCSE复核规则"]]), "",
        "分类分数沿用Trials=1的留出概率后验中位数。定量MAE/RMSE统一使用m的后验均值；CRPS、覆盖率和宽度来自未来实验结果预测分布。所有表按固定模型顺序列出；ELPD仅在同一路线、同一划分下比较。", ""]
    numerical = b.numerical_compatibility
    lines += ["本次保留35份原数值评分导出；另5套joint/P/phylo_distance用稳定对数尾概率评价同一个Beta区间概率，修复原实现的数值相消。**原抽样和fold_fits未改，没有重新拟合，也没有改目标模型。** "
        f"独立高精度复核覆盖20个实际坏例，误差约1e-14；完整100折兼容性表记录{numerical['original_nonfinite_heldout']}个原留出非有限值、0个原训练非有限值和0个修正后非有限值。"
        f"训练联合log差最大{numerical['max_training_joint_log_difference']:.3g}，原值全有限折的ELPD差最大{numerical['max_original_finite_elpd_difference']:.3g}，事件概率差最大{numerical['max_event_probability_difference']:.3g}，均通过既定复核阈值。"
        "数值复核与源文件哈希见review/likelihood_diagnosis_20260916及独立数学复核报告。", ""]
    for d in DESIGNS:
        lines += ["## " + DESIGN_NAME[d] + "：分类", "", table(["模型", "完整折平均AUC", "逐折AUC（1–5）", "Brier"],
            [[m, fmt(b.aucs[d][m]["CV_AUC"]), " / ".join(fmt(next(r for r in b.auc_folds[d] if r["Model"] == m and int(num(r["Fold"])) == f)["AUC"]) for f in range(1, 6)),
              fmt(b.briers[d][m]["BrierScore"], 4)] for m in MODELS]), ""]
        if d == "phylo_distance":
            single = sorted({int(num(r["Fold"])) for r in b.auc_folds[d] if not math.isfinite(num(r["AUC"]))})
            lines += ["第" + "、".join(map(str, single)) + "折只有一种真实类别，因此这些折及包含全部五折的平均CV_AUC为NA；没有删除这些折后重算平均。Brier仍使用所有152条留出实验。", ""]
        else: lines += ["AUC是所有五折的等权平均；Brier按实验记录等权。这里没有把折间波动当作95%置信区间。", ""]
        lines += ["## " + DESIGN_NAME[d] + "：定量", "", "下表MAE、RMSE、CRPS及区间宽度均以**百分点**表示，覆盖率以%表示。总体为145条记录/48个物种，不能当成145个独立物种。", "",
            table(["模型", "MAE", "RMSE", "CRPS", "50%覆盖", "95%覆盖", "50%平均宽度", "95%平均宽度"],
                [[m] + [fmt(b.extensions[("joint", d, m)]["summaries"]["count+exact"][c], 2, 100) for c in
                    ["MAE", "RMSE", "CRPS", "Coverage50", "Coverage95", "MeanPredictiveWidth50", "MeanPredictiveWidth95"]] for m in MODELS]), ""]
        for kind in ["count", "exact"]:
            sr = b.extensions[("joint", d, MODELS[0])]["summaries"][kind]
            lines += [f"**{kind}分层：{int(num(sr['NRecords']))}条记录、{int(num(sr['NSpecies']))}个物种。**", "",
                table(["模型", "MAE", "RMSE", "CRPS", "50%覆盖", "95%覆盖", "95%平均宽度"],
                    [[m] + [fmt(b.extensions[("joint", d, m)]["summaries"][kind][c], 2, 100) for c in
                        ["MAE", "RMSE", "CRPS", "Coverage50", "Coverage95", "MeanPredictiveWidth95"]] for m in MODELS]), ""]
        lines += ["## " + DESIGN_NAME[d] + "：原整折ELPD与积分精度", "",
            table(["模型", "分类ELPD", "分类MC复核折数", "定量ELPD", "定量MC复核折数"],
                [[m, fmt(b.comparisons[("binary", d)][m]["ELPD"], 2), int(num(b.comparisons[("binary", d)][m]["MCFlaggedFolds"])),
                  fmt(b.comparisons[("joint", d)][m]["ELPD"], 2), int(num(b.comparisons[("joint", d)][m]["MCFlaggedFolds"]))] for m in MODELS]), "",
            "这里保留原来的整折联合预测积分，没有改成逐记录边际分数之和。MC复核计数表示触发既定描述性精度筛查的折数；不是参数ESS不合格次数，也不是显著性检验。分数受少量抽样支配时，不能依据有限精度排序宣称唯一最佳模型。", ""]
    primary = b.ppc["primary"]
    actual = primary[(MODELS[0], "primary")]
    above = [m for m in MODELS if actual["Observed"] > primary[(m, "primary")]["Upper"] + 1e-12]
    lines += ["## 必须保留的拟合不足及计数敏感性", "",
        f"原始105条count记录中有{actual['Ones']}条为100%，占{fmt(actual['Observed'], 2, 100)}%。{len(above)}/10个joint主模型的这一观测比例高于其500次既有PPC复制的中央95%范围上界。" +
        ("**因此，十个主计数模型共同低估了100%记录出现的比例；不能因为抽样诊断通过就称它们充分描述了这批资料。**" if len(above) == 10 else "应按下表逐模型保留当前实际PPC差异，不能以数值诊断替代适配检查。"), "",
        table(["主模型", "PPC复制中位数（%）", "PPC中央95%范围（%）", "观测高于上界"],
            [[m, fmt(primary[(m, "primary")]["Median"], 2, 100), f"{fmt(primary[(m, 'primary')]['Lower'],2,100)}–{fmt(primary[(m, 'primary')]['Upper'],2,100)}", "是" if m in above else "否"] for m in MODELS]), "",
        "以下仅重新汇总已经保存的500次PPC复制，没有重新拟合或抽样。beta-binomial比较仍是训练内的描述性模型检查，不是新的留出验证或校准检验。", "",
        table(["joint结构", "计数分布", "复制中位数（%）", "复制中央95%范围（%）", "观测是否位于范围内"],
            [[m, v, fmt(x["Median"], 2, 100), f"{fmt(x['Lower'],2,100)}–{fmt(x['Upper'],2,100)}", "是" if x["Lower"]-1e-12 <= x["Observed"] <= x["Upper"]+1e-12 else "否"]
             for m in ["M1_U", "M1_P"] for v, x in [("主二项模型", primary[(m, "primary")]), ("beta-binomial敏感性", b.ppc["sensitivity"][(m, "beta_binomial")])]]), ""]
    for m in ["M1_U", "M1_P"]:
        p, s = primary[(m, "primary")], b.ppc["sensitivity"][(m, "beta_binomial")]
        relation = "落入" if s["Lower"]-1e-12 <= s["Observed"] <= s["Upper"]+1e-12 else ("仍高于" if s["Observed"] > s["Upper"] else "低于")
        lines += [f"{m}改用beta-binomial后，复制中位数从{fmt(p['Median'],2,100)}%变为{fmt(s['Median'],2,100)}%，原观测{relation}该敏感性版本的中央95%复制范围。这个变化说明加入额外计数变异改变了模型对端点数据的描述，不能单独证明该版本已消除来源差异或可用于任意实验条件。", ""]
    lines += ["## 位点证据、M1结构差异与M3限制", ""]
    states = "、".join(f"{aa} {n}" for aa, n in b.site151_observed.most_common())
    panel = "、".join(f"{aa} {n}" for aa, n in b.site151_panel.most_common())
    lines += [f"按实际输入重新统计：51个有比率资料物种的Site151状态为{states}；365物种面板为{panel}。" +
        ("**有结果资料的物种在Site151没有氨基酸变异，当前数据不能估计该位点不同氨基酸之间的效应；系数图缺少该项是无可用观测变异，不是漏绘。**" if len(b.site151_observed) == 1 else
         "当前有结果物种已存在多种Site151状态，应依据现有编码与设计矩阵重新判断可估性，不能沿用无观测变异的结论。"), ""]
    for o in OUTCOMES:
        u = {r["OriginalTerm"]: r for r in b.parameters[o] if r["Model"] == "M1_U" and r["OriginalTerm"].startswith("M1_Site")}
        p = {r["OriginalTerm"]: r for r in b.parameters[o] if r["Model"] == "M1_P" and r["OriginalTerm"].startswith("M1_Site")}
        ensure(set(u) == set(p), "M1_U/P系数项不匹配，拒绝报告错位区间")
        refs = {r["OriginalTerm"]: r["ReferenceLevel"] for r in b.term_map if r["Outcome"] == o and r["Group"] == "M1"}
        lines += ["**" + OUTCOME_NAME[o] + "的M1系数：后验均值及95%后验区间（logit尺度）。**", "",
            table(["编码项", "参照水平", "M1_U", "M1_P"], [[t, refs.get(t, "未映射"),
                f"{fmt(u[t]['mean'])} [{fmt(u[t]['Lower95'])}, {fmt(u[t]['Upper95'])}]",
                f"{fmt(p[t]['mean'])} [{fmt(p[t]['Lower95'])}, {fmt(p[t]['Upper95'])}]"] for t in u]), ""]
    lines += ["U/P的系数与区间差异以实际数值如上报告。P还增加了带亲缘相关结构的物种差异，因此这些变化不能单独归因于亲缘校正，也不能写成某种氨基酸的独立因果效应。", "",
        table(["设计", "实际秩", "含截距列数"], [[r["Blueprint"], r["Rank"], r["ParameterColumns"]] for r in b.blueprints if r["Blueprint"] in {"binary_M3", "joint_M3"}]), "",
        "秩小于列数意味着部分方向缺少独立识别信息。正规先验能产生数值后验，但不会创造这些信息；M3系数及依赖这些方向的预测必须保留先验依赖标志。", "",
        "## PSIS、敏感性和全部物种预测", "",
        table(["路线", "PSIS排名状态", "有问题模型数", "问题行数"], [[OUTCOME_NAME[r["Outcome"]], r["RankingStatus"], r["ModelsWithProblemRows"], r["ProblemRows"]] for r in b.loo]), "",
        "REFUSED_USE_GROUPED_CV表示拒绝以不可靠PSIS强行排名；真实分组留出结果已另列。两条路线的逐行LOO单位不同，不能混排。", ""]
    sens_rows = []
    for o, v, m in sorted(b.sensitivity_jobs, key=lambda x: (OUTCOMES.index(x[0]), MODELS.index(x[2]), ["b_sd_025", "b_sd_100", "rho_beta22", "beta_binomial"].index(x[1]))):
        z = [r for r in b.sens if (r["Outcome"], r["Variant"], r["Model"]) == (o, v, m) and boolean(r["Supported"])]
        shifts = [abs(num(r["MedianShift"])) for r in z]
        sens_rows.append([OUTCOME_NAME[o], m, v, len(z), fmt(statistics.mean(shifts) if shifts else math.nan, 2, 100), fmt(max(shifts) if shifts else math.nan, 2, 100)])
    lines += ["下表在各模型编码可支持的面板物种中，汇总相对对应主模型的期望量**后验中位数**变化。它是设置敏感性，不是独立预测性能。", "",
              table(["路线", "模型", "敏感性设置", "支持物种数", "平均绝对变化（百分点）", "最大绝对变化（百分点）"], sens_rows), ""]
    support = []
    for m in SIX:
        z = [r for r in b.long if r["Model"] == m]
        support.append([m] + [sum(boolean(r[p+"Supported"]) for r in z) for p in ["Binary", "Ratio"]] +
                       [sum(not boolean(r[p+"Supported"]) for r in z) for p in ["Binary", "Ratio"]] +
                       [sum(boolean(r[p+"Supported"]) and not boolean(r[p+"FixedEffectEstimable"]) for r in z) for p in ["Binary", "Ratio"]])
    lines += [table(["模型", "分类支持数", "定量支持数", "分类留空数", "定量留空数", "分类未识别方向数", "定量未识别方向数"], support), "",
        "07长表完整保留2190行、宽表365行。不支持的编码水平留空，不等于比率为0；无实验物种的输出是投影，不是新增实验。PrHigh和PredictedRatio沿用07的后验中位数；各自95%区间针对概率/整体期望量，不是下一实验结果的95%预测区间。", "",
        "## 矩阵、图件及复核入口", "",
        table(["路线", "状态", "共同量数", "2×MCSE范围外项数"], [[OUTCOME_NAME[o], b.matrices[o][0]["status"], len(b.matrices[o][1]), b.matrices[o][0]["review_differences"]] for o in OUTCOMES]), "",
        "COMPLETE_WITH_REVIEW_DIFFERENCES表示数值检查已完成但差异旗标保留，不等于检查未执行，也不是统计等价证明；未换种子或放宽2×MCSE规则追求旗标清零。", "",
        table(["图集", "实际图页数", "PDF文件数", "索引"], [["描述图", len(b.figures["descriptive"]), len({r["PDF"] for r in b.figures["descriptive"]}), "figures/descriptive/FIGURE_INDEX.csv"],
            ["模型图", len(b.figures["model"]), len({r["PDF"] for r in b.figures["model"]}), "figures/model/FIGURE_INDEX.csv"]]), "",
        "上述索引、逐图数据和既有视觉复核状态已齐全。图件是发表候选材料；格式完成不证明模型科学适用，也不保证某一期刊的最终格式要求。完整来源路径及SHA256在本报告同名的“来源清单.csv”中；生成记录保留所有门槛和读取期间的来源身份。", "",
        "来源可比性、独立实验定义和生物学位点对应仍是本次分析的条件。SourceID用于追踪，没有因此自动消除研究条件或资料收集偏差。对于当前共同的PPC不足以及具体模型的MC/先验敏感性限制，应在论文中如实披露；不能把计算完成解释为所有模型都适用。", "",
        "生成时间（UTC）：" + datetime.now(timezone.utc).isoformat(), ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--run", default="formal_20260914_26e686af86fa")
    parser.add_argument("--check-inputs", action="store_true")
    parser.add_argument("--output", default="计算结果报告.md")
    args = parser.parse_args()
    b = Builder(args.root, args.run)
    b.load_all()
    readiness = b.readiness()
    review = b.root / "review"; review.mkdir(exist_ok=True)
    readiness_path = review / "result_report_readiness.json"
    readiness_path.write_text(json.dumps(readiness, ensure_ascii=False, indent=2), encoding="utf-8")
    if readiness["status"] != "READY_TO_GENERATE":
        print(json.dumps({"status": readiness["status"], "final_report_written": False, "readiness_report": str(readiness_path), "gate_counts": readiness["gate_counts"],
                          "missing_or_conflicting": [r for r in b.gates if r["Status"] != "READY"]}, ensure_ascii=False))
        return 1 if readiness["status"] == "CONFLICT" else 2
    if args.check_inputs:
        print(json.dumps({"status": "READY_TO_GENERATE", "final_report_written": False, "readiness_report": str(readiness_path)}, ensure_ascii=False)); return 0
    output = b.path(args.output)
    ensure(output.suffix.lower() == ".md", "正式报告输出必须为Markdown")
    sources_path = output.with_name(output.stem + "_来源清单.csv")
    manifest_path = output.with_name(output.stem + "_生成记录.json")
    ensure(not any(p.exists() for p in [output, sources_path, manifest_path]), "报告或同名清单已存在；请选择新输出名，不覆盖旧报告")
    text = b.render()
    ensure(not b.unchanged(), "来源在报告生成期间改变，拒绝输出")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    with sources_path.open("w", encoding="utf-8-sig", newline="") as handle:
        fields = ["RelativePath", "AbsolutePath", "Bytes", "SHA256", "MtimeNS", "Use"]
        writer = csv.DictWriter(handle, fieldnames=fields); writer.writeheader()
        writer.writerows(b.sources[p] for p in sorted(b.sources))
    manifest = {"version": VERSION, "status": "GENERATED_AWAITING_INDEPENDENT_FINAL_AUDIT", "not_final_acceptance": True,
                "root": str(b.root), "run": b.run.relative_to(b.root).as_posix(), "report": str(output), "sources": str(sources_path),
                "report_sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "source_manifest_sha256": hashlib.sha256(sources_path.read_bytes()).hexdigest(),
                "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "gates": b.gates,
                "source_map": {row["RelativePath"]: {"absolute_path": row["AbsolutePath"], "sha256": row["SHA256"]} for row in b.sources.values()},
                "point_rule": POINT_RULE, "model_order": MODELS, "new_fits_or_draws": False,
                "numerical_likelihood_method": STABLE_PROTOCOL, "numerical_compatibility_folds": 100,
                "compatibility_manifest_sha256": b.numerical_compatibility["manifest_sha256"],
                "score_protocol_counts": dict(Counter(b.numerical_protocols.values())),
                "final_auditor": "scripts/audit_final_run.py", "generated_at": datetime.now(timezone.utc).isoformat()}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"status": manifest["status"], "report": str(output), "sha256": manifest["report_sha256"], "sources": str(sources_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
