"""Read-only descriptive figures for the frozen 2026-09-14 ratio data.

No fitting, outcome imputation, midpoint substitution, or input rewriting.
Run with the bundled Python. Plotting dependencies may be in
figures/descriptive/_runtime; that directory is excluded from deliverables.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import sys
import xml.etree.ElementTree as ET

BASE = Path(__file__).resolve().parents[1]
FIG = BASE / "figures" / "descriptive"
DATA = BASE / "figure_data" / "descriptive"
FIG.mkdir(parents=True, exist_ok=True)
DATA.mkdir(parents=True, exist_ok=True)
os.environ["MPLCONFIGDIR"] = str(FIG / "_mplconfig")
if (FIG / "_runtime").is_dir():
    sys.path.insert(0, str(FIG / "_runtime"))

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.colors import ListedColormap, BoundaryNorm
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
import numpy as np
import pandas as pd
from Bio import Phylo
from PIL import Image
from pypdf import PdfReader

RUN = BASE / "runs" / "formal_20260914_26e686af86fa"
SITES = ["Site3", "Site20", "Site117", "Site151", "Site196", "Site315"]
NUMS = [s.replace("Site", "") for s in SITES]
COLORS = {"count": "#0072B2", "exact": "#D55E00", "interval": "#6F5487",
          "HIGH": "#0072B2", "LOW": "#D55E00", "Unclassified": "#777777"}
BG = "#FFFFFF"
INK = "#182C3B"
GRID = "#E1E7EA"
ARTIFACTS: list[dict] = []
TEXT_CHECKS: list[dict] = []
COUNTERS: dict[str, list] = {"raw_records": [], "matrix_species": []}
CAPTIONS: list[tuple[str, str, str]] = []

matplotlib.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 8.2,
    "axes.labelsize": 8.2, "axes.titlesize": 10.0,
    "axes.titleweight": "bold", "axes.labelcolor": INK,
    "text.color": INK, "xtick.color": INK, "ytick.color": INK,
    "axes.edgecolor": "#A5B1B9", "axes.linewidth": .6,
    "axes.spines.top": False, "axes.spines.right": False,
    "xtick.labelsize": 7.2, "ytick.labelsize": 7.2,
    "xtick.major.width": .5, "ytick.major.width": .5,
    "xtick.major.size": 3, "ytick.major.size": 2,
    "legend.fontsize": 7.2, "legend.frameon": False,
    "pdf.fonttype": 42, "ps.fonttype": 42, "svg.fonttype": "none",
    "savefig.facecolor": BG, "figure.facecolor": BG,
})


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path, keep_default_na=False, encoding="utf-8-sig")


INPUTS = {
    "observations": BASE / "input" / "observations.csv",
    "sites": BASE / "input" / "sites.csv",
    "tree": BASE / "input" / "tree.nwk",
    "prepared_species": RUN / "prepared_species.csv",
    "prepared_observations": RUN / "prepared_observations.csv",
    "binary_counts": RUN / "binary_counts.csv",
    "source_map": BASE / "provenance" / "observation_source_map.csv",
    "source_identifiers": BASE / "provenance" / "source_identifiers.csv",
}
BEFORE = {k: {"path": str(p), "sha256": sha(p), "bytes": p.stat().st_size,
              "mtime_ns": p.stat().st_mtime_ns} for k, p in INPUTS.items()}

obs = read_csv(INPUTS["prepared_observations"])
raw_obs = read_csv(INPUTS["observations"])
sites = read_csv(INPUTS["sites"])
species = read_csv(INPUTS["prepared_species"])
binary = read_csv(INPUTS["binary_counts"])
source_map = read_csv(INPUTS["source_map"])
source_ids = read_csv(INPUTS["source_identifiers"])

assert not obs.RecordID.duplicated().any()
assert list(obs.RecordID) == list(raw_obs.RecordID)
for field in raw_obs.columns:
    # Compare parsed values, tolerating integer/float display representation only.
    left = pd.to_numeric(obs[field], errors="coerce")
    right = pd.to_numeric(raw_obs[field], errors="coerce")
    if field in ["Events", "Total", "Exact", "Lower", "Upper"]:
        assert np.allclose(left, right, equal_nan=True), field
    else:
        assert list(obs[field].astype(str)) == list(raw_obs[field].astype(str)), field
assert list(species.Species) == list(sites.Species)
assert not species.Species.duplicated().any()
assert set(obs.Species) <= set(species.Species)
assert set(source_map.RecordID) == set(obs.RecordID)
obs = obs.merge(source_map[["RecordID", "ExcelRow", "SourceCode", "OriginalExperiment"]],
                on="RecordID", validate="one_to_one")
for field in ["Events", "Total", "Exact", "Lower", "Upper", "High"]:
    obs[field] = pd.to_numeric(obs[field], errors="coerce")
obs["Label"] = obs.High.map({1.0: "HIGH", 0.0: "LOW"}).fillna("Unclassified")
obs["ObservedPoint"] = np.where(obs.Type.eq("count"), obs.Events / obs.Total,
                                np.where(obs.Type.eq("exact"), obs.Exact, np.nan))
assert obs.loc[obs.Type.eq("interval"), "ObservedPoint"].isna().all()
expected_labels = []
for r in obs.itertuples():
    if r.Type == "count":
        expected_labels.append("HIGH" if 2 * r.Events >= r.Total else "LOW")
    elif r.Type == "exact":
        expected_labels.append("HIGH" if r.Exact >= .5 else "LOW")
    else:
        expected_labels.append("HIGH" if r.Lower >= .5 else ("LOW" if r.Upper <= .5 else "Unclassified"))
assert list(obs.Label) == expected_labels

tree = Phylo.read(str(INPUTS["tree"]), "newick")
tree_order = [x.name for x in tree.get_terminals()]
assert len(tree_order) == len(set(tree_order))
assert set(tree_order) == set(species.Species)
species = species.set_index("Species").loc[tree_order].reset_index()
order = {s: i for i, s in enumerate(tree_order)}
observed = set(obs.Species)
observed_order = [s for s in tree_order if s in observed]
N, NS, NP, NREF = len(obs), len(observed), len(species), obs.SourceID.nunique()
assert NS == len(observed_order)

composition = pd.DataFrame({"Species": observed_order})
composition["TreeOrder"] = composition.Species.map(order)
for kind in ["count", "exact", "interval"]:
    composition[kind] = composition.Species.map(obs[obs.Type.eq(kind)].groupby("Species").size()).fillna(0).astype(int)
for kind in ["HIGH", "LOW", "Unclassified"]:
    composition[kind] = composition.Species.map(obs[obs.Label.eq(kind)].groupby("Species").size()).fillna(0).astype(int)
composition["Records"] = composition[["count", "exact", "interval"]].sum(axis=1)
composition["Sources"] = composition.Species.map(obs.groupby("Species").SourceID.nunique()).astype(int)
composition["Trials"] = composition.HIGH + composition.LOW
bc = binary.set_index("Species").loc[observed_order]
for a, b in [("Records", "RecordCount"), ("HIGH", "HighCount"), ("LOW", "LowCount"),
             ("Unclassified", "UnclassifiedCount"), ("Trials", "Trials")]:
    assert np.array_equal(composition[a], pd.to_numeric(bc[b]).to_numpy()), (a, b)


def csv_out(name: str, frame: pd.DataFrame) -> Path:
    p = DATA / name
    frame.to_csv(p, index=False, encoding="utf-8-sig", na_rep="", lineterminator="\n")
    return p


def foot(fig, line: str, y=.024):
    fig.text(.04, y, line, fontsize=7.0, color="#4C616F", va="bottom")


def header(fig, title: str, subtitle: str, y=.966):
    fig.text(.04, y, title, fontsize=13, weight="bold", va="top", color=INK)
    fig.text(.04, y - .042, subtitle, fontsize=8.0, va="top", color="#4C616F")


def panel(ax, label: str, title: str):
    ax.set_title(f"{label}  {title}", loc="left", pad=8)


def latin_labels(ax, labels, size=7.2):
    ax.set_yticklabels([x.replace("_", " ") for x in labels], fontsize=size, style="italic")


def check_text(fig, stem):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    box = fig.bbox
    outside = []
    for text in fig.findobj(match=matplotlib.text.Text):
        if not text.get_visible() or not text.get_text() or text.get_clip_on():
            continue
        bb = text.get_window_extent(renderer)
        if bb.width == 0 or bb.height == 0:
            continue
        if bb.x0 < -1 or bb.y0 < -1 or bb.x1 > box.width + 1 or bb.y1 > box.height + 1:
            outside.append(text.get_text())
    TEXT_CHECKS.append({"Figure": stem, "OutsideCanvasText": outside})


def save(fig, stem: str, source_file: Path, caption: str, title: str,
         pdf_pages: PdfPages | None = None, pdf_name: str | None = None):
    check_text(fig, stem)
    if pdf_pages is None:
        fig.savefig(FIG / f"{stem}.pdf", metadata={"Title": title, "Subject": caption,
                    "Creator": "plot_descriptive.py; no model fitting"})
        pdf_rel = f"{stem}.pdf"
    else:
        pdf_pages.savefig(fig)
        pdf_rel = str(pdf_name)
    fig.savefig(FIG / f"{stem}.svg")
    fig.savefig(FIG / f"{stem}.png", dpi=600)
    fig.savefig(FIG / f"{stem}_preview.png", dpi=150)
    ARTIFACTS.append({"FigureID": stem, "Title": title, "PDF": pdf_rel,
                      "SVG": f"{stem}.svg", "PNG_600dpi": f"{stem}.png",
                      "Preview": f"{stem}_preview.png", "SourceCSV": str(source_file.relative_to(BASE)),
                      "WidthMM": round(fig.get_figwidth() * 25.4, 2),
                      "HeightMM": round(fig.get_figheight() * 25.4, 2),
                      "Estimator": "Observed data / descriptive counts", "Uncertainty": "None; raw intervals retained",
                      "Scope": "Frozen 2026-09-14 input only; no fitted results"})
    CAPTIONS.append((stem, title, caption))
    plt.close(fig)
    print(f"SAVED {stem}", flush=True)


def plot_overview():
    df = composition.copy()
    summary = []
    for group, values in [("DataType", obs.Type), ("BinaryLabel", obs.Label),
                           ("RecordsPerSpecies", df.Records), ("SourcesPerSpecies", df.Sources)]:
        for category, n in values.value_counts().sort_index().items():
            summary.append({"Panel": group, "Category": category, "Count": n,
                            "Unit": "records" if group in ["DataType", "BinaryLabel"] else "species"})
    source = csv_out("F01_overview_source.csv", pd.DataFrame(summary))
    fig, axs = plt.subplots(2, 2, figsize=(180 / 25.4, 150 / 25.4))
    fig.subplots_adjust(left=.10, right=.97, bottom=.12, top=.79, wspace=.33, hspace=.66)
    header(fig, "Data composition and uneven evidence", f"{N} records  |  {NS} species with ratio data  |  {NREF} source identifiers  |  {NP} panel species")
    for ax, categories, values, colors, letter, title in [
        (axs[0, 0], ["count", "exact", "interval"], obs.Type, COLORS, "A", "Reported data types"),
        (axs[0, 1], ["HIGH", "LOW", "Unclassified"], obs.Label, COLORS, "B", "High/Low classification")]:
        counts = values.value_counts().reindex(categories, fill_value=0)
        bars = ax.bar(categories, counts, color=[colors[x] for x in categories], width=.62,
                      edgecolor="white", hatch=["", "//", ".."][0:len(categories)])
        ax.bar_label(bars, padding=3, fontsize=8)
        ax.set_ylim(0, max(counts) * 1.22)
        ax.set_ylabel("Records")
        ax.tick_params(axis="x", rotation=0)
        panel(ax, letter, title)
    for ax, field, letter, title in [(axs[1, 0], "Records", "C", "Records per species"),
                                    (axs[1, 1], "Sources", "D", "Sources per species")]:
        counts = df[field].value_counts().sort_index()
        xx = np.arange(len(counts))
        bars = ax.bar(xx, counts.to_numpy(), color="#385F7A", width=.68)
        ax.set_xticks(xx, [str(int(x)) for x in counts.index])
        ax.bar_label(bars, padding=2, fontsize=7)
        ax.set_ylim(0, counts.max() * 1.23)
        ax.set_xlabel(field)
        ax.set_ylabel("Species")
        panel(ax, letter, title)
    foot(fig, "Source identifiers, experimental records and individual counts are distinct units.")
    cap = (f"本次冻结数据含{N}条记录、{NS}个有比率资料的物种和{NREF}个来源标识，位点面板共{NP}物种。"
           "A为计数、未知分母具体比率和区间记录的构成；B为按已确认边界形成的HIGH/LOW/未分类记录；"
           "C、D分别显示每物种的记录数与不同来源标识数。直方条均从零起，数值为实际数量，不添加误差线。"
           "来源标识数不自动证明论文或实验相互独立；实验记录数也不等于个体总数。区间上界等于50%归LOW，具体点值等于50%归HIGH，严格跨越50%的区间不分类。")
    save(fig, "F01_data_overview", source, cap, "Data composition and uneven evidence")


def plot_species_evidence():
    source = csv_out("S01A_species_evidence_source.csv", composition)
    fig, axs = plt.subplots(1, 3, figsize=(220 / 25.4, 275 / 25.4), sharey=True,
                            gridspec_kw={"width_ratios": [1.2, 1.2, .60]})
    fig.subplots_adjust(left=.34, right=.97, bottom=.07, top=.825, wspace=.22)
    header(fig, "Evidence by species", "Tree-tip order; counts describe records, not independent experimental units")
    yy = np.arange(NS)
    for ax, cols, title in [(axs[0], ["count", "exact", "interval"], "Reported type"),
                            (axs[1], ["HIGH", "LOW", "Unclassified"], "Classified outcome")]:
        left = np.zeros(NS)
        for j, col in enumerate(cols):
            ax.barh(yy, composition[col], left=left, color=COLORS[col], label=col,
                    height=.75, edgecolor="white", linewidth=.2, hatch=["", "//", ".."][j])
            left += composition[col].to_numpy()
        ax.set_xlabel("Records")
        ax.set_title(title, loc="left")
        ax.set_xlim(0, max(composition.Records) * 1.03)
        ax.set_axisbelow(True)
        ax.grid(axis="x", color=GRID, linewidth=.4)
        ax.legend(loc="lower left", bbox_to_anchor=(0, 1.025), ncol=1, fontsize=6.7)
    axs[2].barh(yy, composition.Sources, color="#455C68", height=.72)
    axs[2].set_title("Sources", loc="left")
    axs[2].set_xlabel("Identifiers")
    axs[2].set_xticks(np.arange(0, composition.Sources.max() + 1, 2))
    for i, n in enumerate(composition.Sources):
        axs[2].text(n + .12, i, str(n), va="center", fontsize=6.6)
    axs[2].set_xlim(0, composition.Sources.max() + 1)
    axs[0].set_yticks(yy)
    latin_labels(axs[0], composition.Species, size=7.3)
    axs[0].invert_yaxis()
    for ax in axs:
        ax.tick_params(axis="y", length=0)
    foot(fig, "A species may have multiple outcomes from one source; no independence assumption is added by this figure.")
    cap = ("按输入树的叶端顺序列出全部有观测物种。左、中为按记录类型及HIGH/LOW状态分解的原始条数，右为每物种不同来源标识数。"
           "共享横轴量纲是记录数，第三栏为来源标识数，不相加。一个物种可同时有HIGH与LOW，未强行归为单一物种标签。"
           "本图只显示资料数量的不均衡，不调整模型权重，也不假定同文献或跨文献记录互相独立。")
    save(fig, "S01A_species_evidence", source, cap, "Evidence by species")


def plot_raw_records():
    display = obs.sort_values("ExcelRow").copy()
    columns = ["RecordID", "ExcelRow", "Species", "SourceCode", "SourceID", "OriginalExperiment",
               "Type", "Events", "Total", "Exact", "Lower", "Upper", "ObservedPoint", "Label"]
    csv_out("S01B_all_raw_records_source.csv", display[columns])
    pages = math.ceil(N / 40)
    pdf_name = "S01B_all_raw_ratio_records.pdf"
    with PdfPages(FIG / pdf_name, metadata={"Title": "All raw ratio records; no interval midpoint"}) as pdf:
        for page in range(pages):
            part = display.iloc[page * 40:(page + 1) * 40].copy()
            source = csv_out(f"S01B_raw_records_page{page + 1:02d}_source.csv", part[columns])
            fig = plt.figure(figsize=(240 / 25.4, 235 / 25.4))
            ax = fig.add_axes([.47, .115, .40, .745])
            table_ax = fig.add_axes([.03, .115, .42, .745], sharey=ax)
            n_ax = fig.add_axes([.884, .115, .085, .745], sharey=ax)
            header(fig, f"All reported ratios  |  page {page + 1}/{pages}",
                   "A line segment is the reported interval; no midpoint is plotted")
            yy = np.arange(len(part))
            ax.set_xlim(-.025, 1.025)
            ax.set_ylim(len(part) - .5, -.5)
            ax.set_xticks(np.linspace(0, 1, 6), ["0", "20", "40", "60", "80", "100"])
            ax.set_xlabel("Reported ratio (%)")
            ax.set_yticks([])
            ax.axvline(.5, ls="--", lw=.7, color="#697C89", zorder=1)
            ax.grid(axis="x", color=GRID, lw=.45, zorder=0)
            table_ax.set_xlim(0, 1)
            n_ax.set_xlim(0, 1)
            for a in [table_ax, n_ax]:
                a.axis("off")
            table_ax.text(0, -.017, "Species / original Excel row", transform=table_ax.transAxes,
                          fontsize=7.0, va="top", color="#536672")
            n_ax.text(.0, -.017, "n = Total", transform=n_ax.transAxes,
                      fontsize=7, va="top", color="#536672")
            for i, r in enumerate(part.itertuples()):
                if i % 2 == 0:
                    ax.axhspan(i - .5, i + .5, color="#F4F7F8", zorder=0)
                    table_ax.axhspan(i - .5, i + .5, color="#F4F7F8", zorder=0)
                    n_ax.axhspan(i - .5, i + .5, color="#F4F7F8", zorder=0)
                table_ax.text(.0, i, r.Species.replace("_", " "), va="center", style="italic", fontsize=7.2)
                table_ax.text(.985, i, f"R{int(r.ExcelRow):03d}  {r.SourceCode}/E{r.OriginalExperiment}",
                              va="center", ha="right", fontsize=7.0, color="#4C616F")
                if r.Type == "interval":
                    ax.hlines(i, r.Lower, r.Upper, color=COLORS["interval"], lw=2.0, zorder=3)
                    ax.vlines([r.Lower, r.Upper], i - .18, i + .18, color=COLORS["interval"], lw=1.0, zorder=3)
                else:
                    ax.scatter(r.ObservedPoint, i, s=20, color=COLORS[r.Type], marker="o" if r.Type == "count" else "D",
                               edgecolors="white", linewidths=.35, zorder=3)
                n_ax.text(.0, i, str(int(r.Total)) if r.Type == "count" else "unknown", va="center", fontsize=6.7)
                COUNTERS["raw_records"].append(r.RecordID)
            handles = [Line2D([], [], color=COLORS["count"], marker="o", ls="", label="count: Events / Total"),
                       Line2D([], [], color=COLORS["exact"], marker="D", ls="", label="exact: denominator unknown"),
                       Line2D([], [], color=COLORS["interval"], lw=2, label="reported interval")]
            fig.legend(handles=handles, loc="lower left", bbox_to_anchor=(.04, .049), ncol=3, fontsize=7.1)
            foot(fig, "R = source workbook row; S = source code; E = within-source experiment label. Source identifiers are provided in CSV.", y=.017)
            cap = (f"原始比率完整长图，第{page + 1}/{pages}页，按原工作簿行号排列。圆点为Events/Total，菱形为未知分母的具体比率；"
                   "带端帽的水平线完整保留原始区间，不绘制其中心点，也不将区间当作95%误差线。右侧n是计数记录的真实分母，未知分母明确写unknown。"
                   "R对应原工作簿Excel行号，S为本次冻结来源代码，E为文献内实验标签；完整来源字符串及RecordID保存在逐页CSV。"
                   "每条记录在整套图中恰好出现一次，相同结果未去重或抖动数值。50%虚线仅指示分类边界，不能暗示不同实验条件具有可比性。")
            save(fig, f"S01B_raw_records_page{page + 1:02d}", source, cap, "All reported ratios", pdf, pdf_name)


def plot_source_matrix():
    source_order = list(source_ids.sort_values("SourceCode").SourceCode)
    ct = pd.crosstab(obs.Species, obs.SourceCode).reindex(index=observed_order, columns=source_order, fill_value=0)
    long = ct.reset_index().melt(id_vars="Species", var_name="SourceCode", value_name="Records")
    long = long.merge(source_ids, on="SourceCode", validate="many_to_one")
    source = csv_out("S01C_source_species_matrix_source.csv", long)
    assert int(ct.to_numpy().sum()) == N
    fig = plt.figure(figsize=(275 / 25.4, 245 / 25.4))
    ax = fig.add_axes([.285, .125, .675, .75])
    header(fig, "Where the records come from", f"{NS} species x {len(source_order)} source identifiers; cell values are record counts")
    max_n = int(ct.to_numpy().max())
    colors = ["#FFFFFF"] + [matplotlib.colors.to_hex(plt.get_cmap("Blues")(.25 + .65 * i / max_n)) for i in range(1, max_n + 1)]
    cmap = ListedColormap(colors)
    ax.imshow(ct.to_numpy(), cmap=cmap, norm=BoundaryNorm(np.arange(-.5, max_n + 1.5), cmap.N), aspect="auto", interpolation="nearest")
    ax.set_yticks(np.arange(NS))
    latin_labels(ax, observed_order, 7.0)
    ax.set_xticks(np.arange(len(source_order)), source_order, rotation=90, fontsize=6.0)
    ax.tick_params(length=0)
    for i, j in zip(*np.where(ct.to_numpy() > 0)):
        n = int(ct.iloc[i, j])
        ax.text(j, i, str(n), ha="center", va="center", fontsize=6.2, color="white" if n >= max_n * .65 else INK)
    ax.set_xlabel("Source code (full identifier in source CSV)", labelpad=8)
    foot(fig, "White cells contain no records. Numbers are displayed in every nonzero cell; source equality does not establish sample independence.")
    cap = ("来源×物种记录数热图。物种按输入树叶端顺序，来源按本次固定S代码顺序；每个非零格直接标注实际记录数，白格为0。"
           f"来源代码到完整来源标识的对应保留在逐图CSV中。每条原始记录恰计入一个格，总和为本次真实的{N}条记录。"
           "该图显示资料的来源聚集，不断言每个来源对应独立样本，更不根据跨文献数值重复自动删除记录。")
    save(fig, "S01C_source_species_matrix", source, cap, "Where the records come from")


def plot_denominators():
    counts = obs[obs.Type.eq("count")].copy()
    freq = counts.groupby("Total").size().rename("Records").reset_index()
    source = csv_out("S01D_denominator_distribution_source.csv", counts[["RecordID", "ExcelRow", "Species", "SourceCode", "Events", "Total", "ObservedPoint", "Label"]])
    csv_out("S01D_denominator_frequencies.csv", freq)
    fig, axs = plt.subplots(1, 2, figsize=(180 / 25.4, 105 / 25.4))
    fig.subplots_adjust(left=.10, right=.97, top=.72, bottom=.20, wspace=.38)
    header(fig, "Denominators in count records", f"{len(counts)} count records; denominator values are retained as reported", y=.95)
    xx = np.arange(len(freq))
    bars = axs[0].bar(xx, freq.Records, color=COLORS["count"], width=.65)
    axs[0].set_xticks(xx, [str(int(x)) for x in freq.Total], rotation=45)
    axs[0].bar_label(bars, padding=3, fontsize=7)
    axs[0].set_ylim(0, freq.Records.max() * 1.25)
    axs[0].set_xlabel("Reported denominator (Total)")
    axs[0].set_ylabel("Records")
    panel(axs[0], "A", "Denominator frequencies")
    points = counts.groupby(["Total", "ObservedPoint", "Label"]).size().rename("Multiplicity").reset_index()
    for label, marker in [("HIGH", "o"), ("LOW", "s")]:
        part = points[points.Label.eq(label)]
        axs[1].scatter(part.Total, part.ObservedPoint * 100, s=part.Multiplicity * 12, c=COLORS[label],
                       marker=marker, alpha=.85, linewidths=.35, edgecolors="white", label=label)
    axs[1].set_ylim(-10, 112)
    axs[1].set_yticks([0, 20, 40, 60, 80, 100])
    axs[1].set_xlim(0, counts.Total.max() * 1.10)
    axs[1].axhline(50, ls="--", color="#7A8B95", lw=.65)
    axs[1].set_xlabel("Reported denominator (Total)")
    axs[1].set_ylabel("Reported ratio (%)")
    axs[1].legend(handles=[Line2D([], [], color=COLORS[label], marker=marker, ls="", markersize=5, label=label)
                           for label, marker in [("HIGH", "o"), ("LOW", "s")]], loc="lower right", fontsize=6.8)
    panel(axs[1], "B", "Ratio versus denominator")
    foot(fig, "Marker area in B is proportional to the number of identical records; records remain distinct in the source data.", y=.045)
    cap = (f"仅包含{len(counts)}条计数记录。A按表内实际出现的分母值统计记录数，横轴为离散类别；B显示比率与分母的原始关系。"
           "B中相同分母、比率和分类标签的记录仅为呈现而重合聚合，点面积与重合记录条数成正比，CSV仍逐条保留。"
           "计数比率0和1正常保留。分母是每行报告的Total，不将不同文献或实验的Total之和称为独立样本总数。"
           "未知分母的exact和interval记录不被赋予虚构分母。")
    save(fig, "S01D_denominator_distribution", source, cap, "Denominators in count records")


def missing_raw(x):
    return str(x).strip().upper() in ["", "NA", "X", "-", "MISSING", "INDEL"]


def plot_coverage():
    frames = []
    for group, subset in [("All panel species", species), ("Species with ratio data", species[species.Species.isin(observed)])]:
        for site in SITES:
            miss = int(subset[site].map(missing_raw).sum())
            frames.append({"Population": group, "Site": site, "Species": len(subset),
                           "Missing": miss, "Present": len(subset) - miss, "MissingPercent": miss / len(subset) * 100})
    coverage = pd.DataFrame(frames)
    source = csv_out("S02A_site_coverage_source.csv", coverage)
    residues = []
    alphabet = list("ACDEFGHIKLMNPQRSTVWY") + ["MISSING"]
    freq_matrix = []
    for site in SITES:
        vals = species[site].map(lambda x: "MISSING" if missing_raw(x) else str(x))
        freqs = vals.value_counts().reindex(alphabet, fill_value=0)
        freq_matrix.append(freqs.to_numpy())
        for aa, num in freqs.items():
            residues.append({"Site": site, "Residue": aa, "Count": num, "PanelSpecies": NP, "Percent": num / NP * 100})
    csv_out("S02A_raw_residue_frequencies.csv", pd.DataFrame(residues))
    fig, axs = plt.subplots(2, 1, figsize=(190 / 25.4, 150 / 25.4), gridspec_kw={"height_ratios": [1, 1]})
    fig.subplots_adjust(left=.12, right=.96, top=.79, bottom=.11, hspace=.68)
    header(fig, "Six-site coverage and amino-acid diversity", f"The full panel contains {NP} species; {NS} have ratio observations")
    yy = np.arange(6)
    for group, dy, color, hatch in [("All panel species", -.16, "#0072B2", ""),
                                     ("Species with ratio data", .16, "#D55E00", "//")]:
        vals = coverage[coverage.Population.eq(group)]
        bars = axs[0].barh(yy + dy, vals.MissingPercent, height=.30, color=color, label=group, hatch=hatch)
        for bar, r in zip(bars, vals.itertuples()):
            axs[0].text(bar.get_width() + .5, bar.get_y() + bar.get_height() / 2, f"{r.Missing}/{r.Species}", va="center", fontsize=6.7)
    axs[0].set_yticks(yy, NUMS)
    axs[0].invert_yaxis()
    axs[0].set_xlim(0, max(coverage.MissingPercent) + 14)
    axs[0].set_ylabel("Reference site")
    axs[0].set_xlabel("Missing-coded species (%)")
    axs[0].legend(loc="lower right", fontsize=7)
    panel(axs[0], "A", "Missing-site coverage")
    matrix = np.array(freq_matrix)
    cmap = plt.get_cmap("Blues").copy()
    cmap.set_bad("#FFFFFF")
    masked = np.ma.masked_where(matrix == 0, matrix)
    axs[1].imshow(masked, aspect="auto", cmap=cmap, vmin=0, vmax=NP, interpolation="nearest")
    axs[1].set_xticks(np.arange(len(alphabet)), ["?" if x == "MISSING" else x for x in alphabet])
    axs[1].set_yticks(np.arange(6), NUMS)
    axs[1].set_ylabel("Reference site")
    axs[1].set_xlabel("Amino-acid letter; ? = missing-coded value")
    axs[1].tick_params(length=0)
    for i, j in zip(*np.where(matrix > 0)):
            axs[1].text(j, i, str(matrix[i, j]), ha="center", va="center", fontsize=7.0,
                    color="white" if matrix[i, j] >= NP * .55 else INK)
    panel(axs[1], "B", "Residue counts in the full panel")
    foot(fig, "A gap or unknown residue is a missing code here; this does not establish a biological deletion.", y=.027)
    cap = (f"A分别以全部{NP}个面板物种和{NS}个有比率资料物种为分母，显示六个位点的缺失编码比例，条旁列缺失数/对应物种总数。"
           "B为全物种各位点氨基酸字符频数，非零格直接写数量，白格为0，问号为按现有模型规则识别的MISSING。"
           "短横线或未知字符在当前建模中按缺失处理，本图不能判断它是生物学真实缺失还是比对/测序信息不足。"
           "位点编号沿用实验参考蛋白的原始编号，不是每个物种自身同号位置或比对列号。")
    save(fig, "S02A_site_coverage", source, cap, "Six-site coverage and amino-acid diversity")


def display_category(group, value):
    if group == "Raw":
        return str(value), (3 if missing_raw(value) else 0)
    if value == "MISSING":
        return "?", 3
    if group == "M1":
        return {"C_validated": ("C*", 0), "K_validated": ("K*", 0),
                "K_or_T": ("KT", 0), "R": ("R", 2), "other": ("o", 1)}[value]
    if group == "M2":
        return ("+", 0) if value == "CKST" else ("-", 1)
    return ("O", 1) if value == "OTHER" else (str(value), 0)


def plot_full_matrix():
    rows = []
    for r in species.itertuples(index=False):
        d = r._asdict()
        for group in ["Raw", "M1", "M2", "M3"]:
            for site in SITES:
                key = site if group == "Raw" else f"{group}_{site}"
                label, color = display_category(group, d[key])
                rows.append({"Species": d["Species"], "TreeOrder": order[d["Species"]],
                             "HasRatioData": d["Species"] in observed, "Encoding": group,
                             "Site": site, "OriginalValue": d[key], "DisplayLabel": label, "ColorClass": color})
    all_data = pd.DataFrame(rows)
    csv_out("S02B_full_panel_all_encodings_source.csv", all_data)
    page_n = 42
    pages = math.ceil(NP / page_n)
    pdf_name = "S02B_365_species_site_and_encoding_matrix.pdf"
    cmap = ListedColormap(["#E1EEF6", "#F7E5D2", "#E9DEF1", "#D8DDE0", "#FFFFFF"])
    with PdfPages(FIG / pdf_name, metadata={"Title": "Full panel amino acids and frozen encodings"}) as pdf:
        for page in range(pages):
            part_species = tree_order[page * page_n:(page + 1) * page_n]
            data = all_data[all_data.Species.isin(part_species)]
            source = csv_out(f"S02B_panel_page{page + 1:02d}_source.csv", data)
            lookup = {(r.Species, r.Encoding, r.Site): (r.DisplayLabel, r.ColorClass) for r in data.itertuples()}
            labels = []
            cm = []
            for sp in part_species:
                labels.append((["\u2022"] if sp in observed else [""]) +
                              [lookup[(sp, g, s)][0] for g in ["Raw", "M1", "M2", "M3"] for s in SITES])
                cm.append([4] + [lookup[(sp, g, s)][1] for g in ["Raw", "M1", "M2", "M3"] for s in SITES])
            fig = plt.figure(figsize=(275 / 25.4, 255 / 25.4))
            ax = fig.add_axes([.29, .145, .675, .71])
            header(fig, f"All panel species: amino acids and encodings  |  {page + 1}/{pages}",
                   "Fixed input tree-tip order; black dots mark species with ratio data")
            ax.imshow(np.array(cm), cmap=cmap, norm=BoundaryNorm(np.arange(-.5, 5.5), cmap.N), aspect="auto", interpolation="nearest")
            ax.set_xlim(-.5, 24.5)
            ax.set_yticks(np.arange(len(part_species)))
            latin_labels(ax, part_species, 7.3)
            ax.set_xticks(np.arange(25), ["Obs"] + NUMS * 4, fontsize=7)
            ax.xaxis.tick_top()
            ax.tick_params(length=0, axis="both")
            for i, sp in enumerate(part_species):
                for j in range(25):
                    ax.text(j, i, labels[i][j], ha="center", va="center", fontsize=7.2)
                COUNTERS["matrix_species"].append(sp)
            for j in [.5, 6.5, 12.5, 18.5]:
                ax.axvline(j, color=BG, lw=3)
            for mid, group in zip([3.5, 9.5, 15.5, 21.5], ["Raw amino acids", "M1", "M2", "M3"]):
                ax.text((mid + .5) / 25, 1.065, group, transform=ax.transAxes,
                        ha="center", va="bottom", fontsize=8.8, weight="bold")
            fig.text(.04, .097, "M1: C*/K* = reference-matching; KT = K or T; R = R; o = other.    M2: + = C/K/S/T; - = other amino acids.", fontsize=7.0)
            fig.text(.04, .073, "M3: literal amino acid if retained; O = OTHER (1-3 occurrences in the 365-species reference).    ? = MISSING.", fontsize=7.0)
            fig.text(.04, .049, "Raw cells retain the original character, including '-'. Category colors aid reading; letters and symbols carry the exact values.", fontsize=7.0)
            foot(fig, "* is a coding label, not evidence that the current analysis validates an amino-acid function.", y=.020)
            cap = (f"全部{NP}物种面板的完整六位点和M1/M2/M3编码矩阵，第{page + 1}/{pages}页。物种严格按输入树的叶端顺序分页，未重估树。"
                   "Raw栏保留输入原始字符；M1的C*/K*表示与既定位点参考残基相同的编码，KT表示K或T，R单列，o为other；星号不是本次验证功能的证据。"
                   "M2的+表示C/K/S/T，-表示其余标准氨基酸。M3保留达到4次的残基字母，O表示频数1–3次合并成的OTHER。"
                   "?表示MISSING，原始Raw栏中的短横线仍为原字符。左侧黑点表示本次有比率记录的物种，不表示数据数量相同或结局分类明确。"
                   "颜色只协助阅读，所有单元格的实际值由字符冗余呈现；逐页CSV同时保存完整原值及展示缩写。")
            save(fig, f"S02B_panel_page{page + 1:02d}", source, cap, "All panel species: amino acids and encodings", pdf, pdf_name)


def plot_encoding_frequencies():
    all_rows = []
    for group in ["M1", "M2", "M3"]:
        for site in SITES:
            col = f"{group}_{site}"
            categories = sorted(set(species[col]), key=lambda x: (x == "MISSING", x == "OTHER", x))
            for pop, frame in [("All panel species", species), ("Species with ratio data", species[species.Species.isin(observed)])]:
                count = frame[col].value_counts()
                for value in categories:
                    n = int(count.get(value, 0))
                    all_rows.append({"Encoding": group, "Site": site, "Category": value, "Population": pop,
                                     "Count": n, "Species": len(frame), "Percent": n / len(frame) * 100})
    all_data = pd.DataFrame(all_rows)
    csv_out("S02C_all_encoding_frequencies_source.csv", all_data)
    for group in ["M1", "M2", "M3"]:
        source = csv_out(f"S02C_{group}_frequencies_source.csv", all_data[all_data.Encoding.eq(group)])
        fig, axs = plt.subplots(3, 2, figsize=(205 / 25.4, 245 / 25.4))
        fig.subplots_adjust(left=.20, right=.965, bottom=.09, top=.82, wspace=.57, hspace=.56)
        header(fig, f"{group}: category frequencies and outcome-data coverage",
               f"Bars: all {NP} panel species; diamonds: the {NS} species with ratio data")
        for ax, site, letter in zip(axs.flat, SITES, "ABCDEF"):
            data = all_data[all_data.Encoding.eq(group) & all_data.Site.eq(site)]
            full = data[data.Population.eq("All panel species")]
            have = data[data.Population.eq("Species with ratio data")]
            assert list(full.Category) == list(have.Category)
            yy = np.arange(len(full))
            ax.barh(yy, full.Percent, color="#BCD7E8", height=.60, edgecolor="#0072B2", lw=.35)
            ax.scatter(have.Percent, yy, marker="D", s=17, color="#A14A12", zorder=3)
            label_map = {"C_validated": "C (reference)", "K_validated": "K (reference)",
                         "K_or_T": "K or T", "non_CKST": "not C/K/S/T", "CKST": "C/K/S/T"}
            ax.set_yticks(yy, [label_map.get(x, x) for x in full.Category], fontsize=7.0)
            ax.invert_yaxis()
            ax.set_xlim(-3, 103)
            ax.set_xticks([0, 25, 50, 75, 100])
            ax.set_xlabel("Species (%)")
            ax.grid(axis="x", color=GRID, lw=.4, zorder=0)
            ax.set_axisbelow(True)
            panel(ax, letter, site.replace("Site", "Site "))
        foot(fig, "Percentages include MISSING in each population denominator; encodings are frozen and are not re-estimated for the observed subset.", y=.030)
        cap = (f"{group}六个位点的编码频率。蓝条为全物种面板频率，棕色菱形为有比率资料物种的频率，二者以各自物种数为分母，均包含MISSING类别。"
               "每个物种在各位点恰计一次；有比率资料子集沿用固定全物种字典，不重新划分OTHER。"
               "M3的OTHER阈值为小于1%，在本次365物种面板即出现1、2、3次合并。具体数量、分母和百分比见源CSV。"
               "频率差异只描述有资料物种对面板基因型的覆盖，不给出因果解释或统计显著性。")
        save(fig, f"S02C_{group}_category_frequencies", source, cap, f"{group}: category frequencies and outcome-data coverage")


def assert_encoding_contract():
    for site in SITES:
        raw = species[site].map(lambda x: "MISSING" if missing_raw(x) else str(x))
        frequency = raw[raw.ne("MISSING")].value_counts()
        expected = raw.map(lambda x: "MISSING" if x == "MISSING" else (x if frequency[x] >= 4 else "OTHER"))
        assert list(expected) == list(species[f"M3_{site}"]), site
    assert int(composition.Records.sum()) == N
    assert int(composition.Trials.sum()) == obs.High.notna().sum()


def finish():
    assert COUNTERS["raw_records"] == list(obs.sort_values("ExcelRow").RecordID)
    assert COUNTERS["matrix_species"] == tree_order
    assert_encoding_contract()
    for name, old in BEFORE.items():
        p = INPUTS[name]
        assert sha(p) == old["sha256"] and p.stat().st_size == old["bytes"] and p.stat().st_mtime_ns == old["mtime_ns"], name
    csv_out("source_identifiers.csv", source_ids)
    csv_out("species_tree_order.csv", pd.DataFrame({"TreeOrder": range(1, NP + 1), "Species": tree_order,
                                                    "HasRatioData": [s in observed for s in tree_order]}))
    pd.DataFrame(ARTIFACTS).to_csv(FIG / "FIGURE_INDEX.csv", index=False, encoding="utf-8-sig", lineterminator="\n")
    lines = ["# 本次描述性图集：中文详细图注", "", "本图集仅使用本次冻结输入与其prepare结果，不读取拟合、历史或demo结果。所有区间保持原上下界，原始文件未修改。", ""]
    for stem, title, caption in CAPTIONS:
        lines += [f"## {stem}", "", f"英文标题：{title}", "", caption, ""]
    lines += ["## 软件与复核", "", "作图脚本为 scripts/plot_descriptive.py；依赖版本和输入哈希见 metadata_checks.json。", "",
              "600dpi PNG按实际像素和导出物理尺寸核对；PDF/SVG为通用投稿候选。尚未指定目标期刊，不宣称符合特定期刊规格。", "",
              "_runtime和_mplconfig为本地绘图环境，不属于论文图件；正式图清单以FIGURE_INDEX.csv为准。", ""]
    (FIG / "CAPTIONS_zh.md").write_text("\n".join(lines), encoding="utf-8")
    metadata = []
    pdfs = {}
    for item in ARTIFACTS:
        png = FIG / item["PNG_600dpi"]
        with Image.open(png) as image:
            dpi = image.info.get("dpi", (0, 0))
            expected = (round(item["WidthMM"] / 25.4 * 600), round(item["HeightMM"] / 25.4 * 600))
            assert abs(image.width - expected[0]) <= 2 and abs(image.height - expected[1]) <= 2
            assert min(dpi) >= 599
            tiny = image.convert("RGB").resize((256, 256))
            variance = float(np.array(tiny).var())
            assert variance > 5
            metadata.append({"File": item["PNG_600dpi"], "Pixels": list(image.size), "DPI": list(dpi),
                             "Mode": image.mode, "NonemptyVariance": variance})
        pdf = FIG / item["PDF"]
        if item["PDF"] not in pdfs:
            reader = PdfReader(str(pdf))
            pages = []
            for page in reader.pages:
                dims = [float(page.mediabox.width) / 72 * 25.4, float(page.mediabox.height) / 72 * 25.4]
                fonts = page.get("/Resources", {}).get("/Font", {})
                font_types = []
                for font in fonts.values():
                    fo = font.get_object()
                    font_types.append(str(fo.get("/Subtype")))
                assert page.extract_text().strip()
                pages.append({"WidthMM": dims[0], "HeightMM": dims[1], "FontTypes": font_types,
                              "ExtractableText": True})
            pdfs[item["PDF"]] = pages
    outside = [x for x in TEXT_CHECKS if x["OutsideCanvasText"]]
    check = {"status": "NEEDS_VISUAL_REVIEW" if not outside else "TEXT_CLIPPING_REVIEW",
             "records": N, "observed_species": NS, "panel_species": NP, "source_identifiers": NREF,
             "high": int(obs.Label.eq("HIGH").sum()), "low": int(obs.Label.eq("LOW").sum()),
             "unclassified": int(obs.Label.eq("Unclassified").sum()),
             "record_page_coverage": "each record exactly once", "panel_matrix_coverage": "each species exactly once",
             "interval_midpoints": "none", "M3_threshold_check": "PASS: counts 1-3 OTHER, >=4 literal",
             "input_immutability": "PASS: byte count, hash and mtime unchanged",
             "inputs": BEFORE, "python": platform.python_version(), "packages": {
                 "matplotlib": matplotlib.__version__, "numpy": np.__version__, "pandas": pd.__version__},
             "png_metadata": metadata, "pdf_metadata": pdfs, "canvas_text_checks": TEXT_CHECKS,
             "new_fitting_started": False, "historical_or_demo_results_used": False}
    (FIG / "metadata_checks.json").write_text(json.dumps(check, indent=2, ensure_ascii=False), encoding="utf-8")
    file_rows = []
    for folder in [FIG, DATA]:
        for p in sorted(folder.iterdir()):
            if not p.is_file() or p.name in ["MANIFEST.csv", "MANIFEST.sha256"]:
                continue
            file_rows.append({"Path": str(p.relative_to(BASE)), "Bytes": p.stat().st_size, "SHA256": sha(p)})
    script = Path(__file__).resolve()
    file_rows.append({"Path": str(script.relative_to(BASE)), "Bytes": script.stat().st_size, "SHA256": sha(script)})
    pd.DataFrame(file_rows).to_csv(FIG / "MANIFEST.csv", index=False, encoding="utf-8-sig", lineterminator="\n")
    (FIG / "MANIFEST.sha256").write_text("\n".join(f"{r['SHA256']}  {r['Path']}" for r in file_rows) + "\n", encoding="utf-8")
    print(json.dumps({"figures": len(ARTIFACTS), "records": N, "observed_species": NS,
                      "panel_species": NP, "outside_text_figures": len(outside), "file_manifest_entries": len(file_rows)}, ensure_ascii=False), flush=True)


def audit_existing(confirm_visual_review=False):
    """Audit delivered files without rerendering or fitting; human review is explicit."""
    index = read_csv(FIG / "FIGURE_INDEX.csv")
    checked = json.loads((FIG / "metadata_checks.json").read_text(encoding="utf-8"))
    for name, old in checked["inputs"].items():
        p = INPUTS[name]
        assert sha(p) == old["sha256"] and p.stat().st_size == old["bytes"]
        assert p.stat().st_mtime_ns == old["mtime_ns"]
    assert not any(x["OutsideCanvasText"] for x in checked["canvas_text_checks"])
    audit = []
    for r in index.itertuples():
        png_path = FIG / r.PNG_600dpi
        with Image.open(png_path) as im:
            assert min(im.info.get("dpi", (0, 0))) >= 599
            assert abs(im.width - float(r.WidthMM) / 25.4 * 600) < 2
            assert abs(im.height - float(r.HeightMM) / 25.4 * 600) < 2
            opaque = ("A" not in im.getbands()) or im.getchannel("A").getextrema() == (255, 255)
            assert opaque, png_path
        svg = ET.parse(FIG / r.SVG).getroot()
        assert svg.attrib["width"].endswith("pt") and svg.attrib["height"].endswith("pt")
        w_mm = float(svg.attrib["width"][:-2]) / 72 * 25.4
        h_mm = float(svg.attrib["height"][:-2]) / 72 * 25.4
        assert abs(w_mm - float(r.WidthMM)) < .03 and abs(h_mm - float(r.HeightMM)) < .03
        texts = svg.findall(".//{http://www.w3.org/2000/svg}text")
        assert len(texts) > 0
        audit.append({"FigureID": r.FigureID, "OpaquePNG": True, "SVGWidthMM": w_mm,
                      "SVGHeightMM": h_mm, "SVGTextElements": len(texts), "MetadataStatus": "PASS"})
    font_rows = []
    page_count = 0
    for name in index.PDF.unique():
        reader = PdfReader(str(FIG / name))
        for page_id, page in enumerate(reader.pages, 1):
            page_count += 1
            assert page.extract_text().strip()
            fonts = page.get("/Resources", {}).get("/Font", {})
            for key, ref in fonts.items():
                font = ref.get_object()
                descendants = font.get("/DescendantFonts", [font])
                embedded = []
                for desc in descendants:
                    obj = desc.get_object()
                    descriptor = obj.get("/FontDescriptor")
                    if descriptor:
                        fd = descriptor.get_object()
                        embedded.append(any(k in fd for k in ["/FontFile", "/FontFile2", "/FontFile3"]))
                assert embedded and all(embedded), (name, page_id, key)
                font_rows.append({"PDF": name, "Page": page_id, "Font": str(font.get("/BaseFont")),
                                  "Subtype": str(font.get("/Subtype")), "Embedded": True})
    assert page_count == len(index)
    raw_pages = pd.concat([read_csv(p) for p in sorted(DATA.glob("S01B_raw_records_page*_source.csv"))], ignore_index=True)
    assert list(raw_pages.RecordID) == list(obs.sort_values("ExcelRow").RecordID)
    assert raw_pages.loc[raw_pages.Type.eq("interval"), "ObservedPoint"].eq("").all()
    matrix_pages = pd.concat([read_csv(p) for p in sorted(DATA.glob("S02B_panel_page*_source.csv"))], ignore_index=True)
    assert len(matrix_pages) == NP * 24
    assert not matrix_pages.duplicated(["Species", "Encoding", "Site"]).any()
    assert list(matrix_pages.Species.drop_duplicates()) == tree_order
    assert_encoding_contract()
    pd.DataFrame(font_rows).to_csv(FIG / "pdf_font_checks.csv", index=False, encoding="utf-8-sig")
    checked["status"] = "PASS_DESCRIPTIVE_FIGURES" if confirm_visual_review else "AWAITING_HUMAN_VISUAL_REVIEW"
    checked["manual_visual_review"] = {"completed": confirm_visual_review,
        "scope": "All 21 rendered PNG pages reviewed; remaining PDF/SVG checks are structural metadata checks, not a journal-compliance certification",
        "corrections": ["Moved species-evidence legends below subtitle", "Expanded denominator plot limits to preserve endpoint markers", "Added a fixed Obs column to avoid shifting amino-acid columns"]}
    checked["existing_export_audit"] = audit
    checked["pdf_pages"] = page_count
    checked["pdf_files"] = len(index.PDF.unique())
    checked["script_sha256"] = sha(Path(__file__).resolve())
    (FIG / "metadata_checks.json").write_text(json.dumps(checked, indent=2, ensure_ascii=False), encoding="utf-8")
    rows = []
    for folder in [FIG, DATA]:
        for p in sorted(folder.iterdir()):
            if p.is_file() and p.name not in ["MANIFEST.csv", "MANIFEST.sha256"]:
                rows.append({"Path": str(p.relative_to(BASE)), "Bytes": p.stat().st_size, "SHA256": sha(p)})
    for p in [Path(__file__).resolve(), BASE / "review" / "descriptive_figure_checks.md"]:
        if p.exists():
            rows.append({"Path": str(p.relative_to(BASE)), "Bytes": p.stat().st_size, "SHA256": sha(p)})
    pd.DataFrame(rows).to_csv(FIG / "MANIFEST.csv", index=False, encoding="utf-8-sig", lineterminator="\n")
    (FIG / "MANIFEST.sha256").write_text("\n".join(f"{r['SHA256']}  {r['Path']}" for r in rows) + "\n", encoding="utf-8")
    print(json.dumps({"status": checked["status"], "figures": len(index), "pdf_files": len(index.PDF.unique()),
                      "pdf_pages": page_count, "font_entries_embedded": len(font_rows),
                      "manifest_entries": len(rows)}, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=["overview", "evidence", "raw", "sources", "denominators", "coverage", "matrix", "frequencies"])
    parser.add_argument("--audit-only", action="store_true")
    parser.add_argument("--confirm-visual-review", action="store_true")
    args = parser.parse_args()
    funcs = {"overview": plot_overview, "evidence": plot_species_evidence, "raw": plot_raw_records,
             "sources": plot_source_matrix, "denominators": plot_denominators, "coverage": plot_coverage,
             "matrix": plot_full_matrix, "frequencies": plot_encoding_frequencies}
    if args.audit_only:
        audit_existing(args.confirm_visual_review)
    elif args.only:
        funcs[args.only]()
        print(json.dumps(TEXT_CHECKS, ensure_ascii=False), flush=True)
    else:
        for fn in funcs.values():
            fn()
        finish()


if __name__ == "__main__":
    main()
