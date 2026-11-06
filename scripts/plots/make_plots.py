#!/usr/bin/env python3
"""Analysis figures -> figures/analysis/, plus helpers shared with poster_plots.py."""
import csv
import collections
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RES, FIG = ROOT / "results", ROOT / "figures"
ANALYSIS = FIG / "analysis"
ANALYSIS.mkdir(parents=True, exist_ok=True)

COLOR = {
    "colo-dp4": "#2a78d6", "afd-1a1f": "#eb6834", "afd-2a1f": "#1baf7a",
    "afd-2a2f": "#eda100", "afd-3a1f": "#e87ba4", "colo-dp2tp2": "#008300",
    "colo-dp1tp4": "#6250d6",
}
LABEL = {
    "colo-dp4": "colocated DP4", "colo-dp2tp2": "colocated DP2·TP2", "colo-dp1tp4": "colocated TP4",
    "afd-1a1f": "AFD 1A1F (2 GPU)", "afd-2a1f": "AFD 2A1F (3 GPU)",
    "afd-2a2f": "AFD 2A2F (4 GPU)", "afd-3a1f": "AFD 3A1F (4 GPU)",
}
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
SHAPE_TITLE = {"short": "short: 1024 in / 128 out", "long": "long: 4096 in / 256 out", "decode": "decode-heavy: 128 in / 512 out"}

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "font.size": 10,
    "legend.frameon": False,
})


def load():
    rows = []
    for r in csv.DictReader(open(RES / "summary_all.csv")):
        if "rep" in r["config"] or r["config"].startswith("mlen-"):
            continue  # mlen-* (fixed max-model-len) runs get their own figure
        rows.append({"config": r["config"], "shape": r["shape"], "c": int(r["concurrency"]),
                     "t": float(r["output_tok_s_per_gpu"]), "p": float(r["tpot_p50_ms"])})
    return rows


def rows_all():
    out = []
    for r in csv.DictReader(open(RES / "summary_all.csv")):
        if "rep" in r["config"]:
            continue
        out.append({"config": r["config"], "shape": r["shape"], "c": int(r["concurrency"]),
                    "t": float(r["output_tok_s_per_gpu"]), "p": float(r["tpot_p50_ms"])})
    return out


def frontier(rows):
    pts = [r for r in rows if not any(
        o is not r and o["p"] <= r["p"] and o["t"] >= r["t"] and (o["p"] < r["p"] or o["t"] > r["t"])
        for o in rows)]
    return sorted(pts, key=lambda r: r["p"])


def series(rows, cfg, shape):
    return sorted((r for r in rows if r["config"] == cfg and r["shape"] == shape), key=lambda r: r["c"])


def style_axes(ax, title):
    ax.set_xlabel("median TPOT (ms)  →  lower is better")
    ax.set_ylabel("output tok/s per GPU  →  higher is better\n(<4-GPU configs: assumed replicated to 4 GPUs)")
    ax.set_title(title, loc="left", fontsize=11, color=INK)
    ax.set_xscale("log")
    ax.xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:g}"))
    ax.set_xticks([5, 10, 20, 50, 100])


def plot_frontier(ax, rows, shape):
    f = frontier([r for r in rows if r["shape"] == shape])
    ax.step([r["p"] for r in f], [r["t"] for r in f], where="post", color=INK2,
            lw=6, alpha=0.12, zorder=1, solid_capstyle="round", label="Pareto frontier (all configs)")


def pareto(rows, shape):
    fig, ax = plt.subplots(figsize=(8, 5.2))
    plot_frontier(ax, rows, shape)
    order = ["colo-dp4", "colo-dp2tp2", "colo-dp1tp4", "afd-1a1f", "afd-2a1f", "afd-2a2f", "afd-3a1f"]
    for cfg in order:
        s = series(rows, cfg, shape)
        if not s:
            continue
        ax.plot([r["p"] for r in s], [r["t"] for r in s], "-o", color=COLOR[cfg], lw=2, ms=6,
                mec=SURFACE, mew=1.5, label=LABEL[cfg], zorder=3)
    for r in series(rows, "colo-dp4", shape):  # selective direct labels: concurrency on the baseline
        ax.annotate(f"c{r['c']}", (r["p"], r["t"]), xytext=(6, -12), textcoords="offset points",
                    fontsize=8, color=INK2)
    style_axes(ax, f"Colocated vs AFD (DBO off) — {SHAPE_TITLE[shape]}")
    ax.legend(loc="upper left", fontsize=9)
    fig.text(0.01, 0.01, "Points = concurrency 1, 8, 32, 128, 256 (lines can bend back at saturation: extra requests queue, so TPOT stops rising).\nOne A100-80GB node, DeepSeek-V2-Lite, vLLM 0.32 + afd-plugin.",
             fontsize=8, color=INK2)
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    fig.savefig(ANALYSIS / f"pareto_{shape}.png", dpi=160)
    plt.close(fig)


