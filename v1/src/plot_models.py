"""Publication-candidate model figures from this run's verified postprocessing.

This script never fits, simulates, deduplicates, or imputes observations. Missing
formal data yield PENDING rows, not empty final images. Use --check-inputs first.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import traceback
import xml.etree.ElementTree as ET

BASE = Path(__file__).resolve().parents[1]
PLOT_SCRIPT_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
RUN = BASE / "runs" / "formal_20260914_26e686af86fa"
RES = RUN / "results"
DER = BASE / "derived"
FIG = BASE / "figures" / "model"
DATA = BASE / "figure_data" / "model"
FIG.mkdir(parents=True, exist_ok=True)
DATA.mkdir(parents=True, exist_ok=True)
os.environ["MPLCONFIGDIR"] = str(FIG / "_mplconfig")
sys.path.insert(0, str(BASE / "figures" / "descriptive" / "_runtime"))
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle
from matplotlib.colors import LogNorm
from matplotlib.ticker import MaxNLocator
import numpy as np
import pandas as pd
from PIL import Image
from pypdf import PdfReader
from Bio import Phylo

MODELS = ["Null_U", "Phylogeny_only_P", "Site315_U", "Site315_P", "M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P"]
SIX = ["M1_U", "M1_P", "M2_U", "M2_P", "M3_U", "M3_P"]
CVTYPES = ["species", "phylo_distance"]
OUTCOMES = ["binary", "joint"]
POINT_RULE = "posterior_mean_of_species_expected_ratio_m"
INK = "#182C3B"
GRAY = "#667B88"
GRID = "#DFE6EA"
BLUE, ORANGE, PURPLE = "#0072B2", "#D55E00", "#705288"
FC = [BLUE, ORANGE, "#009E73", "#AA3377", "#343C44"]
MARK = ["o", "s", "^", "D", "v"]
matplotlib.rcParams.update({"font.family": "DejaVu Sans", "font.size": 8,
    "axes.titlesize": 9.5, "axes.titleweight": "bold", "axes.labelsize": 8,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "legend.fontsize": 7,
    "text.color": INK, "axes.labelcolor": INK, "xtick.color": INK, "ytick.color": INK,
    "axes.spines.top": False, "axes.spines.right": False, "axes.linewidth": .6,
    "axes.edgecolor": "#A3B1BB", "legend.frameon": False,
    "pdf.fonttype": 42, "svg.fonttype": "none", "figure.facecolor": "white", "savefig.facecolor": "white"})
FILES, STATUSES, USED, CAPTIONS, TEXT_QA = [], [], {}, [], []
CURRENT_INPUTS = {}
CHECK_ONLY = False
CURRENT_GROUP, CURRENT_SCOPE = "", ""


class Pending(Exception):
    pass


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def register_input(p):
    p = Path(p)
    rel = str(p.relative_to(BASE))
    signature = {"SHA256": sha(p), "Bytes": p.stat().st_size}
    USED[rel] = signature
    CURRENT_INPUTS[rel] = signature
    return p


def read(p, cols=()):
    p = Path(p)
    if not p.is_file():
        raise Pending(f"Missing file: {p.relative_to(BASE)}")
    d = pd.read_csv(p, encoding="utf-8-sig", keep_default_na=True)
    if not set(cols) <= set(d.columns):
        raise ValueError(f"{p.name}: missing columns {sorted(set(cols) - set(d.columns))}")
    register_input(p)
    return d


def read_json(p):
    p = Path(p)
    if not p.exists():
        raise Pending(f"Missing manifest: {p.relative_to(BASE)}")
    register_input(p)
    return json.loads(p.read_text(encoding="utf-8-sig"))


def bools(x):
    if pd.api.types.is_bool_dtype(x):
        return x.fillna(False)
    return x.astype(str).str.lower().isin(["true", "1", "yes"])


def numeric_ok(d, cols, probability=False, allow_na=False):
    v = d[list(cols)].apply(pd.to_numeric, errors="raise").to_numpy(dtype=float)
    if not allow_na and not np.isfinite(v).all():
        raise ValueError(f"Nonfinite required values: {cols}")
    if probability and np.any((v[np.isfinite(v)] < -1e-10) | (v[np.isfinite(v)] > 1 + 1e-10)):
        raise ValueError(f"Probability outside [0,1]: {cols}")


def primary_gate():
    status = read_json(RES / "postfit_primary_status.json")
    if status.get("formal_output_gate") != "PASS_ALL_20_IDENTITIES_AND_DIAGNOSTICS":
        raise Pending("All 20 primary identity and diagnostic gates are not complete")
    if not str(status.get("status", "")).startswith("COMPLETE_"):
        raise Pending("Primary postprocessing is not complete")
    for out in OUTCOMES:
        d = read(RES / f"diagnostics_{out}_primary.csv", ["Model", "Status"])
        if set(d.Model) != set(MODELS) or not d.Status.eq("PASS").all():
            raise Pending(f"Incomplete or unpassed primary diagnostics: {out}")


def primary_table(name, cols=()):
    primary_gate()
    return read(RES / name, cols)


def cv_directory(out, cvtype):
    dm = read(BASE / "provenance" / "cv_directory_manifest.csv", ["Outcome", "CVType", "Directory", "FoldKey"])
    z = dm[(dm.Outcome == out) & (dm.CVType == cvtype)]
    if len(z) != 1:
        raise Pending(f"Unique CV directory not found: {out}/{cvtype}")
    p = RUN / "cv" / str(z.iloc[0].Directory).replace("\\", "/").rstrip("/").split("/")[-1]
    return p, str(z.iloc[0].FoldKey)


def extension(out, cvtype, model, filename, cols=()):
    folder = DER / "cv_extensions" / f"{out}_{cvtype}_{model}"
    meta = read_json(folder / "postprocessing_manifest.json")
    if meta.get("status") != "PASS":
        raise Pending(f"Extension export incomplete: {folder.name}")
    for k, v in {"Outcome": out, "CVType": cvtype, "Model": model}.items():
        if meta.get(k) != v:
            raise ValueError(f"Extension identity mismatch: {folder.name}/{k}")
    selected = read(BASE / "provenance" / "selected_cv_manifest.csv", ["Outcome", "CVType", "Model", "CVKey", "ParentKey"])
    z = selected[(selected.Outcome == out) & (selected.CVType == cvtype) & (selected.Model == model)]
    if len(z) != 1 or str(z.iloc[0].CVKey) != str(meta.get("CVKey")) or str(z.iloc[0].ParentKey) != str(meta.get("FitKey")):
        raise Pending(f"Extension is not the unique currently selected CV: {folder.name}")
    d = read(folder / filename, ["Outcome", "Model", "CVType", "CVKey", "FitKey", *cols])
    for field in ["Outcome", "Model", "CVType", "CVKey", "FitKey"]:
        if not d[field].astype(str).eq(str(meta[field])).all():
            raise ValueError(f"CSV/manifest identity mismatch: {folder.name}/{filename}/{field}")
    return d


def all_extensions(out, cvtype, filename, cols=()):
    return pd.concat([extension(out, cvtype, m, filename, cols) for m in MODELS], ignore_index=True)


def find_named(name, roots=None):
    roots = roots or [DER, RES, BASE / "provenance"]
    candidates = []
    for root in roots:
        if root.exists():
            candidates.extend(p for p in root.rglob(name) if "postfit_primary_audit" not in p.parts)
    candidates = sorted(set(candidates))
    if not candidates:
        raise Pending(f"Required formal export not yet available: {name}")
    if len(candidates) > 1:
        raise Pending(f"Ambiguous export; explicit identity needed: {name} ({len(candidates)} matches)")
    return candidates[0]


def source(stem, d):
    p = DATA / f"{stem}.csv"
    d.to_csv(p, index=False, encoding="utf-8-sig", na_rep="", lineterminator="\n")
    return str(p.relative_to(BASE))


def header(fig, title, subtitle="", y=.965):
    fig.text(.04, y, title, fontsize=12.5, weight="bold", va="top")
    if subtitle:
        fig.text(.04, y - .044, subtitle, fontsize=7.7, color=GRAY, va="top")


def footer(fig, text, y=.023):
    fig.text(.04, y, text, fontsize=6.8, color=GRAY, va="bottom")


def fold_legend(fig, y=.075):
    handles = [Line2D([0], [0], color=FC[k], marker=MARK[k], ls="none", markersize=4,
                      label=f"Fold {k + 1}") for k in range(5)]
    fig.legend(handles=handles, loc="lower left", bbox_to_anchor=(.25, y), ncol=5, fontsize=6.7)


def calibration_labels(fig, ax, bins):
    """Move annotation text only; keep every plotted score/frequency unchanged."""
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    boundary = ax.get_window_extent(renderer)
    occupied = []
    marker_boxes = []
    marker_pad = 3.4 * fig.dpi / 72
    for row in bins.itertuples():
        x, y = ax.transData.transform((row.MeanOOFScore, row.ObservedHighFraction))
        marker_boxes.append(matplotlib.transforms.Bbox.from_bounds(x - marker_pad, y - marker_pad,
                                                                   2 * marker_pad, 2 * marker_pad))
    for row in bins.sort_values("MeanOOFScore").itertuples():
        first = (5, -12, "left") if row.ObservedHighFraction > .8 else (5, 6, "left")
        candidates = [first, (-5, 6, "right"), (-5, -12, "right"), (5, 6, "left"),
                      (5, -12, "left"), (5, 19, "left"), (-5, 19, "right"),
                      (5, -26, "left"), (-5, -26, "right"),
                      (5, 32, "left"), (-5, 32, "right"),
                      (5, -40, "left"), (-5, -40, "right")]
        label = ax.annotate(f"{row.NRecords}/{row.NSpecies}",
                            (row.MeanOOFScore, row.ObservedHighFraction),
                            xytext=first[:2], textcoords="offset points", fontsize=6)
        for dx, dy, align in candidates:
            label.set_position((dx, dy))
            label.set_ha(align)
            box = label.get_window_extent(renderer).expanded(1.08, 1.25)
            inside = box.x0 >= boundary.x0 and box.x1 <= boundary.x1 and box.y0 >= boundary.y0 and box.y1 <= boundary.y1
            if inside and not any(box.overlaps(other) for other in occupied + marker_boxes):
                occupied.append(box)
                break
        else:
            raise ValueError("Calibration label collision remains; manual layout repair required")


def save(fig, stem, d, caption, *, pdf=None, pdf_name=None, estimand="", interval="", status="READY"):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    outside = []
    for t in fig.findobj(match=matplotlib.text.Text):
        if not t.get_visible() or not t.get_text() or t.get_clip_on():
            continue
        box = t.get_window_extent(renderer)
        if box.width and box.height and (box.x0 < -1 or box.y0 < -1 or box.x1 > fig.bbox.width + 1 or box.y1 > fig.bbox.height + 1):
            outside.append(t.get_text())
    TEXT_QA.append({"FigureID": stem, "OutsideCanvasText": outside})
    src = source(stem, d)
    if pdf is None:
        pdf_name = f"{stem}.pdf"
        fig.savefig(FIG / pdf_name)
    else:
        pdf.savefig(fig)
    fig.savefig(FIG / f"{stem}.svg")
    fig.savefig(FIG / f"{stem}.png", dpi=600)
    fig.savefig(FIG / f"{stem}_preview.png", dpi=150)
    provenance_path = FIG / f"{stem}_provenance.json"
    provenance_path.write_text(json.dumps({
        "FigureID": stem, "Group": CURRENT_GROUP, "Scope": CURRENT_SCOPE,
        "plot_script_sha256": PLOT_SCRIPT_SHA256,
        "source_files_at_generation": dict(CURRENT_INPUTS),
        "figure_source_csv": {"Path": src, "SHA256": sha(BASE / src)},
        "PNG_SHA256": sha(FIG / f"{stem}.png"),
        "SVG_SHA256": sha(FIG / f"{stem}.svg"),
        "canvas_check": TEXT_QA[-1],
        "Estimand": estimand, "Interval": interval, "ScientificStatus": status,
        "new_fits_started": False, "simulated_data_created_by_plotter": False,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    FILES.append({"FigureID": stem, "Group": CURRENT_GROUP, "Scope": CURRENT_SCOPE,
        "PDF": pdf_name, "SVG": f"{stem}.svg", "PNG": f"{stem}.png",
        "Preview": f"{stem}_preview.png", "SourceCSV": src, "WidthMM": fig.get_figwidth() * 25.4,
        "HeightMM": fig.get_figheight() * 25.4, "Estimand": estimand, "Interval": interval,
        "ScientificStatus": status, "VisualReview": "PENDING",
        "SourceManifest": str(provenance_path.relative_to(BASE))})
    CAPTIONS.append((stem, caption))
    plt.close(fig)
    print(f"SAVED {stem}", flush=True)


def rows_numeric(d, fields, *, join_id="RecordID"):
    numeric_ok(d, fields)
    if join_id and d[join_id].duplicated().any():
        raise ValueError(f"Repeated {join_id}")


def coefficients(out):
    d = primary_table(f"parameter_summary_{out}_primary.csv", ["Model", "OriginalTerm", "mean", "Lower95", "Upper95", "RankDeficientModel"])
    tm = read(BASE / "provenance" / "blueprint_term_map.csv", ["Outcome", "Group", "OriginalTerm", "ReferenceLevel", "IdentifiableDirection"])
    tm = tm[tm.Outcome.eq(out)].drop_duplicates(["Group", "OriginalTerm"])
    bet = d[d.OriginalTerm.str.match(r"^(M[123]|M1)_Site")].copy()
    bet["Group"] = bet.Model.str.extract(r"^(M[123])", expand=False).fillna("Site315")
    bet = bet.merge(tm, on=["Group", "OriginalTerm"], how="left", suffixes=("", "_map"), validate="many_to_one")
    if bet.ReferenceLevel.isna().any():
        raise Pending("Coefficient reference-level mapping is incomplete")
    if CHECK_ONLY:
        return
    for group in ["M1", "M2", "M3"]:
        z = bet[bet.Group.eq(group) & bet.Model.isin([f"{group}_U", f"{group}_P"])].copy()
        terms = list(z.OriginalTerm.drop_duplicates())
        if not terms:
            raise Pending(f"No coefficient rows: {out}/{group}")
        numeric_ok(z, ["mean", "Lower95", "Upper95"])
        fig, ax = plt.subplots(figsize=(205 / 25.4, max(130, 8 * len(terms) + 75) / 25.4))
        fig.subplots_adjust(left=.40, right=.96, bottom=.13, top=.80)
        y = np.arange(len(terms))
        for model, dy, color, mark in [(f"{group}_U", -.13, BLUE, "o"), (f"{group}_P", .13, ORANGE, "s")]:
            q = z[z.Model.eq(model)].set_index("OriginalTerm").reindex(terms)
            if q["mean"].isna().any():
                raise ValueError("U/P coefficient terms differ")
            ax.hlines(y + dy, q.Lower95, q.Upper95, color=color, lw=1)
            ax.scatter(q["mean"], y + dy, s=22, color=color, marker=mark, label=model, zorder=3)
        lab = []
        for term in terms:
            r = z[z.OriginalTerm.eq(term)].iloc[0]
            label = re.sub(r"^M[123]_Site(\d+)", r"Site \1: ", term).replace("_validated", " (reference)")
            caution = " [prior dependent]" if not bools(pd.Series([r.IdentifiableDirection])).iloc[0] else ""
            lab.append(f"{label}{caution}\nvs {r.ReferenceLevel}")
        ax.set_yticks(y, lab, fontsize=7)
        ax.invert_yaxis()
        ax.axvline(0, color=GRAY, ls="--", lw=.7)
        ax.set_xlabel("Coefficient on logit scale (posterior mean)")
        ax.legend(loc="lower right")
        rank = bools(z.RankDeficientModel).any()
        subtitle = "95% posterior intervals; association conditional on the frozen design"
        if rank:
            subtitle += "\nRANK DEFICIENT: individual coefficients may be prior dependent"
        header(fig, f"{out}: {group} coefficient estimates", subtitle)
        footer(fig, "These are model associations, not isolated mutational or causal effects.")
        cap = (f"{out}路线{group}固定效应，圆点/方点为U/P模型的后验均值，线段为2.5%–97.5%后验分位区间。"
               "基准水平和单方向可估性直接来自本次R设计矩阵的blueprint_term_map，不由Python猜测。binary系数作用于HIGH概率的logit；joint系数作用于整体期望比率m的logit。"
               "秩不足模型保留明确标记，单独系数不能解释为被数据独立识别的位点作用。图不构成因果突变效应证据。")
        save(fig, f"F05_coefficients_{out}_{group}", z, cap, estimand=f"{out} fixed-effect logit coefficient posterior mean",
             interval="95% posterior interval", status="PRIOR_DEPENDENCE_CAUTION" if rank else "READY")


def diagnostic_plot(d, stem, title, subtitle):
    names = ["MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI"]
    fig, axs = plt.subplots(2, 3, figsize=(225 / 25.4, 205 / 25.4))
    fig.subplots_adjust(left=.10, right=.97, bottom=.22, top=.79, wspace=.32, hspace=1.02)
    labels = list(d.DisplayLabel)
    xx = np.arange(len(d))
    for ax, col, threshold, direction in zip(axs.flat, names, [1.01, 400, 400, 0, 0, .3], ["less", "more", "more", "equal", "equal", "more"]):
        values = pd.to_numeric(d[col])
        ax.scatter(xx, values, marker="o", s=17, color=[BLUE if x == "PASS" else ORANGE for x in d.Status])
        ax.axhline(threshold, color=ORANGE, ls="--", lw=.8)
        ax.set_title(col, loc="left")
        ax.set_xticks(xx, labels, rotation=70, ha="right", fontsize=6.4)
        if col in ["MinBulkESS", "MinTailESS"] and values.min() > 0:
            ax.set_yscale("log")
        if col in ["Divergences", "TreeDepthHits"]:
            ax.set_ylim(-.05, max(1., float(values.max()) * 1.15))
            ax.yaxis.set_major_locator(MaxNLocator(integer=True, nbins=3))
        ax.grid(axis="y", color=GRID, lw=.45)
    header(fig, title, subtitle)
    footer(fig, "Numerical sampling checks do not establish model adequacy, identifiability or predictive validity.")
    save(fig, stem, d, "抽样诊断图；各点为该拟合的参数集合或采样链诊断摘要。Rhat、bulk/tail ESS、发散、树深度命中及EBFMI分别显示。"
         "阈值来自本次设置；PASS只表示相应数值检查通过，不说明模型充分、M3可辨识或预测准确。未通过记录保留并标色。", estimand="Numerical diagnostic summaries")


def diagnostics(out):
    d = primary_table(f"diagnostics_{out}_primary.csv", ["Model", "Status", "MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI"])
    settings = register_input(BASE / "manual" / "00_开始与使用顺序.md").read_text(encoding="utf-8")
    if not re.search(r"MAX_RHAT\s*<-\s*1[.]01", settings) or not re.search(r"MIN_ESS\s*<-\s*400", settings):
        raise ValueError("Diagnostic threshold literals differ; plot must read the new settings")
    if CHECK_ONLY:
        return
    d = d.set_index("Model").loc[MODELS].reset_index()
    d["DisplayLabel"] = d.Model
    diagnostic_plot(d, f"S05_diagnostics_{out}_primary", f"{out}: primary sampling diagnostics", "All ten selected primary fits; dashed lines are numerical screening thresholds")


def cv_diagnostics(out, cvtype):
    d = read(DER / "cv_comparisons" / f"{out}_{cvtype}" / "cv_fold_diagnostics.csv",
             ["Outcome", "CVType", "Model", "CVKey", "ParentKey", "Fold", "Status", "MaxRhat", "MinBulkESS", "MinTailESS", "Divergences", "TreeDepthHits", "MinEBFMI"])
    chosen = read(BASE / "provenance" / "selected_cv_manifest.csv", ["Outcome", "CVType", "Model", "CVKey", "ParentKey"])
    chosen = chosen[(chosen.Outcome == out) & (chosen.CVType == cvtype)]
    if set(chosen.Model) != set(MODELS) or set(d.Model) != set(MODELS):
        raise Pending("CV diagnostics need the complete ten-model selection")
    if not d.Outcome.eq(out).all() or not d.CVType.eq(cvtype).all() or d.duplicated(["Model", "Fold"]).any():
        raise ValueError("CV diagnostic group identity invalid")
    for model in MODELS:
        z = d[d.Model.eq(model)]
        row = chosen[chosen.Model.eq(model)].iloc[0]
        if set(z.Fold) != {1, 2, 3, 4, 5} or not z.CVKey.eq(row.CVKey).all() or not z.ParentKey.eq(row.ParentKey).all():
            raise ValueError("CV diagnostic values do not belong to the selected model/folds")
    if CHECK_ONLY:
        return
    for fold in range(1, 6):
        part = d[d.Fold.eq(fold)].set_index("Model").loc[MODELS].reset_index()
        part["DisplayLabel"] = part.Model
        diagnostic_plot(part, f"S05_cv_diagnostics_{out}_{cvtype}_fold{fold}",
                        f"CV diagnostics: {out} / {cvtype} / fold {fold}",
                        "Selected heldout refits, with explicit CV and parent-fit identity")


def pareto(out):
    d = primary_table(f"loo_source_means_{out}_primary.csv", ["Model", "RecordID", "ParetoK"])
    status = primary_table(f"loo_status_{out}_primary.csv", ["Model", "KLimit", "Status", "ProblemRows"])
    if set(status.Model) != set(MODELS):
        raise Pending("Incomplete Pareto-k status table")
    if CHECK_ONLY:
        return
    fig, axs = plt.subplots(5, 2, figsize=(210 / 25.4, 260 / 25.4))
    fig.subplots_adjust(left=.09, right=.97, top=.84, bottom=.085, hspace=.64, wspace=.28)
    all_k = pd.to_numeric(d.ParetoK, errors="coerce").to_numpy(float)
    finite_k = all_k[np.isfinite(all_k)]
    bounds = np.r_[finite_k, status.KLimit.to_numpy(float), 0.]
    k_pad = max(.05, float(np.ptp(bounds)) * .05)
    shared_ylim = (float(bounds.min()) - k_pad, float(bounds.max()) + k_pad)
    for ax, model in zip(axs.flat, MODELS):
        q = d[d.Model.eq(model)].copy()
        k = pd.to_numeric(q.ParetoK, errors="coerce")
        lim = float(status.loc[status.Model.eq(model), "KLimit"].iloc[0])
        finite = np.isfinite(k)
        ax.scatter(np.arange(len(k))[finite], k[finite], s=8, c=np.where(k[finite] > lim, ORANGE, BLUE))
        ax.axhline(lim, color=ORANGE, lw=.7, ls="--")
        ax.set_title(f"{model} | {int(status.loc[status.Model.eq(model), 'ProblemRows'].iloc[0])} flagged", loc="left", fontsize=8)
        ax.set_ylabel("Pareto k")
        ax.set_ylim(*shared_ylim)
        if (~finite).any():
            ax.text(.02, .88, f"{int((~finite).sum())} nonfinite k (flagged)", transform=ax.transAxes, fontsize=6.5, color=ORANGE)
    header(fig, f"{out}: PSIS importance-sampling diagnostics", "Shared k scale; unreliable PSIS values are diagnostic findings, not a model ranking")
    footer(fig, "Horizontal index follows the recorded likelihood rows; prediction evaluation uses actual grouped holdout fits.")
    save(fig, f"S06_pareto_k_{out}", d.merge(status[["Model", "KLimit", "Status"]], on="Model"),
         "逐模型PSIS Pareto-k诊断；同一路线的十面板使用相同k轴范围。binary的似然行是物种汇总分类行，joint是原始记录，两个横轴对象不同。非有限k另行标明。"
         "出现不可靠PSIS时只保留诊断，不由这些权重绘制最佳模型排名或验证预测；正式预测评价来自真正分组留出。", estimand="PSIS diagnostic k", status="USE_GROUPED_CV")


def ppc(out):
    observed = primary_table("ppc_observed_plot_data_primary.csv", ["Outcome", "Model", "Subset", "RecordID", "Observed"])
    stats = primary_table("ppc_statistic_plot_data_primary.csv", ["Outcome", "Model", "Subset", "Replicate", "Mean", "SD", "ZeroFraction", "OneFraction"])
    observed, stats = observed[observed.Outcome.eq(out)], stats[stats.Outcome.eq(out)]
    if set(observed.Model) != set(MODELS) or set(stats.Model) != set(MODELS):
        raise Pending("PPC export does not cover all ten models")
    if CHECK_ONLY:
        return
    pdfname = f"S07_ppc_statistics_{out}.pdf"
    with PdfPages(FIG / pdfname) as pdf:
        for model in MODELS:
            for subset in observed.loc[observed.Model.eq(model), "Subset"].unique():
                o = observed[(observed.Model == model) & (observed.Subset == subset)].copy()
                s = stats[(stats.Model == model) & (stats.Subset == subset)].copy()
                yy = o.Observed.to_numpy(float)
                actual = [yy.mean(), yy.std(ddof=1), (yy == 0).mean(), (yy == 1).mean()]
                fig, axs = plt.subplots(2, 2, figsize=(180 / 25.4, 145 / 25.4))
                fig.subplots_adjust(left=.11, right=.96, bottom=.12, top=.78, hspace=.58, wspace=.31)
                for ax, col, val in zip(axs.flat, ["Mean", "SD", "ZeroFraction", "OneFraction"], actual):
                    values = s[col].dropna().to_numpy(float)
                    if len(np.unique(values)) == 1:
                        ax.vlines(values[0], 0, len(values), color=BLUE, lw=3)
                        ax.text(.04, .86, f"All {len(values)} replicates = {values[0]:.3g}", transform=ax.transAxes, fontsize=6.6)
                        if col in ["Mean", "ZeroFraction", "OneFraction"]:
                            ax.set_xlim(-.02, 1.02)
                    else:
                        ax.hist(values, bins=25, color="#C5DDEB", edgecolor=BLUE, lw=.4)
                    ax.axvline(val, color=ORANGE, lw=1.6, label="Observed")
                    ax.set_title(col, loc="left")
                    ax.set_ylabel("Replicates")
                    ax.set_xlabel("Statistic")
                    ax.legend(fontsize=6.5)
                if out == "binary":
                    replication_note = f"{len(o)} species rows; replicated High counts retain each species' Trials"
                elif subset == "count":
                    replication_note = f"{len(o)} count records; replicated Events retain each record's Total"
                else:
                    replication_note = f"{len(o)} exact records; replicated outcomes include the model's mass at 1"
                header(fig, f"PPC: {out} / {model} / {subset}", replication_note)
                footer(fig, "In-sample posterior predictive check; this is not held-out validation.")
                both = pd.concat([s.assign(RowType="replicated_statistic"), o.assign(RowType="observed")], ignore_index=True)
                weight_note = (f"binary PPC以{len(o)}个物种为显示和统计单位：先计算各物种HighCount/Trials，Mean再对物种等权取算术均值；"
                               "SD、ZeroFraction和OneFraction也在这些物种比例上计算。Mean不是合并所有实验记录后的总体HIGH比例，"
                               "不能与实验记录等权的AUC/校准或总体HIGH率混为同一权重目标。" if out == "binary" else "")
                save(fig, f"S07_ppc_{out}_{model}_{subset}", both,
                     weight_note + "训练内后验预测检查。直方图为既有04模拟数据的均值、标准差、0及1比例，竖线为原始观测统计量。"
                     "保留计数记录的Total及分类记录的Trials；joint的count和exact分别检查。它不属于独立留出验证，统计均值接近也不能单独证明模型充分。",
                     pdf=pdf, pdf_name=pdfname, estimand="In-sample posterior predictive statistics")


def ppc_ecdf(out):
    primary_gate()
    d = read(find_named("ppc_ecdf_plot_data_primary.csv"), ["Outcome", "Model", "Subset", "Replicate", "X", "ECDF"])
    o = primary_table("ppc_observed_plot_data_primary.csv", ["Outcome", "Model", "Subset", "Observed"])
    d, o = d[d.Outcome.eq(out)], o[o.Outcome.eq(out)]
    if set(d.Model) != set(MODELS):
        raise Pending("ECDF export does not include all models")
    if CHECK_ONLY:
        return
    pdfname = f"S07_ppc_ecdf_{out}.pdf"
    with PdfPages(FIG / pdfname) as pdf:
        for model in MODELS:
            fig, axs = plt.subplots(1, len(d.loc[d.Model.eq(model), "Subset"].unique()), figsize=(180 / 25.4, 105 / 25.4), squeeze=False)
            fig.subplots_adjust(left=.11, right=.96, bottom=.18, top=.72, wspace=.31)
            q = d[d.Model.eq(model)]
            for ax, subset in zip(axs.flat, q.Subset.unique()):
                z = q[q.Subset.eq(subset)]
                for _, rep in z[z.Replicate.gt(0)].groupby("Replicate", sort=True):
                    rep = rep.sort_values(["X", "ECDF"])
                    ax.step(rep.X, rep.ECDF, where="post", color="#83AEC8", alpha=.25, lw=.55)
                yy = np.sort(o[(o.Model == model) & (o.Subset == subset)].Observed.to_numpy(float))
                ax.step(np.r_[0, yy, 1], np.r_[0, np.arange(1, len(yy) + 1) / len(yy), 1], where="post", color=ORANGE, lw=1.5)
                ax.set(xlim=(0, 1), ylim=(0, 1), xlabel="Outcome", ylabel="Cumulative fraction", title=subset)
            header(fig, f"PPC distribution: {out} / {model}", "Orange: observed; thin blue: fixed exported posterior predictive replicates")
            footer(fig, "In-sample distribution check. Interval records are evaluated separately as interval events.")
            save(fig, f"S07_ppc_ecdf_{out}_{model}", q, "训练内经验累积分布检查，橙线为观测，蓝线为固定选出的后验预测重复。未平滑或改写原值，区间记录不伪造点值。此图不代表外部验证。", pdf=pdf, pdf_name=pdfname, estimand="In-sample outcome distribution")


def cv_elpd(out, cvtype):
    folder, foldkey = cv_directory(out, cvtype)
    d = read(folder / "cv_model_comparison.csv", ["Model", "ELPD", "ELPD_Difference", "PairedSE"])
    mc = all_extensions(out, cvtype, "cv_fold_scores_mc.csv", ["Fold", "ELPD", "MCReviewStatus"])
    if set(d.Model) != set(MODELS):
        raise Pending("ELPD comparison requires the complete ten-model cohort")
    numeric_ok(d, ["ELPD", "ELPD_Difference", "PairedSE"])
    best = str(d.loc[d.ELPD.idxmax(), "Model"])
    totals = mc.groupby("Model").ELPD.sum()
    if not np.allclose(d.ELPD, d.Model.map(totals), atol=1e-7, rtol=0):
        raise ValueError("ELPD comparison differs from selected extension score totals")
    if not np.allclose(d.ELPD_Difference, d.ELPD - float(d.ELPD.max()), atol=1e-7, rtol=0):
        raise ValueError("ELPD differences use an unexpected numerical reference")
    score_matrix = mc.pivot(index="Fold", columns="Model", values="ELPD").reindex(columns=MODELS)
    paired = score_matrix.subtract(score_matrix[best], axis=0)
    expected_se = np.sqrt(len(score_matrix) * paired.var(axis=0, ddof=1))
    if not np.allclose(d.PairedSE, d.Model.map(expected_se), atol=1e-7, rtol=0):
        raise ValueError("ELPD whiskers are not the paired fold-difference SE")
    flags = mc.assign(Flag=mc.MCReviewStatus.ne("NO_SCREEN_FLAG")).groupby("Model").Flag.any()
    d["ReferenceModel"] = best
    d["OwnMCReviewRequired"] = d.Model.map(flags)
    d["ReferenceMCReviewRequired"] = bool(flags[best])
    d["ReviewRequired"] = d.OwnMCReviewRequired | d.ReferenceMCReviewRequired
    d["Outcome"], d["CVType"], d["FoldKey"] = out, cvtype, foldkey
    if CHECK_ONLY:
        return
    d = d.set_index("Model").loc[MODELS].reset_index()
    fig, ax = plt.subplots(figsize=(200 / 25.4, 140 / 25.4))
    fig.subplots_adjust(left=.25, right=.96, bottom=.14, top=.77)
    yy = np.arange(len(d))
    for i, row in enumerate(d.itertuples()):
        color = ORANGE if row.ReviewRequired else BLUE
        ax.hlines(i, row.ELPD_Difference - row.PairedSE, row.ELPD_Difference + row.PairedSE, color=color, lw=1)
        ax.scatter(row.ELPD_Difference, i, s=30, facecolors="white" if row.ReviewRequired else color, edgecolors=color, zorder=3)
    ax.set_yticks(yy, [m + (" *" if f else "") for m, f in zip(d.Model, d.ReviewRequired)])
    ax.invert_yaxis()
    ax.axvline(0, ls="--", color=GRAY, lw=.7)
    ax.set_xlabel("Whole-fold joint ELPD difference (whisker: +/- 1 paired SE)")
    header(fig, f"{out}: grouped holdout ELPD / {cvtype}", f"Plotting zero: {best}; numerical maximum is not proof of a uniquely best model")
    footer(fig, "* REVIEW_REQUIRED: model or reference has an MC stability flag. Paired SE does not include integration MC error.")
    save(fig, f"F02_elpd_{out}_{cvtype}", d, "真实分组留出的整折联合ELPD差值。参照仅为当前数值总分最高者，没有固定Site315；模型按预定顺序展示。"
         "线段是差值±1折间配对SE，不是95%区间，也不包含后验积分Monte Carlo误差。模型自身或参照模型任意一折触发MC检查时用空心橙点及星号标ReviewRequired。"
         "这些数值可以帮助检查表现差异，但在积分不稳定时不能据此声明唯一最佳模型。两路线/两种CV设计分开解释。",
         estimand="Whole-fold joint heldout log predictive score difference", interval="+/-1 paired SE, excluding MC integration error",
         status="REVIEW_REQUIRED" if d.ReviewRequired.any() else "NO_MC_SCREEN_FLAG")


def cv_mc(out, cvtype):
    d = all_extensions(out, cvtype, "cv_fold_scores_mc.csv", ["Fold", "DeltaMethod_MCSE_LogPredictive", "MaxNormalizedContribution", "EffectiveContributionCount", "ChainLogPredictiveRange", "MCReviewStatus"])
    if CHECK_ONLY:
        return
    fig, axs = plt.subplots(2, 2, figsize=(210 / 25.4, 195 / 25.4))
    fig.subplots_adjust(left=.23, right=.96, bottom=.10, top=.80, hspace=.55, wspace=.65)
    fields = [("DeltaMethod_MCSE_LogPredictive", "Log-score MCSE (delta method)"), ("MaxNormalizedContribution", "Largest normalized contribution"),
              ("EffectiveContributionCount", "Effective contribution count"), ("ChainLogPredictiveRange", "Between-chain score range")]
    for ax, (field, title) in zip(axs.flat, fields):
        v = d.pivot(index="Model", columns="Fold", values=field).reindex(MODELS)
        a = v.to_numpy(float)
        finite = np.isfinite(a)
        if field == "EffectiveContributionCount":
            display = np.log10(np.maximum(a, 1))
            unit = "log10"
        else:
            display, unit = a, ""
        im = ax.imshow(np.ma.masked_invalid(display), cmap="YlOrBr", aspect="auto", interpolation="nearest")
        for i, j in zip(*np.where(~finite)):
            ax.text(j, i, "NA", ha="center", va="center", fontsize=6)
        for i, m in enumerate(MODELS):
            for j, fold in enumerate(v.columns):
                flag = d[(d.Model == m) & (d.Fold == fold)].MCReviewStatus.iloc[0] != "NO_SCREEN_FLAG"
                if flag:
                    rgba = np.array(im.cmap(im.norm(display[i, j])))[:3]
                    linear = np.where(rgba <= .04045, rgba / 12.92, ((rgba + .055) / 1.055) ** 2.4)
                    luminance = float(linear @ np.array([.2126, .7152, .0722]))
                    mark_color = "white" if luminance < .22 else INK
                    ax.text(j, i, "*", ha="center", va="center", color=mark_color, fontsize=8.5, weight="bold")
        ax.set_yticks(range(10), MODELS, fontsize=6.6)
        ax.set_xticks(range(len(v.columns)), [f"F{k}" for k in v.columns])
        ax.set_title(title, loc="left", fontsize=8)
        cb = fig.colorbar(im, ax=ax, fraction=.044, pad=.03)
        cb.ax.tick_params(labelsize=6)
        if unit:
            cb.set_label(unit, fontsize=6)
    header(fig, f"{out}: whole-fold score integration / {cvtype}", "Asterisks mark predeclared MC review screens; no flag is not a proof of exact ranking")
    footer(fig, "Effective contributions are likelihood-integration diagnostics, not posterior parameter ESS.")
    save(fig, f"S06_mc_score_{out}_{cvtype}", d, "每模型每折的整折预测概率积分检查。四面板分别显示对数分数MCSE近似、最大归一化似然贡献、有效贡献数量和链间对数分数范围。"
         "有效贡献数量用log10色标，不能误称参数ESS；星号为既定描述性复核触发条件，并非显著性检验。MCSE在相对误差大时本身也可能不可靠。", estimand="Monte Carlo score integration diagnostics", status="REVIEW_REQUIRED" if d.MCReviewStatus.ne("NO_SCREEN_FLAG").any() else "NO_MC_SCREEN_FLAG")


def auc_tables(cvtype):
    preferred = DER / "cv_comparisons" / f"binary_{cvtype}" / "roc_oof_experiments.csv"
    candidates = [preferred] if preferred.exists() else []
    for root in ([] if candidates else [RES, DER]):
        if root.exists():
            for p in root.rglob("roc_oof_experiments.csv"):
                frame = read(p, ["Model", "RecordID", "Species", "High", "OOFPrHigh", "Fold"])
                if "CVType" in frame and frame.CVType.astype(str).eq(cvtype).all():
                    candidates.append(p)
                elif cvtype in str(p.relative_to(BASE)).replace("\\", "/").split("/") or f"binary_{cvtype}_" in str(p):
                    candidates.append(p)
    if len(candidates) != 1:
        raise Pending(f"Need one identity-labelled ROC/AUC output directory for {cvtype}; found {len(candidates)}")
    folder = candidates[0].parent
    rows = read(candidates[0], ["Model", "RecordID", "Species", "High", "OOFPrHigh", "Fold", "LevelSeenInTraining", "FixedEffectEstimable"])
    summary = read(folder / "auc_summary.csv", ["Model", "CV_AUC", "Status"])
    folds = read(folder / "auc_by_fold.csv", ["Model", "Fold", "AUC", "Status", "High", "Low"])
    coord = read(folder / "roc_coordinates_by_fold.csv", ["Model", "Fold", "FPR", "TPR"])
    if set(rows.Model) != set(MODELS) or set(summary.Model) != set(MODELS):
        raise Pending("ROC output requires all ten models")
    if rows.duplicated(["Model", "RecordID"]).any():
        raise ValueError("Repeated OOF experimental predictions")
    numeric_ok(rows, ["OOFPrHigh", "High"], probability=True)
    directory, _ = cv_directory("binary", cvtype)
    allocation = read(directory / "folds.csv", ["Species", "Fold"])
    mapping = allocation.set_index("Species").Fold
    if not np.array_equal(rows.Fold.to_numpy(), rows.Species.map(mapping).to_numpy()):
        raise ValueError("ROC predictions do not match the actual heldout-species allocation")
    for model in MODELS:
        f = folds[folds.Model.eq(model)]
        if set(f.Fold) != set(allocation.Fold):
            raise ValueError("AUC fold coverage incomplete")
        valid = f.High.gt(0) & f.Low.gt(0)
        reported = summary.loc[summary.Model.eq(model), "CV_AUC"].iloc[0]
        if valid.all():
            if not np.isclose(reported, f.AUC.mean(), atol=1e-10):
                raise ValueError("CV_AUC is not the mean of all fold AUCs")
        elif pd.notna(reported):
            raise ValueError("CV_AUC must remain NA when a fold has one class")
    return rows, summary, folds, coord


def roc_calibration(cvtype):
    rows, summary, folds, coordinates = auc_tables(cvtype)
    if CHECK_ONLY:
        return
    pdfname = f"F03_roc_calibration_{cvtype}.pdf"
    bins_all = []
    with PdfPages(FIG / pdfname) as pdf:
        for model in MODELS:
            q = rows[rows.Model.eq(model)].copy()
            summary_row = summary[summary.Model.eq(model)].iloc[0]
            f = folds[folds.Model.eq(model)]
            fig, axs = plt.subplots(2, 2, figsize=(205 / 25.4, 190 / 25.4))
            fig.subplots_adjust(left=.10, right=.96, bottom=.115, top=.79, hspace=.49, wspace=.35)
            rocax, calax, distax, speciesax = axs.flat
            for k in sorted(f.Fold):
                r = f[f.Fold.eq(k)].iloc[0]
                c = coordinates[(coordinates.Model == model) & (coordinates.Fold == k)]
                label = f"Fold {int(k)}: {r.AUC:.3f}" if pd.notna(r.AUC) else f"Fold {int(k)}: one class"
                if len(c):
                    rocax.plot(c.FPR, c.TPR, color=FC[int(k) - 1], ls=["-", "--", "-.", ":", "-"][int(k) - 1], lw=1.2, label=label)
                else:
                    rocax.plot([], [], color=FC[int(k) - 1], label=label)
            rocax.plot([0, 1], [0, 1], color=GRAY, ls="--", lw=.7)
            rocax.set(xlim=(0, 1), ylim=(0, 1), xlabel="False positive rate", ylabel="True positive rate", title="A  Fold-specific ROC")
            rocax.legend(fontsize=6.0, loc="lower right")
            q["Bin"] = np.minimum((q.OOFPrHigh * 5).astype(int), 4)
            binrows = []
            for b in range(5):
                z = q[q.Bin.eq(b)]
                binrows.append({"Model": model, "CVType": cvtype, "Bin": b + 1, "BinLower": b / 5, "BinUpper": (b + 1) / 5,
                    "RightClosed": b == 4, "NRecords": len(z), "NSpecies": z.Species.nunique(),
                    "MeanOOFScore": z.OOFPrHigh.mean() if len(z) else np.nan,
                    "ObservedHighFraction": z.High.mean() if len(z) else np.nan})
            bin_df = pd.DataFrame(binrows)
            bins_all.append(bin_df)
            ok = bin_df.NRecords.gt(0)
            calax.plot([0, 1], [0, 1], color=GRAY, ls="--", lw=.7)
            calax.scatter(bin_df.loc[ok, "MeanOOFScore"], bin_df.loc[ok, "ObservedHighFraction"], s=34, color=BLUE)
            calax.set(xlim=(-.025, 1.025), ylim=(-.025, 1.025),
                      xlabel="Mean OOF score in fixed bin\nLabels: records/species; no naive CI",
                      ylabel="Observed HIGH fraction", title="B  Descriptive calibration")
            calibration_labels(fig, calax, bin_df[ok])
            distax.hist([q[q.High.eq(0)].OOFPrHigh, q[q.High.eq(1)].OOFPrHigh], bins=np.linspace(0, 1, 11), label=["LOW", "HIGH"], color=[ORANGE, BLUE], stacked=True, edgecolor="white", lw=.4)
            distax.set(xlim=(0, 1), xlabel="OOF HIGH probability score", ylabel="Experimental records", title="C  Score distribution")
            distax.legend(fontsize=6.5)
            sp = q.groupby(["Species", "Fold"], as_index=False).agg(OOFPrHigh=("OOFPrHigh", "first"), HighFraction=("High", "mean"), Trials=("High", "size"))
            for k, z in sp.groupby("Fold"):
                speciesax.scatter(z.OOFPrHigh, z.HighFraction, s=12 + z.Trials * 3, marker=MARK[int(k) - 1], color=FC[int(k) - 1], alpha=.8)
            speciesax.plot([0, 1], [0, 1], color=GRAY, ls="--", lw=.7)
            speciesax.set(xlim=(-.03, 1.03), ylim=(-.03, 1.03), xlabel="OOF HIGH probability score", ylabel="Species HIGH / Trials", title="D  Species-level display")
            auc_text = f"mean fold CV_AUC = {summary_row.CV_AUC:.3f}" if pd.notna(summary_row.CV_AUC) else "CV_AUC undefined: at least one fold has one class"
            unseen_count = int((~bools(q.LevelSeenInTraining)).sum())
            nonestimable_count = int((~bools(q.FixedEffectEstimable)).sum())
            auc_text += f"\nTraining-unseen levels: {unseen_count} records; nonestimable directions: {nonestimable_count} records"
            header(fig, f"High/Low validation: {model} / {cvtype}", auc_text)
            footer(fig, "All curves and points use genuine species-held-out fits. Different folds are not one joint posterior.")
            combined = pd.concat([q.assign(RowType="OOF_experiment"), bin_df.assign(RowType="calibration_bin"), f.assign(RowType="fold_auc")], ignore_index=True)
            save(fig, f"F03_roc_calibration_{cvtype}_{model}", combined,
                 "A为每折独立ROC，使用真实物种留出预测，方向固定为高分更倾向HIGH，折平均CV_AUC仅在所有折均含两类时定义，不拼接跨折ROC代替。"
                 "B为固定五箱[0,.2)、[.2,.4)、[.4,.6)、[.6,.8)、[.8,1]的实验等权描述性校准，标注记录/物种数，不对同物种重复记录套独立样本置信区间，空箱不连线。"
                 "C保留原HIGH/LOW标签的分数分布；D每物种一点、点面积随Trials增加。概率得分按原06A为后验中位数，与定量MAE的后验均值定义不同。"
                 "未见水平或不可估方向记录继续参与评价，源CSV保留逐条标记，副标题显示两类标记的记录数；两类标记可重叠，不能相加当独立样本量。", pdf=pdf, pdf_name=pdfname,
                 estimand="OOF discrimination and descriptive probability calibration", interval="No invented AUC or calibration confidence interval",
                 status="AUC_UNDEFINED_ONE_CLASS_FOLD" if pd.isna(summary_row.CV_AUC) else "DEFINED")
    source(f"F03_calibration_bins_{cvtype}", pd.concat(bins_all, ignore_index=True))
    fig, ax = plt.subplots(figsize=(180 / 25.4, 155 / 25.4))
    fig.subplots_adjust(left=.27, right=.95, top=.78, bottom=.25)
    for i, model in enumerate(MODELS):
        z = folds[folds.Model.eq(model)]
        for r in z.itertuples():
            if pd.notna(r.AUC):
                ax.scatter(r.AUC, i + (r.Fold - 3) * .07, color=FC[int(r.Fold) - 1], marker=MARK[int(r.Fold) - 1], s=20)
        cv = summary.loc[summary.Model.eq(model), "CV_AUC"].iloc[0]
        if pd.notna(cv):
            ax.scatter(cv, i, s=55, marker="|", color=INK, zorder=4)
        else:
            ax.text(.02, i, "CV_AUC = NA", va="center", fontsize=7, color=ORANGE)
    ax.set(yticks=np.arange(10), yticklabels=MODELS, xlim=(-.025, 1.025),
           xticks=np.linspace(0, 1, 6), xlabel="Fold AUC; black tick = mean over every fold")
    ax.invert_yaxis()
    ax.axvline(.5, color=GRAY, ls="--", lw=.7)
    fold_legend(fig, y=.087)
    header(fig, f"High/Low AUC by model / {cvtype}", "Fold variation is shown directly; it is not a 95% confidence interval")
    undefined = sorted(folds.loc[folds.AUC.isna(), "Fold"].unique())
    auc_note = "AUC below 0.5 is retained without reversing the prediction direction."
    if undefined:
        auc_note += "\nSingle-class " + ", ".join(f"F{int(k)}" for k in undefined) + ": fold AUC and complete CV_AUC remain NA."
    footer(fig, auc_note, y=.018)
    save(fig, f"F02_auc_summary_{cvtype}", pd.concat([folds.assign(RowType="fold"), summary.assign(RowType="summary")], ignore_index=True),
         "各模型逐折AUC及全部折的算术均值。不同折的点直接显示折间变化，不把范围称为95%CI。含单类别折时完整CV_AUC为NA，仍显示其他已定义折且明确不形成剩余折平均。", estimand="Unweighted mean of all fold AUCs", interval="Fold values, not confidence intervals")


def quantitative(outcome_unused, cvtype):
    data = []
    for model in MODELS:
        p = extension("joint", cvtype, model, "oof_predictive_summary.csv", ["RecordID", "Species", "Type", "OOFMeanPosteriorMean", "OOFMeanLower95", "OOFMeanUpper95", "OOFMeanMedian", "LevelSeenInTraining", "FixedEffectEstimable"])
        i = extension("joint", cvtype, model, "oof_interval_probability.csv", ["RecordID", "Lower", "Upper", "OOFMeanPosteriorMean", "PredictiveEventProbability", "LevelSeenInTraining", "FixedEffectEstimable"])
        rows_numeric(p, ["OOFMeanPosteriorMean", "OOFMeanMedian", "OOFMeanLower95", "OOFMeanUpper95"])
        p["ObservedRatio"] = np.where(p.Type.eq("count"), p.Events / p.Total, p.Exact)
        data.append((model, p, i))
    if CHECK_ONLY:
        return
    pdfname = f"F04_oof_prediction_observation_{cvtype}.pdf"
    with PdfPages(FIG / pdfname) as pdf:
        for model, p, interval in data:
            fig, axs = plt.subplots(1, 2, figsize=(205 / 25.4, 125 / 25.4), gridspec_kw={"width_ratios": [1, 1]})
            fig.subplots_adjust(left=.10, right=.96, top=.75, bottom=.19, wspace=.35)
            ax = axs[0]
            for kind, color, mark in [("count", BLUE, "o"), ("exact", ORANGE, "D")]:
                z = p[p.Type.eq(kind)]
                ax.scatter(z.ObservedRatio * 100, z.OOFMeanPosteriorMean * 100, color=color, marker=mark, s=18, alpha=.75, label=kind)
            for r in interval.itertuples():
                ax.hlines(r.OOFMeanPosteriorMean * 100, r.Lower * 100, r.Upper * 100, color=PURPLE, lw=1.2)
            ax.plot([0, 100], [0, 100], color=GRAY, ls="--", lw=.7)
            ax.set(xlim=(-3, 103), ylim=(-3, 103), xlabel="Observed ratio or interval (%)", ylabel="OOF posterior mean of m (%)", title="A  Point predictions and intervals")
            handles, labels = ax.get_legend_handles_labels()
            handles.append(Line2D([0], [0], color=PURPLE, lw=1.2, label="reported interval"))
            ax.legend(handles=handles, fontsize=6.5)
            z = interval.sort_values("RecordID").copy()
            y = np.arange(len(z))
            axs[1].hlines(y, z.EventProbabilityLower95, z.EventProbabilityUpper95, color=PURPLE, lw=1)
            axs[1].scatter(z.PredictiveEventProbability, y, color=PURPLE, s=25)
            lab = [f"{r.RecordID.replace('XLSX_', '')} [{r.Lower:.2g}, {r.Upper:.2g}]" for r in z.itertuples()]
            axs[1].set(yticks=y, yticklabels=lab, xlim=(-.03, 1.03), xlabel="OOF probability of reported interval", title="B  Interval-event probability")
            axs[1].tick_params(axis="y", labelsize=6.6)
            axs[1].invert_yaxis()
            flags = pd.concat([p, interval], ignore_index=True)
            unseen_count = int((~bools(flags.LevelSeenInTraining)).sum())
            nonestimable_count = int((~bools(flags.FixedEffectEstimable)).sum())
            subtitle = "Main point estimate: posterior mean(m); interval records have no fabricated point value"
            subtitle += f"\nTraining-unseen levels: {unseen_count} records; nonestimable directions: {nonestimable_count} records"
            header(fig, f"Quantitative holdout prediction: {model} / {cvtype}", subtitle)
            footer(fig, "Interval-event probability is affected by interval width and is not the probability that a record is correct.")
            save(fig, f"F04_oof_prediction_{cvtype}_{model}", pd.concat([p, interval], ignore_index=True),
                 "A比较真实留出物种的整体期望比率m后验均值与原观测；count用Events/Total、exact用原具体比率，interval仅显示完整横向范围且无中点。"
                 "本次量化MAE/RMSE主点预测明确采用后验均值，源数据另保留后验中位数。B点为报告区间事件的后验平均概率，线段为该事件概率参数的95%后验区间；不是未来比率预测区间。"
                 "宽区间自然可能获得高概率，不能解释为原数据正确的概率。副标题完整显示训练中未见水平及固定效应不可估方向的记录数，"
                 "两类标记可重叠；所有记录均保留，逐条标记见源CSV。", pdf=pdf, pdf_name=pdfname,
                 estimand="OOF posterior mean of m and interval-event probability", interval="Original observed intervals; event probability posterior interval")


def predictive_bands(cvtype):
    models = ["M1_U", "M1_P"]
    datasets = [extension("joint", cvtype, m, "oof_predictive_summary.csv", ["RecordID", "Species", "PredictiveLower50", "PredictiveUpper50", "PredictiveLower95", "PredictiveUpper95", "OOFMeanPosteriorMean"]) for m in models]
    if CHECK_ONLY:
        return
    for model, data in zip(models, datasets):
        data = data.sort_values("RecordID").copy()
        data["ObservedRatio"] = np.where(data.Type.eq("count"), data.Events / data.Total, data.Exact)
        npage = math.ceil(len(data) / 40)
        pdfname = f"F04_future_predictive_bands_{cvtype}_{model}.pdf"
        with PdfPages(FIG / pdfname) as pdf:
            for page in range(npage):
                d = data.iloc[page * 40:(page + 1) * 40].copy()
                fig, ax = plt.subplots(figsize=(225 / 25.4, 235 / 25.4))
                fig.subplots_adjust(left=.45, right=.95, top=.83, bottom=.12)
                y = np.arange(len(d))
                ax.hlines(y, d.PredictiveLower95 * 100, d.PredictiveUpper95 * 100, color="#A9C8DB", lw=2.1, label="95% future-result interval")
                ax.hlines(y, d.PredictiveLower50 * 100, d.PredictiveUpper50 * 100, color=BLUE, lw=3.6, label="50% future-result interval")
                ax.scatter(d.OOFMeanPosteriorMean * 100, y, color=INK, marker="|", s=28, label="Posterior mean(m)", zorder=4)
                for kind, mark, color in [("count", "o", ORANGE), ("exact", "D", PURPLE)]:
                    sel = d.Type.eq(kind).to_numpy()
                    ax.scatter(d.ObservedRatio.to_numpy()[sel] * 100, y[sel], marker=mark, color=color, s=18, edgecolors="white", lw=.3, zorder=5, label=f"Observed {kind}")
                labels = [f"{r.Species.replace('_', ' ')} | {r.RecordID.replace('XLSX_', '')}" for r in d.itertuples()]
                ax.set_yticks(y, labels, fontsize=6.8)
                ax.invert_yaxis()
                ax.set_xlim(-3, 103)
                ax.set_xlabel("Ratio (%)")
                header(fig, f"Future-result intervals: {model} / {cvtype} | {page + 1}/{npage}", "Held-out count/exact experiments; actual count denominator retained")
                fig.legend(*ax.get_legend_handles_labels(), loc="lower left", bbox_to_anchor=(.04, .04), ncol=3, fontsize=6.5)
                footer(fig, "These are predictive intervals for an experimental result, distinct from posterior uncertainty in its expectation.", y=.017)
                save(fig, f"F04_future_bands_{cvtype}_{model}_p{page + 1:02d}", d,
                     "预先指定主结构M1_U/P的逐条留出未来结果预测带。浅蓝为95%、深蓝为50%后验预测分位区间，原始count/exact观测用点叠加，黑短线是m后验均值。"
                     "count的结果预测使用本行真实Total，exact使用对应拟合含1端点质量的预测分布。原始interval没有已知真实点，未混入此点观测预测覆盖图。"
                     "预测带使用既有R后处理的经验分位数type=1，不由m后验区间代替。完整十模型的预测摘要和覆盖指标仍保留于CSV及总览图。",
                     pdf=pdf, pdf_name=pdfname, estimand="OOF posterior predictive future experimental ratio", interval="50% and 95% empirical posterior predictive intervals")


def metrics(cvtype):
    summary = all_extensions("joint", cvtype, "quantitative_metrics_summary.csv", ["Type", "MAE", "RMSE", "CRPS", "Coverage50", "Coverage95", "MeanPredictiveWidth50", "MeanPredictiveWidth95", "PointRule", "Weighting"])
    fold = all_extensions("joint", cvtype, "quantitative_metrics_by_fold.csv", ["Fold", "Type", "MAE", "RMSE", "CRPS", "PointRule"])
    predicted = all_extensions("joint", cvtype, "oof_predictive_summary.csv", ["Model", "RecordID", "Type", "Fold"])
    directory, _ = cv_directory("joint", cvtype)
    allocation = read(directory / "folds.csv", ["Species", "Fold"])
    expected_folds = set(allocation.Fold.astype(int))
    if not summary.PointRule.eq(POINT_RULE).all() or not fold.PointRule.eq(POINT_RULE).all():
        raise ValueError("Point prediction must be posterior mean(m), not median")
    if not summary.Weighting.eq("equal_weight_per_experiment").all():
        raise ValueError("Unexpected metric weighting")
    if CHECK_ONLY:
        return
    for kind in ["count+exact", "count", "exact"]:
        s = summary[summary.Type.eq(kind)].set_index("Model").loc[MODELS].reset_index()
        f = fold[fold.Type.eq(kind)]
        present = predicted[predicted.Type.isin(["count", "exact"]) if kind == "count+exact" else predicted.Type.eq(kind)]
        actual_counts = present.groupby(["Model", "Fold"]).size()
        reported_counts = f.set_index(["Model", "Fold"]).NRecords
        if not actual_counts.sort_index().equals(reported_counts.astype(int).sort_index()):
            raise ValueError("Metric fold coverage does not match actual count/exact OOF records")
        empty = []
        absent_sets = []
        for model in MODELS:
            absent = sorted(expected_folds - set(present.loc[present.Model.eq(model), "Fold"].astype(int)))
            absent_sets.append(tuple(absent))
            for k in absent:
                empty.append({"Model": model, "CVType": cvtype, "Type": kind, "Fold": k,
                              "NRecords": 0, "MAE": np.nan, "RMSE": np.nan, "CRPS": np.nan,
                              "RowType": "undefined_empty_fold", "Status": "NO_POINT_OBSERVATIONS"})
        if len(set(absent_sets)) != 1:
            raise ValueError("Point-observation fold coverage differs across compared models")
        empty_df = pd.DataFrame(empty)
        missing_folds = absent_sets[0]
        fig, axs = plt.subplots(1, 3, figsize=(225 / 25.4, 160 / 25.4), sharey=True)
        fig.subplots_adjust(left=.23, right=.97, top=.77, bottom=.22, wspace=.30)
        for ax, metric in zip(axs, ["MAE", "RMSE", "CRPS"]):
            for i, model in enumerate(MODELS):
                z = f[f.Model.eq(model)]
                for r in z.itertuples():
                    ax.scatter(getattr(r, metric) * 100, i + (r.Fold - 3) * .055, color=FC[int(r.Fold) - 1], marker=MARK[int(r.Fold) - 1], s=13, alpha=.75)
                ax.scatter(s.loc[s.Model.eq(model), metric] * 100, [i], marker="|", s=90, color=INK, zorder=4)
            ax.set_xlabel(f"{metric} (percentage points)")
            ax.set_xlim(left=0)
            ax.grid(axis="x", color=GRID, lw=.5)
        axs[0].set_yticks(range(10), MODELS)
        axs[0].invert_yaxis()
        subtitle = "Black ticks: pooled experiment-weighted score; symbols: individual folds"
        if missing_folds:
            subtitle += "\n" + ", ".join(f"F{k}" for k in missing_folds) + f": no {kind} records; fold metrics undefined (NA), not zero"
        header(fig, f"Quantitative holdout scores / {cvtype} / {kind}", subtitle)
        fold_legend(fig, y=.085)
        footer(fig, "MAE/RMSE use posterior mean(m). CRPS uses the full future-result predictive distribution. Lower is better.")
        save(fig, f"F02_quantitative_metrics_{cvtype}_{kind.replace('+', '_')}", pd.concat([s.assign(RowType="pooled"), f.assign(RowType="fold"), empty_df], ignore_index=True),
             "量化点观测子集的真实分组留出MAE、RMSE、CRPS。黑线为按实验等权汇总，彩色符号为各折；总体RMSE先对全部平方误差求均值再开根号，不能取各折RMSE平均。"
             "MAE/RMSE均以m后验均值为主点预测，CRPS来自真正未来结果预测分布。仅count/exact有真实点结果，区间不填中点且仍参与原联合拟合和ELPD。"
             "三项指标按0–1结果计算后乘100显示百分点。折散点是描述性变动，不代表95%置信区间。"
             "若某折没有当前count/exact子集的观测，该折的辅助指标未定义，图中明确标为NA且不伪造零分；逐图CSV另列undefined_empty_fold。"
             "这种空子集不删除联合模型中的区间观测，也不删除整折ELPD。", estimand="OOF experiment-weighted point errors and predictive CRPS", interval="Fold values, not confidence intervals")
    fig, axs = plt.subplots(1, 2, figsize=(215 / 25.4, 150 / 25.4), sharey=True)
    fig.subplots_adjust(left=.25, right=.96, top=.76, bottom=.14, wspace=.35)
    for i, model in enumerate(MODELS):
        for j, kind in enumerate(["count", "exact"]):
            z = summary[(summary.Model == model) & (summary.Type == kind)].iloc[0]
            for level, dx, mark in [(50, -.05, "o"), (95, .05, "s")]:
                yy = i + (j - .5) * .28 + dx
                color = BLUE if kind == "count" else ORANGE
                axs[0].scatter(z[f"Coverage{level}"] * 100, yy, color=color, marker=mark, s=19)
                axs[1].scatter(z[f"MeanPredictiveWidth{level}"] * 100, yy, color=color, marker=mark, s=19)
    axs[0].axvline(50, color=GRAY, ls=":", lw=.7)
    axs[0].axvline(95, color=GRAY, ls="--", lw=.7)
    axs[0].set(xlim=(0, 103), xlabel="Observed predictive coverage (%)", yticks=range(10), yticklabels=MODELS)
    axs[1].set(xlim=(0, 103), xlabel="Mean predictive interval width (pp)")
    axs[0].invert_yaxis()
    header(fig, f"Coverage and width / {cvtype}", "Blue=count; orange=exact; circles=50% interval; squares=95% interval")
    footer(fig, "Coverage is empirical, not an independent-binomial confidence statement; discrete count intervals can be conservative.")
    save(fig, f"S03_predictive_coverage_{cvtype}", summary, "按count/exact分别显示50%和95%后验预测区间的实际留出覆盖率和平均宽度。不使用整体期望m的后验区间，不对区间观测计算点覆盖。"
         "离散count预测区间可能保守；记录之间的依赖尚不允许把这些比率套成独立二项置信区间。", estimand="Empirical OOF future-result predictive coverage and width")


def species_predictions():
    d = primary_table("species_predictions_long.csv", ["Species", "Model", "PrHigh", "PrHighLower95", "PrHighUpper95", "PredictedRatio", "RatioLower95", "RatioUpper95", "BinarySupported", "RatioSupported"])
    tree_path = register_input(BASE / "input" / "tree.nwk")
    order = [x.name for x in Phylo.read(str(tree_path), "newick").get_terminals()]
    if len(d) != len(order) * 6 or d.duplicated(["Species", "Model"]).any() or set(d.Model) != set(SIX):
        raise ValueError("Species prediction panel is not the six-model full universe")
    if CHECK_ONLY:
        return
    for out, prefix, mid, lo, hi in [("binary", "Binary", "PrHigh", "PrHighLower95", "PrHighUpper95"), ("joint", "Ratio", "PredictedRatio", "RatioLower95", "RatioUpper95")]:
        pdfname = f"F06_full_species_predictions_{out}.pdf"
        npage = math.ceil(len(order) / 42)
        with PdfPages(FIG / pdfname) as pdf:
            for page in range(npage):
                names = order[page * 42:(page + 1) * 42]
                part = d[d.Species.isin(names)].copy()
                fig, axs = plt.subplots(1, 6, figsize=(285 / 25.4, 255 / 25.4), sharey=True)
                fig.subplots_adjust(left=.255, right=.98, top=.83, bottom=.13, wspace=.23)
                yy = np.arange(len(names))
                for ax, model in zip(axs, SIX):
                    q = part[part.Model.eq(model)].set_index("Species").loc[names]
                    support = bools(q[prefix + "Supported"])
                    identifiable = bools(q[prefix + "FixedEffectEstimable"])
                    has = q[prefix + "DataStatus"].eq("observed")
                    vals = q[[lo, mid, hi]].to_numpy(float)
                    if not np.isfinite(vals[support]).all() or not np.isnan(vals[~support]).all():
                        raise ValueError("Prediction support mask violated")
                    if np.any(vals[support] < 0) or np.any(vals[support] > 1) or np.any(np.diff(vals[support], axis=1) < 0):
                        raise ValueError("Posterior expectation interval bounds or ordering invalid")
                    for k, sp in enumerate(names):
                        if not support.iloc[k]:
                            ax.text(.5, k, "NA", ha="center", va="center", fontsize=6.1, color=GRAY)
                            continue
                        color = BLUE if identifiable.iloc[k] else ORANGE
                        ax.hlines(k, q.iloc[k][lo], q.iloc[k][hi], color=color, lw=.65)
                        ax.scatter(q.iloc[k][mid], k, marker="o" if identifiable.iloc[k] else "D", s=12, edgecolors=color, facecolors=color if has.iloc[k] else "white", linewidths=.6, zorder=3)
                    ax.set_xlim(-.025, 1.025)
                    ax.set_xticks([0, .5, 1], ["0", ".5", "1"])
                    ax.set_title(model, fontsize=8.7)
                    ax.grid(axis="x", color=GRID, lw=.4)
                    ax.set_xlabel("Pr(HIGH)" if out == "binary" else "Expected ratio")
                axs[0].set_yticks(yy, [s.replace("_", " ") for s in names], fontsize=7, style="italic")
                axs[0].invert_yaxis()
                header(fig, f"{out}: full-panel posterior predictions | {page + 1}/{npage}", "Median and 95% posterior interval of expectation; full-data fit, not held-out validation")
                footer(fig, "Filled: data present; open: projection; circle: estimable; diamond/orange: prior-dependent direction; NA: unsupported level.", y=.07)
                footer(fig, "The 365 model predictions are not 365 new experimental observations. Missing-site and new-combination flags are retained in source CSV.", y=.025)
                save(fig, f"F06_species_{out}_p{page + 1:02d}", part,
                     "全物种六结构预测，按固定输入树叶端顺序分页。点为全数据拟合后HIGH概率或整体期望m的后验中位数，线为95%期望量后验区间，绝不是未来实验预测带。"
                     "实心点表示该路线有观测结局，空心点为无标签物种投影；圆形表示可估方向，菱形和橙色共同标出固定效应不可估方向，NA保留未支持水平且不补零。"
                     "所有缺失位点、组合是否见过及支持标记保存在逐页源表。365个预测不是新增实验；本图不充当OOF验证。",
                     pdf=pdf, pdf_name=pdfname, estimand=f"Full-data posterior median expected quantity: {out}", interval="95% posterior interval of expectation")


def sensitivity():
    primary_gate()
    sstatus = read_json(RES / "postfit_sensitivity_status.json")
    if sstatus.get("status") != "COMPLETE_DIAGNOSTICS_AND_TRAINING_PPC":
        raise Pending("Sensitivity postprocessing is not complete")
    combined = read(RES / "sensitivity_expected_values_long.csv", ["Outcome", "Model", "Variant", "Species", "PrimaryKey", "AlternativeKey"])
    fit_selection = read(RUN / "fit_index.csv", ["Outcome", "Model", "Variant", "Key"])
    plan = read_json(BASE / "provenance" / "fit_plan.json")
    expected = plan.get("sensitivity_jobs")
    if expected is None:
        expected = plan.get("sensitivity")
    if expected is None:
        expected = [j for j in plan.get("main_jobs", []) if j.get("variant") != "primary"]
    if not isinstance(expected, list):
        raise Pending("Sensitivity job list is not exported under sensitivity_jobs")
    all_rows, diagnostic_rows = [], []
    for job in expected:
        out, model, variant = job["outcome"], job["model"], job["variant"]
        path = RES / f"sensitivity_{out}_{model}_{variant}.csv"
        legacy = read(path, ["Species", "PrimaryMedian", "AlternativeMedian", "MedianShift", "PrimaryLower", "PrimaryUpper", "AlternativeLower", "AlternativeUpper", "Supported"])
        d = combined[(combined.Outcome == out) & (combined.Model == model) & (combined.Variant == variant)].copy()
        primary_key = fit_selection[(fit_selection.Outcome == out) & (fit_selection.Model == model) & (fit_selection.Variant == "primary")].iloc[-1].Key
        alternative_key = fit_selection[(fit_selection.Outcome == out) & (fit_selection.Model == model) & (fit_selection.Variant == variant)].iloc[-1].Key
        if not d.PrimaryKey.eq(primary_key).all() or not d.AlternativeKey.eq(alternative_key).all():
            raise Pending(f"Sensitivity comparison no longer matches selected fits: {out}/{model}/{variant}")
        if len(d) != 365 or d.Species.duplicated().any() or list(d.Species) != list(legacy.Species):
            raise ValueError("Sensitivity long table and original export coverage differ")
        for col in ["PrimaryMedian", "AlternativeMedian", "MedianShift", "PrimaryLower", "PrimaryUpper", "AlternativeLower", "AlternativeUpper"]:
            if not np.allclose(d[col], legacy[col], equal_nan=True, atol=1e-12, rtol=0):
                raise ValueError("Sensitivity long table differs from the original manual comparison")
        dg = read(RES / f"diagnostics_{out}_{variant}.csv", ["Model", "Status"])
        row = dg[dg.Model.eq(model)]
        if len(row) != 1 or not row.Status.eq("PASS").all():
            raise Pending(f"Sensitivity diagnostics not passed: {out}/{model}/{variant}")
        row = row.copy()
        row["Outcome"], row["Variant"], row["DisplayLabel"] = out, variant, f"{model}/{variant}"
        diagnostic_rows.append(row)
        d["Outcome"], d["Model"], d["Variant"] = out, model, variant
        all_rows.append(d)
    data = pd.concat(all_rows, ignore_index=True)
    if CHECK_ONLY:
        return
    observed = set(read(BASE / "input" / "observations.csv", ["Species"]).Species)
    for out in OUTCOMES:
        subset = data[data.Outcome.eq(out)]
        diags = pd.concat([x for x in diagnostic_rows if x.Outcome.eq(out).all()], ignore_index=True)
        diagnostic_plot(diags, f"S05_diagnostics_{out}_sensitivity", f"{out}: sensitivity-fit diagnostics",
                        "All prespecified sensitivity structures; each selected fit must pass separately")
        pdfname = f"S08_sensitivity_{out}.pdf"
        with PdfPages(FIG / pdfname) as pdf:
            for (model, variant), d in subset.groupby(["Model", "Variant"], sort=False):
                valid = d[bools(d.Supported)].copy()
                fig, axs = plt.subplots(1, 2, figsize=(205 / 25.4, 125 / 25.4))
                fig.subplots_adjust(left=.10, right=.97, top=.75, bottom=.19, wspace=.34)
                has = valid.Species.isin(observed)
                known = valid[has]
                axs[0].errorbar(known.PrimaryMedian, known.AlternativeMedian,
                    xerr=np.vstack([known.PrimaryMedian - known.PrimaryLower, known.PrimaryUpper - known.PrimaryMedian]),
                    yerr=np.vstack([known.AlternativeMedian - known.AlternativeLower, known.AlternativeUpper - known.AlternativeMedian]),
                    fmt="none", ecolor="#92A5AF", alpha=.22, elinewidth=.5, zorder=1)
                axs[0].scatter(valid.loc[~has, "PrimaryMedian"], valid.loc[~has, "AlternativeMedian"], s=10, facecolors="white", edgecolors="#8C9FA9", lw=.5, label="unlabelled projection")
                axs[0].scatter(valid.loc[has, "PrimaryMedian"], valid.loc[has, "AlternativeMedian"], s=19, color=BLUE, label="with ratio data")
                axs[0].plot([0, 1], [0, 1], ls="--", color=GRAY, lw=.7)
                axs[0].set(xlim=(-.025, 1.025), ylim=(-.025, 1.025), xlabel="Primary posterior median", ylabel="Alternative posterior median", title="A  Point-summary stability")
                axs[0].legend(fontsize=6.3)
                axs[1].hist(valid.MedianShift * 100, bins=25, color="#C5DDEB", edgecolor=BLUE, lw=.4)
                axs[1].axvline(0, ls="--", color=GRAY, lw=.7)
                axs[1].set(xlabel="Alternative - primary median (pp)", ylabel="Panel species", title="B  Changes across supported species")
                header(fig, f"Sensitivity: {out} / {model} / {variant}", "Same expected quantity and source data; each posterior remains a separate fit")
                footer(fig, "Distribution in B is across species, not a posterior interval for a difference. Unsupported species stay in the source CSV.")
                save(fig, f"S08_sensitivity_{out}_{model}_{variant}", d,
                     "比较同路线同结构的主拟合与指定敏感性拟合。A为整体期望量后验中位数对照，有比率资料物种叠加横向/纵向的各自95%后验区间；不是两拟合的联合差值区间。"
                     "B为支持物种的中位数位移分布，不是不同后验同编号draw相减形成的差值后验。无支持物种保留于CSV但不伪造数值；敏感性拟合均须先通过抽样诊断。", pdf=pdf, pdf_name=pdfname, estimand="Shift between posterior point summaries under prespecified assumptions", interval="Separate 95% posterior intervals, not a paired difference interval")


def sensitivity_ppc(out):
    primary_gate()
    status = read_json(RES / "postfit_sensitivity_status.json")
    if status.get("status") != "COMPLETE_DIAGNOSTICS_AND_TRAINING_PPC":
        raise Pending("Sensitivity PPC is not complete")
    primary = read(RES / "ppc_statistic_plot_data_primary.csv", ["Outcome", "Model", "Subset", "Replicate", "Mean", "SD", "ZeroFraction", "OneFraction"])
    alternative = read(RES / "ppc_statistic_plot_data_sensitivity.csv", ["Outcome", "Model", "Variant", "Subset", "Replicate", "Mean", "SD", "ZeroFraction", "OneFraction"])
    observed = read(RES / "ppc_observed_plot_data_primary.csv", ["Outcome", "Model", "Subset", "Observed"])
    primary, alternative, observed = primary[primary.Outcome.eq(out)], alternative[alternative.Outcome.eq(out)], observed[observed.Outcome.eq(out)]
    if CHECK_ONLY:
        return
    for subset in alternative.Subset.unique():
        z = alternative[alternative.Subset.eq(subset)]
        groups = list(z[["Model", "Variant"]].drop_duplicates().itertuples(index=False, name=None))
        rows = []
        for model, variant in groups:
            p = primary[(primary.Model == model) & (primary.Subset == subset)]
            a = z[(z.Model == model) & (z.Variant == variant)]
            y = observed[(observed.Model == model) & (observed.Subset == subset)].Observed.to_numpy(float)
            actual = {"Mean": y.mean(), "SD": y.std(ddof=1), "ZeroFraction": (y == 0).mean(), "OneFraction": (y == 1).mean()}
            for stat in actual:
                qp, qa = np.quantile(p[stat], [.025, .5, .975]), np.quantile(a[stat], [.025, .5, .975])
                rows.append({"Outcome": out, "Subset": subset, "Model": model, "Variant": variant, "Statistic": stat,
                    "ObservedStatistic": actual[stat], "PrimaryLower95": qp[0], "PrimaryMedian": qp[1], "PrimaryUpper95": qp[2],
                    "AlternativeLower95": qa[0], "AlternativeMedian": qa[1], "AlternativeUpper95": qa[2]})
        result = pd.DataFrame(rows)
        fig, axs = plt.subplots(1, 4, figsize=(260 / 25.4, 160 / 25.4), sharey=True)
        fig.subplots_adjust(left=.28, right=.98, top=.78, bottom=.14, wspace=.33)
        for ax, stat in zip(axs, ["Mean", "SD", "ZeroFraction", "OneFraction"]):
            block = result[result.Statistic.eq(stat)]
            for i, r in enumerate(block.itertuples()):
                ax.hlines(i - .12, r.PrimaryLower95, r.PrimaryUpper95, color=BLUE, lw=.8)
                ax.scatter(r.PrimaryMedian, i - .12, color=BLUE, s=17, marker="o")
                ax.hlines(i + .12, r.AlternativeLower95, r.AlternativeUpper95, color=ORANGE, lw=.8)
                ax.scatter(r.AlternativeMedian, i + .12, color=ORANGE, s=17, marker="s")
            ax.axvline(float(block.ObservedStatistic.iloc[0]), color=PURPLE, ls="--", lw=.9)
            if stat in {"ZeroFraction", "OneFraction"}:
                fraction_values = block[["ObservedStatistic", "PrimaryLower95", "PrimaryUpper95", "AlternativeLower95", "AlternativeUpper95"]].to_numpy(float)
                if np.ptp(fraction_values) == 0:
                    ax.set_xlim(-.02, 1.02)
                    ax.set_xticks([0, .5, 1])
            ax.set_title(stat, fontsize=8)
            ax.set_xlabel("Predictive statistic")
        axs[0].set_yticks(range(len(groups)), [f"{m} / {v}" for m, v in groups], fontsize=7)
        axs[0].invert_yaxis()
        header(fig, f"Sensitivity PPC: {out} / {subset}", "Blue=primary; orange=alternative; dashed line=observed statistic")
        footer(fig, "Intervals describe replicated-data statistics (2.5%-97.5%); this is in-sample model checking, not held-out validation.")
        save(fig, f"S08_sensitivity_ppc_{out}_{subset}", result,
             "敏感性设置与对应主结构的训练内PPC摘要。各行分别显示主拟合与替代拟合重复数据统计量的中位数及95%范围，紫虚线为原数据统计量。"
             "统计量包括均值、标准差、0与1比例；区间是重复数据统计量分布，不是系数可信区间或OOF预测表现区间。不跨计数分布混比LOO。",
             estimand="In-sample posterior predictive statistic under alternative assumptions", interval="95% predictive-statistic interval")


def matrix_check(out):
    primary_gate()
    selected = read(RUN / "fit_index.csv", ["Outcome", "Variant", "Model", "Key"])
    row = selected[(selected.Outcome == out) & (selected.Variant == "primary") & (selected.Model == "M3_P")].iloc[-1]
    folder = RUN / "matrix_checks" / f"{out}_M3_P" / f"parent_{str(row.Key)[:16]}"
    matches = []
    for path in sorted(folder.glob("attempt_*/matrix_comparison_plot_data.csv")):
        state = read_json(path.parent / "status.json")
        if str(state.get("status", "")).startswith("COMPLETE_"):
            matches.append(path)
    if len(matches) != 1:
        raise Pending(f"Need one completed current-parent matrix check for {out}; found {len(matches)}")
    d = read(matches[0], ["Quantity", "FullMean", "SubmatrixMean", "Difference", "JointMCSE", "ReviewFlag", "Outcome", "Model", "ParentKey", "CheckKey", "QuantityType", "CheckSeed"])
    if not d.ParentKey.eq(row.Key).all() or not d.Outcome.eq(out).all() or not d.Model.eq("M3_P").all():
        raise ValueError("Matrix comparison identity mismatch")
    numeric_ok(d, ["FullMean", "SubmatrixMean", "Difference", "JointMCSE"])
    if not (d.JointMCSE > 0).all() or not np.allclose(d.FullMean - d.SubmatrixMean, d.Difference, atol=1e-10, rtol=0):
        raise ValueError("Matrix mean-difference definition invalid")
    flags = np.where(d.Difference.abs() <= 2 * d.JointMCSE, "within_2_MCSE", "review_difference")
    if not np.array_equal(flags, d.ReviewFlag):
        raise ValueError("Matrix review rule differs from frozen 2*MCSE rule")
    if CHECK_ONLY:
        return
    for qtype, part in d.groupby("QuantityType", sort=False):
        part = part.copy()
        part["DifferenceInJointMCSE"] = part.Difference / part.JointMCSE
        pages = math.ceil(len(part) / 40)
        pdfname = f"S09_matrix_check_{out}_{qtype}.pdf"
        with PdfPages(FIG / pdfname) as pdf:
            for page in range(pages):
                z = part.iloc[page * 40:(page + 1) * 40]
                fig, ax = plt.subplots(figsize=(215 / 25.4, max(130, 5 * len(z) + 75) / 25.4))
                fig.subplots_adjust(left=.45, right=.96, top=.79, bottom=.13)
                y = np.arange(len(z))
                ax.axvspan(-2, 2, color="#E8F1F5", zorder=0)
                ax.axvline(0, color=GRAY, lw=.7)
                ax.scatter(z.DifferenceInJointMCSE, y, color=np.where(z.ReviewFlag.eq("review_difference"), ORANGE, BLUE), s=22)
                qlabels = [str(x)[9:-1].replace("_", " ") if str(x).startswith("Expected[") and str(x).endswith("]") else str(x) for x in z.Quantity]
                ax.set_yticks(y, qlabels, fontsize=6.8)
                ax.invert_yaxis()
                ax.set_xlabel("Full - submatrix posterior mean (joint MCSE units)")
                header(fig, f"M3_P matrix check: {out} | {page + 1}/{pages}", f"{qtype}; original +/- 2 joint-MCSE review rule")
                footer(fig, "Orange = review_difference. This is not a failure-triggered search for a better seed or a 95% posterior interval.")
                save(fig, f"S09_matrix_{out}_{qtype}_p{page + 1:02d}", z,
                     "完整物种矩阵与有观测物种子矩阵核查，差值定义为完整矩阵后验均值减子矩阵后验均值，横轴以联合MCSE标准化。阴影范围是原指南±2联合MCSE的数值复核规则，不是95%后验区间。"
                     "超出范围的review_difference完整保留为橙点，不自动改种子重试。共同参数与物种期望量分开显示，比较只采用当前主拟合身份下唯一完成的核查。",
                     pdf=pdf, pdf_name=pdfname, estimand="Full/submatrix numerical posterior mean comparison", interval="Original +/-2 joint MCSE review rule", status="REVIEW_DIFFERENCES" if z.ReviewFlag.eq("review_difference").any() else "WITHIN_2_MCSE")


def folds():
    d = read(BASE / "provenance" / "cv_fold_composition.csv", ["Outcome", "CVType", "Fold", "Species", "Records", "High", "Low", "Unclassified", "Count", "Exact", "Interval"])
    obs = read(RUN / "prepared_observations.csv", ["RecordID", "Species", "Type", "High", "NoRatioInformation"])
    if obs.RecordID.duplicated().any():
        raise ValueError("Prepared RecordID values are not unique")
    allocations = []
    record_allocations, source_checks = [], []
    for out in OUTCOMES:
        for cvtype in CVTYPES:
            folder, _ = cv_directory(out, cvtype)
            allocation = read(folder / "folds.csv", ["Species", "Fold"])
            if allocation.Species.duplicated().any() or set(allocation.Fold) != {1, 2, 3, 4, 5}:
                raise ValueError("Actual fold allocation has duplicate species or incomplete fold labels")
            composition = d[(d.Outcome == out) & (d.CVType == cvtype)]
            if not np.array_equal(composition.set_index("Fold").sort_index().Species.to_numpy(), allocation.groupby("Fold").size().sort_index().to_numpy()):
                raise ValueError("Fold composition and actual allocation disagree")
            eligible = obs[obs.High.notna() if out == "binary" else ~bools(obs.NoRatioInformation)].copy()
            if set(eligible.Species) != set(allocation.Species):
                raise ValueError("Eligible source species differ from actual fold allocation")
            eligible = eligible.merge(allocation, on="Species", validate="many_to_one")
            eligible["Outcome"], eligible["CVType"] = out, cvtype
            if eligible.RecordID.duplicated().any():
                raise ValueError("An eligible source record occurs in more than one fold")
            record_allocations.append(eligible)
            for k in range(1, 6):
                rows = eligible[eligible.Fold.eq(k)]
                target = composition[composition.Fold.eq(k)]
                if len(target) != 1:
                    raise ValueError("Composition table has missing or duplicated fold rows")
                actual = {"Species": rows.Species.nunique(), "Records": len(rows),
                    "High": int(rows.High.eq(1).sum()), "Low": int(rows.High.eq(0).sum()),
                    "Unclassified": int(rows.High.isna().sum()), "Count": int(rows.Type.eq("count").sum()),
                    "Exact": int(rows.Type.eq("exact").sum()), "Interval": int(rows.Type.eq("interval").sum())}
                if any(int(target.iloc[0][field]) != value for field, value in actual.items()):
                    raise ValueError(f"Prepared records do not reproduce composition: {out}/{cvtype}/F{k}")
                source_checks.append({"Outcome": out, "CVType": cvtype, "Fold": k, **actual,
                    "LabelStatus": "HIGH_ONLY" if actual["High"] and not actual["Low"] else ("LOW_ONLY" if actual["Low"] and not actual["High"] else "BOTH_CLASSES"),
                    "RecordIDs": "|".join(rows.RecordID), "Status": "SOURCE_COUNTS_MATCH"})
            allocations.append(allocation.assign(Outcome=out, CVType=cvtype))
    if CHECK_ONLY:
        return
    fig, axs = plt.subplots(4, 3, figsize=(210 / 25.4, 245 / 25.4))
    fig.subplots_adjust(left=.10, right=.97, top=.83, bottom=.10, hspace=.73, wspace=.38)
    for row, (out, cvtype) in enumerate([(o, c) for o in OUTCOMES for c in CVTYPES]):
        z = d[(d.Outcome == out) & (d.CVType == cvtype)].sort_values("Fold")
        x = np.arange(len(z))
        species_bars = axs[row, 0].bar(x, z.Species, color="#3D6178")
        axs[row, 0].bar_label(species_bars, padding=2, fontsize=6.3)
        axs[row, 0].set_ylim(0, max(z.Species) * 1.24)
        axs[row, 0].set_title(f"{out} / {cvtype}\nSpecies", loc="left", fontsize=8)
        bottom = np.zeros(len(z))
        for col, color, hatch in [("High", BLUE, ""), ("Low", ORANGE, "//"), ("Unclassified", GRAY, "..")]:
            axs[row, 1].bar(x, z[col], bottom=bottom, color=color, hatch=hatch, edgecolor="white", lw=.3, label=col)
            bottom += z[col].to_numpy()
        axs[row, 1].set_title("HIGH / LOW / unclassified", loc="left", fontsize=8)
        for j, total in enumerate(z.High + z.Low + z.Unclassified):
            axs[row, 1].text(j, total, str(int(total)), ha="center", va="bottom", fontsize=6.3)
        axs[row, 1].set_ylim(0, max(z.Records) * 1.24)
        bottom = np.zeros(len(z))
        for col, color, hatch in [("Count", BLUE, ""), ("Exact", ORANGE, "//"), ("Interval", PURPLE, "..")]:
            axs[row, 2].bar(x, z[col], bottom=bottom, color=color, hatch=hatch, edgecolor="white", lw=.3, label=col)
            bottom += z[col].to_numpy()
        axs[row, 2].set_title("Data types", loc="left", fontsize=8)
        for j, total in enumerate(z.Count + z.Exact + z.Interval):
            axs[row, 2].text(j, total, str(int(total)), ha="center", va="bottom", fontsize=6.3)
        axs[row, 2].set_ylim(0, max(z.Records) * 1.24)
        for column, ax in enumerate(axs[row]):
            single = z.Low.eq(0) | z.High.eq(0)
            ax.set_xticks(x, [f"F{k}{'*' if mark else ''}" for k, mark in zip(z.Fold, single)])
            ax.set_ylabel("Species" if column == 0 else "Records")
            ax.yaxis.set_major_locator(MaxNLocator(integer=True, nbins=4))
    header(fig, "Actual held-out fold composition", "Species are held out together; phylogenetic-distance groups are not necessarily monophyletic")
    fig.legend(*axs[0, 1].get_legend_handles_labels(), loc="lower left", bbox_to_anchor=(.06, .045), fontsize=6.5, ncol=3)
    fig.legend(*axs[0, 2].get_legend_handles_labels(), loc="lower left", bbox_to_anchor=(.54, .045), fontsize=6.5, ncol=3)
    footer(fig, "* Single-class fold. Binary phylo_distance folds 3 and 4 are HIGH-only; complete CV_AUC remains undefined.", y=.020)
    checked_d = pd.DataFrame(source_checks)
    save(fig, "S04_fold_composition", checked_d, "本次实际折构成。每行依次显示该路线/划分的物种数、按既定规则的HIGH/LOW/未分类记录数和原始Type构成。"
         "计数条均从零起，数值与实际folds.csv物种分配核对。同物种全体记录一起留出。距离聚类块不保证是严格单系类群。"
         "分类路线仅包含有HIGH/LOW标签的记录，定量路线包含有定量信息的记录；两者不能因图中同列名称而混为同一评分对象。"
         "每条柱上数字为该栏总数，横轴星号标出单类别折。binary phylo_distance的第3、4折仅HIGH，完整CV_AUC必须保留NA，不删除这些折后平均。"
         "全部20个折汇总行已从prepared_observations与各自真实folds.csv独立重算物种数、记录数、标签和Type，逐项一致；逐条分折源表包含RecordID。", estimand="Actual heldout-species/record counts")
    source("S04_actual_species_fold_allocation", pd.concat(allocations, ignore_index=True))
    source("S04_source_record_fold_allocation", pd.concat(record_allocations, ignore_index=True))
    source("S04_source_count_checks", checked_d)


def finalize():
    status_file = FIG / ("INTERFACE_STATUS.csv" if CHECK_ONLY else "FIGURE_STATUS.csv")
    current_status = pd.DataFrame(STATUSES)
    if status_file.exists():
        old_status = pd.read_csv(status_file, encoding="utf-8-sig")
        scopes = {(s["Group"], s["Scope"]) for s in STATUSES}
        old_status = old_status[[tuple(x) not in scopes for x in old_status[["Group", "Scope"]].to_numpy()]]
        current_status = pd.concat([old_status, current_status], ignore_index=True)
    current_status.to_csv(status_file, index=False, encoding="utf-8-sig", lineterminator="\n")
    if FILES:
        index_path = FIG / "FIGURE_INDEX.csv"
        current = pd.DataFrame(FILES)
        if index_path.exists():
            previous = pd.read_csv(index_path, encoding="utf-8-sig")
            scopes = {(s["Group"], s["Scope"]) for s in STATUSES}
            if {"Group", "Scope"} <= set(previous):
                previous = previous[[tuple(x) not in scopes for x in previous[["Group", "Scope"]].to_numpy()]]
                current = pd.concat([previous, current], ignore_index=True)
        current.to_csv(index_path, index=False, encoding="utf-8-sig", lineterminator="\n")
        lines = ["# 本次模型图中文图注", "", "图件来自本次真实后处理；正式状态和是否完成视觉检查见FIGURE_STATUS和metadata。", ""]
        for stem, caption in CAPTIONS:
            lines += [f"## {stem}", "", caption, ""]
        for stem, caption in CAPTIONS:
            (FIG / f"{stem}_caption_zh.md").write_text(f"# {stem}\n\n{caption}\n", encoding="utf-8")
        captions = sorted(FIG.glob("*_caption_zh.md"))
        (FIG / "CAPTIONS_zh.md").write_text("\n\n".join(p.read_text(encoding="utf-8") for p in captions), encoding="utf-8")
    metadata = []
    for r in FILES:
        with Image.open(FIG / r["PNG"]) as im:
            assert min(im.info.get("dpi", (0, 0))) >= 599
            assert abs(im.width - r["WidthMM"] / 25.4 * 600) < 2
            assert abs(im.height - r["HeightMM"] / 25.4 * 600) < 2
            metadata.append({"FigureID": r["FigureID"], "Pixels": list(im.size), "DPI": list(im.info["dpi"])})
    changed = []
    for rel, before in USED.items():
        if sha(BASE / rel) != before["SHA256"]:
            changed.append(rel)
    report = {"status": "INTERFACES_CHECKED" if CHECK_ONLY else "AWAITING_VISUAL_REVIEW", "files_generated_this_invocation": len(FILES),
        "input_changes_during_read": changed, "source_files": USED, "canvas_checks": TEXT_QA, "PNG": metadata,
        "point_rule_for_quantitative_MAE_RMSE": POINT_RULE,
        "posterior_species_summary_rule": "posterior median as in manual 07",
        "new_fits_started": False, "simulated_data_created_by_plotter": False,
        "python": sys.version, "packages": {"matplotlib": matplotlib.__version__, "numpy": np.__version__, "pandas": pd.__version__}}
    report_path = FIG / ("interface_checks.json" if CHECK_ONLY else "metadata_checks.json")
    if not CHECK_ONLY and report_path.exists():
        previous = json.loads(report_path.read_text(encoding="utf-8"))
        regenerated = {r["FigureID"] for r in FILES}
        report["canvas_checks"] = [r for r in previous.get("canvas_checks", []) if r["FigureID"] not in regenerated] + TEXT_QA
        report["PNG"] = [r for r in previous.get("PNG", []) if r["FigureID"] not in regenerated] + metadata
        report["source_files"] = {**previous.get("source_files", {}), **USED}
        report["source_provenance_note"] = "Combined latest read signatures; each generated figure has its own immutable-at-generation provenance snapshot."
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    if changed:
        raise RuntimeError(f"Postprocessing files changed during plotting; rerun after they are stable: {changed}")
    if any(x["Status"] == "ERROR_CONTRACT" for x in STATUSES):
        return 1
    return 0


def audit_existing(confirm_visual_review=False):
    index_path = FIG / "FIGURE_INDEX.csv"
    if not index_path.exists():
        raise Pending("No model figures have been generated; only interface checks exist")
    index = pd.read_csv(index_path, encoding="utf-8-sig")
    checks, fonts = [], []
    pdf_counts = index.groupby("PDF").size()
    for r in index.itertuples():
        with Image.open(FIG / r.PNG) as im:
            dpi = im.info.get("dpi", (0, 0))
            opaque = "A" not in im.getbands() or im.getchannel("A").getextrema() == (255, 255)
            if min(dpi) < 599 or not opaque or abs(im.width - r.WidthMM / 25.4 * 600) >= 2 or abs(im.height - r.HeightMM / 25.4 * 600) >= 2:
                raise ValueError(f"PNG export failed metadata audit: {r.PNG}")
            pixels = list(im.size)
        svg = ET.parse(FIG / r.SVG).getroot()
        w = float(svg.attrib["width"].removesuffix("pt")) / 72 * 25.4
        h = float(svg.attrib["height"].removesuffix("pt")) / 72 * 25.4
        if abs(w - r.WidthMM) > .03 or abs(h - r.HeightMM) > .03 or not svg.findall(".//{http://www.w3.org/2000/svg}text"):
            raise ValueError(f"SVG export failed metadata audit: {r.SVG}")
        src = BASE / r.SourceCSV
        if not src.exists() or len(pd.read_csv(src, encoding="utf-8-sig")) == 0:
            raise ValueError(f"Missing or empty per-figure source CSV: {src}")
        checks.append({"FigureID": r.FigureID, "Pixels": pixels, "DPI": list(dpi), "Opaque": opaque,
                       "WidthMM": w, "HeightMM": h, "CSV_SHA256": sha(src)})
    for name, expected_pages in pdf_counts.items():
        reader = PdfReader(str(FIG / name))
        if len(reader.pages) != expected_pages:
            raise ValueError(f"PDF page count disagrees with figure index: {name}")
        for k, page in enumerate(reader.pages, 1):
            if not page.extract_text().strip():
                raise ValueError(f"No extractable PDF text: {name}/{k}")
            for _, ref in page.get("/Resources", {}).get("/Font", {}).items():
                font = ref.get_object()
                descriptors = []
                for child in font.get("/DescendantFonts", [font]):
                    obj = child.get_object()
                    if "/FontDescriptor" in obj:
                        descriptors.append(obj["/FontDescriptor"].get_object())
                if not descriptors or not all(any(v in fd for v in ["/FontFile", "/FontFile2", "/FontFile3"]) for fd in descriptors):
                    raise ValueError(f"Unembedded font: {name}/{k}")
                fonts.append({"PDF": name, "Page": k, "Font": str(font.get("/BaseFont")), "Embedded": True})
    pd.DataFrame(fonts).to_csv(FIG / "pdf_font_checks.csv", index=False, encoding="utf-8-sig")
    states = pd.read_csv(FIG / "FIGURE_STATUS.csv", encoding="utf-8-sig")
    incomplete = states[~states.Status.eq("GENERATED_AWAITING_VISUAL_REVIEW")]
    expected_scopes = set()
    for out in OUTCOMES:
        expected_scopes.update((g, out) for g in ["coefficients", "diagnostics", "pareto", "ppc", "ppc_ecdf", "sensitivity_ppc", "matrix_check"])
        expected_scopes.update((g, f"{out}_{c}") for c in CVTYPES for g in ["cv_elpd", "cv_mc", "cv_diagnostics"])
    expected_scopes.update((g, c) for c in CVTYPES for g in ["roc_calibration", "quantitative", "predictive_bands", "metrics"])
    expected_scopes.update({("species_predictions", "both"), ("sensitivity", "both"), ("folds", "all")})
    actual_scopes = set(zip(states.Group, states.Scope))
    missing_scopes = sorted(expected_scopes - actual_scopes)
    final_status = "PARTIAL_OR_AWAITING_VISUAL_REVIEW"
    if confirm_visual_review and incomplete.empty:
        final_status = "PASS_GENERATED_SUBSET_ONLY" if missing_scopes else "PASS_MODEL_FIGURES"
    result = {"status": final_status,
        "manual_visual_review_confirmed": confirm_visual_review, "figures": len(index), "pdf_files": len(pdf_counts),
        "pdf_pages": int(pdf_counts.sum()), "embedded_font_entries": len(fonts),
        "pending_scopes": incomplete.to_dict("records"), "not_yet_generated_scopes": [{"Group": g, "Scope": s} for g, s in missing_scopes], "exports": checks,
        "warning": "Export and visual QA do not certify scientific model assumptions, MC score stability or target-journal compliance"}
    if confirm_visual_review:
        qa_path = FIG / "VISUAL_QA.csv"
        if not qa_path.exists():
            raise ValueError("Confirming visual review requires a per-figure VISUAL_QA.csv ledger")
        qa = pd.read_csv(qa_path, encoding="utf-8-sig")
        if not {"FigureID", "ReviewStatus", "PNG_SHA256"} <= set(qa) or qa.FigureID.duplicated().any():
            raise ValueError("Visual review ledger is missing required fields or has repeated FigureID")
        qa = qa.set_index("FigureID")
        for r in index.itertuples():
            if r.FigureID not in qa.index:
                if r.VisualReview == "COMPLETED_BY_REVIEWER":
                    continue
                raise ValueError(f"No actual visual review recorded for {r.FigureID}")
            check = qa.loc[r.FigureID]
            if check.ReviewStatus != "PASS" or str(check.PNG_SHA256) != sha(FIG / r.PNG):
                raise ValueError(f"Visual review is incomplete or stale for {r.FigureID}")
        index["VisualReview"] = "COMPLETED_BY_REVIEWER"
        index.to_csv(index_path, index=False, encoding="utf-8-sig", lineterminator="\n")
    (FIG / "final_figure_checks.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    manifest = []
    for folder in [FIG, DATA]:
        for p in sorted(folder.rglob("*")):
            if p.is_file() and "_mplconfig" not in p.relative_to(folder).parts and p.name not in ["MANIFEST.csv", "MANIFEST.sha256"]:
                manifest.append({"Path": str(p.relative_to(BASE)), "Bytes": p.stat().st_size, "SHA256": sha(p)})
    for p in [Path(__file__).resolve(), BASE / "review" / "model_figure_notes.md"]:
        if p.exists():
            manifest.append({"Path": str(p.relative_to(BASE)), "Bytes": p.stat().st_size, "SHA256": sha(p)})
    pd.DataFrame(manifest).to_csv(FIG / "MANIFEST.csv", index=False, encoding="utf-8-sig", lineterminator="\n")
    (FIG / "MANIFEST.sha256").write_text("\n".join(f"{r['SHA256']}  {r['Path']}" for r in manifest) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "exports"}, ensure_ascii=False), flush=True)


def main():
    global CHECK_ONLY, CURRENT_GROUP, CURRENT_SCOPE, CURRENT_INPUTS
    tasks = []
    for out in OUTCOMES:
        for group, fn in [("coefficients", coefficients), ("diagnostics", diagnostics), ("pareto", pareto), ("ppc", ppc), ("ppc_ecdf", ppc_ecdf)]:
            tasks.append((group, out, lambda fn=fn, out=out: fn(out)))
        tasks += [("sensitivity_ppc", out, lambda o=out: sensitivity_ppc(o)),
                  ("matrix_check", out, lambda o=out: matrix_check(o))]
        for cvtype in CVTYPES:
            tasks += [("cv_elpd", f"{out}_{cvtype}", lambda o=out, c=cvtype: cv_elpd(o, c)),
                      ("cv_mc", f"{out}_{cvtype}", lambda o=out, c=cvtype: cv_mc(o, c)),
                      ("cv_diagnostics", f"{out}_{cvtype}", lambda o=out, c=cvtype: cv_diagnostics(o, c))]
    for cvtype in CVTYPES:
        tasks += [("roc_calibration", cvtype, lambda c=cvtype: roc_calibration(c)),
                  ("quantitative", cvtype, lambda c=cvtype: quantitative("joint", c)),
                  ("predictive_bands", cvtype, lambda c=cvtype: predictive_bands(c)),
                  ("metrics", cvtype, lambda c=cvtype: metrics(c))]
    tasks += [("species_predictions", "both", species_predictions), ("sensitivity", "both", sensitivity), ("folds", "all", folds)]
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-inputs", action="store_true", help="Validate interfaces only; no figures")
    parser.add_argument("--group", action="append", choices=sorted({x[0] for x in tasks}),
                        help="Select one or more groups; repeat this option to generate a stable subset in one invocation")
    parser.add_argument("--audit-existing", action="store_true")
    parser.add_argument("--confirm-visual-review", action="store_true")
    args = parser.parse_args()
    if args.audit_existing:
        audit_existing(args.confirm_visual_review)
        return
    CHECK_ONLY = args.check_inputs
    for group, scope, fn in tasks:
        if args.group and group not in args.group:
            continue
        CURRENT_GROUP, CURRENT_SCOPE = group, scope
        CURRENT_INPUTS = {}
        before = len(FILES)
        try:
            fn()
            state, reason = ("INTERFACE_READY" if CHECK_ONLY else "GENERATED_AWAITING_VISUAL_REVIEW"), ""
        except Pending as e:
            state, reason = "PENDING_FORMAL_DATA", str(e)
        except Exception as e:
            state, reason = "ERROR_CONTRACT", f"{type(e).__name__}: {e}"
            traceback.print_exc()
        STATUSES.append({"Group": group, "Scope": scope, "Status": state, "Reason": reason, "NewFigures": len(FILES) - before})
        print(json.dumps(STATUSES[-1], ensure_ascii=False), flush=True)
    raise SystemExit(finalize())


if __name__ == "__main__":
    main()
