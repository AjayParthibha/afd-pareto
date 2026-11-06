#!/usr/bin/env python3
"""Final poster figures -> figures/poster/."""
import csv
import collections
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import make_plots as mp  # noqa: E402
plt = mp.plt
OUT = mp.FIG / "poster"
OUT.mkdir(exist_ok=True)
SURFACE, INK, INK2 = mp.SURFACE, mp.INK, mp.INK2
plt.rcParams.update({"font.size": 14, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13,
                     "legend.fontsize": 12.5, "lines.linewidth": 3, "lines.markersize": 8})


def heading(ax, text, pad=12):
    ax.set_title(text, loc="center", fontsize=17, fontweight="bold", pad=pad)


def save(fig, name):
    fig.tight_layout()
    fig.savefig(OUT / f"{name}.png", dpi=300)
    plt.close(fig)


def axes_tpot(ax):
    ax.set_xlabel("time per output token, median (ms)  →  lower is better")
    ax.set_ylabel("tokens/s per GPU  →  higher is better")
    ax.set_xscale("log")
    ax.xaxis.set_major_formatter(mp.matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:g}"))
    ax.set_xticks([5, 10, 20, 50])
    ax.xaxis.set_minor_formatter(mp.matplotlib.ticker.NullFormatter())


def n1():
    agg = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in csv.DictReader(open(mp.RES / "traces" / "breakdown.csv")):
        if not r["run"].endswith("-c128") or "mlen" in r["run"]:
            continue
        w = float(r["window_ms"])
        agg[(r["run"], r["role"])]["c"].append(100 * float(r["compute_ms"]) / w)
        agg[(r["run"], r["role"])]["w"].append(100 * (float(r["nccl_ms"]) - float(r["overlap_ms"])) / w)
        agg[(r["run"], r["role"])]["i"].append(100 * float(r["idle_ms"]) / w)
    picks = [("colo-dp4", "colo", "colocated · all GPUs"),
             ("afd-1a1f", "attn", "1A1F · attention"), ("afd-1a1f-dbo", "attn", "+DBO · attention"),
             ("afd-1a1f", "ffn", "1A1F · FFN"), ("afd-1a1f-dbo", "ffn", "+DBO · FFN"),
             ("afd-2a2f", "ffn", "2A2F · FFN"), ("afd-2a2f-dbo", "ffn", "+DBO · FFN")]
    lab, c, w, i = [], [], [], []
    for cfg, role, l in picks:
        key = next((k for k in agg if k[1] == role and f"-{cfg}-a100" in k[0]), None)
        if key:
            m = {k: sum(v) / len(v) for k, v in agg[key].items()}
            lab.append(l); c.append(m["c"]); w.append(m["w"]); i.append(m["i"])
    fig, ax = plt.subplots(figsize=(8, 5.4))
    y = list(range(len(lab)))[::-1]
    kw = dict(edgecolor=SURFACE, linewidth=2, height=0.72)
    ax.barh(y, c, color="#2a78d6", label="computing", **kw)
    ax.barh(y, w, left=c, color="#eb6834", label="waiting on other GPU (NCCL)", **kw)
    ax.barh(y, i, left=[a + b for a, b in zip(c, w)], color="#c9c8c2", label="idle", **kw)
    for yi, cv, wv, iv in zip(y, c, w, i):
        ax.text(cv - 1.5, yi, f"{cv:.0f}%", va="center", ha="right", fontsize=12, color="white")
        if wv > 8:
            ax.text(cv + wv - 1.5, yi, f"{wv:.0f}%", va="center", ha="right", fontsize=12, color="white")
        if iv > 12:
            ax.text(cv + wv + iv - 1.5, yi, f"{iv:.0f}%", va="center", ha="right", fontsize=12, color=INK)
    ax.set_yticks(y, lab)
    ax.set_xlim(0, 100)
    ax.set_xlabel("% of GPU time (Nsight Systems)")
    ax.grid(axis="y", visible=False)
    ax.legend(loc="lower left", bbox_to_anchor=(-0.02, 1.0), ncol=3, fontsize=11.5, handlelength=1.2,
              columnspacing=1.0)
    heading(ax, "Where GPU time goes  (Nsight, 128 requests)", pad=42)
    save(fig, "N1_nsight_gpu_time")