def dbo_effect(rows, shape):
    splits = [c for c in ["afd-1a1f", "afd-2a1f", "afd-2a2f", "afd-3a1f"]
              if series(rows, c, shape) and series(rows, c + "-dbo", shape)]
    if not splits:
        return
    fig, axes = plt.subplots(1, len(splits), figsize=(3.75 * len(splits) + 0.5, 4.2), sharey=True, squeeze=False)
    axes = axes[0]
    ref = series(rows, "colo-dp4", shape)
    for ax, cfg in zip(axes, splits):
        ax.plot([r["p"] for r in ref], [r["t"] for r in ref], "-", color=GRID, lw=3, zorder=1,
                label="colocated DP4 (ref)")
        off, on = series(rows, cfg, shape), series(rows, cfg + "-dbo", shape)
        ax.plot([r["p"] for r in off], [r["t"] for r in off], "-o", color=COLOR[cfg], lw=2, ms=6,
                mec=SURFACE, mew=1.5, label="DBO off", zorder=3)
        ax.plot([r["p"] for r in on], [r["t"] for r in on], "--s", color=COLOR[cfg], lw=2, ms=6,
                mec=COLOR[cfg], mew=1.8, mfc=SURFACE, label="DBO on", zorder=3)
        for a, b in zip(off, on):  # mark large DBO regressions (direct label, not color-alone)
            if b["t"] < 0.6 * a["t"]:
                ax.annotate(f"c{b['c']}: {b['t']/a['t']:.0%} of DBO-off", (b["p"], b["t"]),
                            xytext=(6, 4), textcoords="offset points", fontsize=8, color=INK)
        style_axes(ax, LABEL[cfg])
        ax.set_ylabel("")
        ax.legend(loc="upper left", fontsize=8)
    axes[0].set_ylabel("output tok/s per GPU  →  higher is better")
    fig.suptitle(f"Effect of 2-microbatch overlap (DBO) per AFD split — {SHAPE_TITLE[shape]}   (points = concurrency 1→256)",
                 x=0.01, ha="left", fontsize=12)
    fig.tight_layout()
    fig.savefig(ANALYSIS / f"dbo_effect_{shape}.png", dpi=160)
    plt.close(fig)


def trace_breakdown():
    path = RES / "traces" / "breakdown.csv"
    if not path.exists():
        return
    agg = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in csv.DictReader(open(path)):
        if not r["run"].endswith("-c128"):
            continue
        w = float(r["window_ms"])
        nccl_only = float(r["nccl_ms"]) - float(r["overlap_ms"])
        agg[(r["run"], r["role"])]["compute"].append(100 * float(r["compute_ms"]) / w)
        agg[(r["run"], r["role"])]["nccl"].append(100 * nccl_only / w)
        agg[(r["run"], r["role"])]["idle"].append(100 * float(r["idle_ms"]) / w)
    order = ["colo-dp4", "afd-1a1f", "afd-1a1f-dbo", "afd-2a1f", "afd-2a1f-dbo",
             "afd-2a2f", "afd-2a2f-dbo", "afd-3a1f", "afd-3a1f-dbo"]
    labels, comp, nccl, idle = [], [], [], []
    for cfg in order:
        for role in ("colo", "attn", "ffn"):
            key = next((k for k in agg if k[1] == role and f"-{cfg}-a100" in k[0]), None)
            if key is None:
                continue
            m = {k: sum(v) / len(v) for k, v in agg[key].items()}
            name = cfg.replace("colo-dp4", "colocated DP4").replace("afd-", "AFD ").replace("-dbo", " +DBO").upper().replace("COLOCATED", "colocated")
            labels.append(f"{name}  ·  {'all GPUs' if role == 'colo' else role}")
            comp.append(m["compute"]); nccl.append(m["nccl"]); idle.append(m["idle"])
    fig, ax = plt.subplots(figsize=(9, 0.42 * len(labels) + 1.4))
    y = list(range(len(labels)))[::-1]
    gap = dict(edgecolor=SURFACE, linewidth=2, height=0.72)
    ax.barh(y, comp, color="#2a78d6", label="compute kernels", **gap)
    ax.barh(y, nccl, left=comp, color="#eb6834", label="NCCL send/recv/collectives (transfer + waiting)", **gap)
    ax.barh(y, idle, left=[a + b for a, b in zip(comp, nccl)], color="#c9c8c2", label="idle", **gap)
    for yi, c in zip(y, comp):
        ax.text(c - 1.5, yi, f"{c:.0f}%", va="center", ha="right", fontsize=8, color="white")
    ax.set_yticks(y, labels, fontsize=9)
    ax.set_xlim(0, 100)
    ax.set_xlabel("% of captured wall time (per GPU, averaged over GPUs of that role)")
    ax.grid(axis="y", visible=False)
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), ncol=3, fontsize=8)
    ax.set_title("Where GPU time goes — Nsight traces, short shape, concurrency 128", loc="left",
                 fontsize=11, pad=24)
    fig.tight_layout()
    fig.savefig(ANALYSIS / "trace_breakdown_c128.png", dpi=160, bbox_inches="tight")
    plt.close(fig)


def main():
    rows = load()
    shapes = sorted({r["shape"] for r in rows}, key=["short", "long", "decode"].index)
    for shape in shapes:
        pareto(rows, shape)
        dbo_effect(rows, shape)
    trace_breakdown()
    print("wrote", sorted(p.name for p in ANALYSIS.glob("*.png")))


if __name__ == "__main__":
    main()