def t1(rows):
    by = {(r["config"], r["shape"], r["c"]): r["t"] for r in rows}
    splits = ["afd-1a1f", "afd-2a1f", "afd-3a1f", "afd-2a2f"]
    fig, ax = plt.subplots(figsize=(8, 5.2))
    width = 0.38
    xs = list(range(len(splits)))
    for k, (c, lab, col) in enumerate([(8, "low load (8 requests)", "#c9c8c2"), (128, "high load (128 requests)", "#2a78d6")]):
        vals = [100 * (by[(s_ + "-dbo", "short", c)] / by[(s_, "short", c)] - 1) for s_ in splits]
        bx = [x + (k - 0.5) * width for x in xs]
        ax.bar(bx, vals, width=width * 0.92, color=col, label=lab, edgecolor=SURFACE, linewidth=1.5)
        for x, v in zip(bx, vals):
            ax.text(x, v + (2 if v >= 0 else -2), f"{v:+.0f}%", ha="center", va="bottom" if v >= 0 else "top",
                    fontsize=12, color=INK)
    ax.axhline(0, color=INK2, lw=1.2)
    ax.set_xticks(xs, ["1A1F", "2A1F", "3A1F", "2A2F"])
    ax.set_ylabel("throughput change with DBO (%)")
    ax.set_ylim(-100, 40)
    ax.grid(axis="x", visible=False)
    ax.legend(loc="lower left")
    heading(ax, "Throughput change from DBO  (short prompts)")
    save(fig, "T1_dbo_effect")


def t3a():
    bars = [("in server\n(216 splits)", 748, "#eb6834"), ("standalone\n(2 splits)", 124.5, "#c9c8c2"),
            ("standalone\n(8 splits, fix)", 118.6, "#2a78d6")]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    y = list(range(len(bars)))[::-1]
    ax.barh(y, [b[1] for b in bars], color=[b[2] for b in bars], height=0.62, edgecolor=SURFACE, linewidth=2)
    for yi, (_, v, _) in zip(y, bars):
        ax.text(v + 12, yi, f"{v:.0f} µs", va="center", fontsize=14, color=INK)
    ax.set_yticks(y, [b[0] for b in bars])
    ax.set_xlim(0, 900)
    ax.grid(axis="y", visible=False)
    ax.set_xlabel("attention kernel time per call (µs)  →  lower is better")
    heading(ax, "Attention kernel: ~6× slower inside the server")
    save(fig, "T3a_attention_kernel")


def t3b(rows):
    dec = [r for r in rows if r["shape"] == "decode"]
    pre_colo = [r for r in dec if r["config"] == "colo-dp4"]
    pre_afd = mp.frontier([r for r in dec if r["config"].startswith(("afd-", "tune-"))])
    post_colo = [r for r in dec if r["config"] in ("mlen-colo-dp4", "mlen-colo-dp4-s256")]
    post_afd = mp.frontier([r for r in dec if r["config"].startswith("mlen-afd-")
                            and r["config"].split("-")[2] not in ("1a2f", "1a3f")])
    fig, ax = plt.subplots(figsize=(8, 5.2))
    for pts, lab, col, ls, mk, filled in [
            (pre_colo, "colocated, before fix", mp.COLOR["colo-dp4"], "--", "o", False),
            (post_colo, "colocated, after fix", mp.COLOR["colo-dp4"], "-", "o", True),
            (pre_afd, "best AFD, before fix", mp.COLOR["afd-1a1f"], "--", "s", False),
            (post_afd, "best AFD, after fix + re-tuning", mp.COLOR["afd-1a1f"], "-", "s", True)]:
        pts = sorted(pts, key=lambda r: r["p"])
        ax.plot([r["p"] for r in pts], [r["t"] for r in pts], linestyle=ls, marker=mk, color=col, mec=col,
                mfc=col if filled else SURFACE, mew=2, label=lab, zorder=3)
    axes_tpot(ax)
    ax.legend(loc="upper left")
    heading(ax, "Decode-heavy: before vs after the kernel fix")
    save(fig, "T3b_before_after_fix")


B1_CFGS = [("colo-dp4", "colocated DP4"), ("colo-dp2tp2", "colocated DP2·TP2"), ("colo-dp1tp4", "colocated TP4"),
           ("afd-1a1f", "AFD 1A1F"), ("afd-2a1f", "AFD 2A1F"), ("afd-2a2f", "AFD 2A2F"), ("afd-3a1f", "AFD 3A1F")]
B1_YMAX = {"short": 1400, "long": 1000}


def b1_panel(ax, rows, shape, legend=True):
    pre = [r for r in rows if not r["config"].startswith(("mlen", "tune")) and r["shape"] == shape
           and not r["config"].endswith("-dbo")]
    f = mp.frontier(pre)
    ax.step([r["p"] for r in f], [r["t"] for r in f], where="post", color=INK2, lw=12, alpha=0.13,
            solid_capstyle="round", label="Pareto frontier", zorder=1)
    for cfg, lab in B1_CFGS:
        s_ = mp.series(pre, cfg, shape)
        ax.plot([r["p"] for r in s_], [r["t"] for r in s_], "-o", color=mp.COLOR[cfg], mec=SURFACE, mew=1.5,
                lw=2.6, ms=7, label=lab, zorder=3)
    for r in mp.series(pre, "colo-dp4", shape):
        ax.annotate(f"{r['c']} req", (r["p"], r["t"]), xytext=(7, -14), textcoords="offset points", fontsize=11,
                    color=INK2)
    axes_tpot(ax)
    ax.set_xticks([5, 10, 20, 50, 100])
    ax.set_ylim(0, B1_YMAX[shape])
    if legend:
        ax.legend(loc="upper left", ncol=2, fontsize=11.5, columnspacing=1.0)


def b1(rows):
    fig, axes = plt.subplots(1, 2, figsize=(15, 6.0))
    for ax, (shape, title) in zip(axes, [("short", "Short prompts  (1024 in / 128 out)"),
                                         ("long", "Long prompts  (4096 in / 256 out)")]):
        b1_panel(ax, rows, shape, legend=(shape == "short"))
        ax.set_title(title, loc="center", fontsize=17, fontweight="bold", pad=12)
    axes[1].set_ylabel("")
    save(fig, "B1_baseline_short_long")


def t2(rows):
    dec = [r for r in rows if r["shape"] == "decode" and not r["config"].startswith("mlen")]
    by = {(r["config"], r["c"]): r for r in dec}
    tuned = [by.get(("tune-1a1f-dbo-seqs256", c)) if c == 256 else None for c in (1, 8, 32, 128, 256)]
    tuned = [t or by.get(("afd-1a1f-dbo", c)) for t, c in zip(tuned, (1, 8, 32, 128, 256))]
    tuned = [t for t in tuned if t]
    fig, ax = plt.subplots(figsize=(8, 5.2))
    for pts, lab, col, ls, mk, filled in [
            (mp.series(dec, "colo-dp4", "decode"), "colocated DP4", mp.COLOR["colo-dp4"], "-", "o", True),
            (mp.series(dec, "colo-dp1tp4", "decode"), "colocated TP4", mp.COLOR["colo-dp1tp4"], "-", "o", True),
            (mp.series(dec, "afd-1a1f", "decode"), "AFD 1A1F, default", mp.COLOR["afd-1a1f"], ":", "o", True),
            (tuned, "AFD 1A1F, tuned (DBO + 256 seqs)", mp.COLOR["afd-1a1f"], "-", "D", False)]:
        ax.plot([r["p"] for r in pts], [r["t"] for r in pts], linestyle=ls, marker=mk, color=col, mec=col,
                mfc=col if filled else SURFACE, mew=2, label=lab, zorder=3)
    for r in tuned:
        ax.annotate(f"{r['c']}", (r["p"], r["t"]), xytext=(7, 4), textcoords="offset points", fontsize=11, color=INK2)
    axes_tpot(ax)
    ax.legend(loc="upper left")
    heading(ax, "Decode-heavy prompts: default vs tuned AFD")
    save(fig, "T2_decode_tuned")


def o1(rows):
    dec = [r for r in rows if r["shape"] == "decode" and r["config"].startswith("mlen-")]
    def cfgs(*names):
        return sorted((r for r in dec if r["config"] in names), key=lambda r: r["c"])
    unmod = mp.frontier([r for r in dec if r["config"].startswith("mlen-afd-")
                         and r["config"].split("-")[2] not in ("1a2f", "1a3f")])
    fig, ax = plt.subplots(figsize=(8, 5.4))
    for pts, lab, col, ls, mk, filled in [
            (cfgs("mlen-colo-dp4", "mlen-colo-dp4-s256"), "colocated DP4", mp.COLOR["colo-dp4"], "-", "o", True),
            (sorted(unmod, key=lambda r: r["p"]), "best unmodified AFD (tuned)", INK2, "--", "s", False),
            (cfgs("mlen-afd-1a3f"), "optimized AFD 1A3F", mp.COLOR["afd-1a1f"], "-", "D", True),
            (cfgs("mlen-afd-1a2f"), "optimized AFD 1A2F", mp.COLOR["afd-2a2f"], "-", "D", True)]:
        ax.plot([r["p"] for r in pts], [r["t"] for r in pts], linestyle=ls, marker=mk, color=col, mec=col,
                mfc=col if filled else SURFACE, mew=2, label=lab, zorder=3)
    axes_tpot(ax)
    ax.legend(loc="upper left")
    heading(ax, "Preliminary: fewer attention than FFN GPUs")
    save(fig, "O1_optimization_preliminary")


def n2():
    rows = collections.defaultdict(list)
    for line in open(mp.RES / "traces" / "kernels_mlen_decode_c128.txt"):
        if not line.startswith("dsv2lite"):
            continue
        f = line.strip().split(",")
        cfg = "1a3f" if "-1a3f-" in f[0] else "1a1f-dbo"
        rows[(cfg, f[1])].append((float(f[8]), float(f[9]), float(f[10])))
    picks = [(("1a1f-dbo", "attn"), "1A1F+DBO · attention"), (("1a1f-dbo", "ffn"), "1A1F+DBO · FFN"),
             (("1a3f", "attn"), "1A3F · attention"), (("1a3f", "ffn"), "1A3F · FFN (avg of 3)")]
    lab, c, w, i = [], [], [], []
    for key, l in picks:
        v = rows[key]
        lab.append(l)
        c.append(sum(x[0] for x in v) / len(v)); w.append(sum(x[1] for x in v) / len(v)); i.append(sum(x[2] for x in v) / len(v))
    fig, ax = plt.subplots(figsize=(8, 3.9))
    y = [4.2, 3.2, 1.0, 0.0]
    kw = dict(edgecolor=SURFACE, linewidth=2, height=0.72)
    ax.barh(y, c, color="#2a78d6", label="computing", **kw)
    ax.barh(y, w, left=c, color="#eb6834", label="waiting on other GPU (NCCL)", **kw)
    ax.barh(y, i, left=[a + b for a, b in zip(c, w)], color="#c9c8c2", label="idle", **kw)
    for yi, cv, wv in zip(y, c, w):
        ax.text(cv - 1.5, yi, f"{cv:.0f}%", va="center", ha="right", fontsize=12, color="white")
        ax.text(cv + wv - 1.5, yi, f"{wv:.0f}%", va="center", ha="right", fontsize=12, color="white")
    ax.set_yticks(y, lab)
    ax.set_xlim(0, 100)
    ax.set_xlabel("% of GPU time (Nsight Systems)")
    ax.grid(axis="y", visible=False)
    ax.legend(loc="lower left", bbox_to_anchor=(-0.02, 1.0), ncol=3, fontsize=11.5, handlelength=1.2,
              columnspacing=1.0)
    heading(ax, "Nsight after the fix  (decode-heavy)", pad=42)
    save(fig, "N2_nsight_after_fix")


if __name__ == "__main__":
    rows = mp.rows_all()
    b1(rows); n1(); t1(rows); t2(rows); t3a(); t3b(rows); n2(); o1(rows)
    print(sorted(p.name for p in OUT.glob("*.png")))
