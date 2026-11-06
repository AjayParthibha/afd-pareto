#!/usr/bin/env python3
"""Per-GPU kernel time by category + top kernels from Nsight .sqlite exports.  kernels.py [--top N] traces/<run> ..."""
import os
import re
import sqlite3
import sys

# first match wins
CATS = [
    ("nccl", r"nccl"),
    ("moe_experts", r"fused_moe|moe_align|topk|moe_sum|silu_and_mul"),
    ("attention", r"mla|flash|attn|attention|decode_kernel|_fwd_kernel|_fwd_grouped_kernel|reshape_and_cache|rotary|rope"),
    ("gemm", r"gemm|cutlass|xmma|ampere_|sm80|cublas|nvjet|splitk|matmul"),
    ("norm", r"norm"),
    ("sampling", r"sample|softmax|argmax|top_k|top_p|gumbel|penalt"),
]


def cat_of(name):
    n = name.lower()
    for c, pat in CATS:
        if re.search(pat, n):
            return c
    return "other"


def analyze(path, top):
    con = sqlite3.connect(path)
    rows = con.execute(
        "select k.deviceId, k.start, k.end, s.value "
        "from CUPTI_ACTIVITY_KIND_KERNEL k join StringIds s on k.shortName = s.id"
    ).fetchall()
    devs = {}
    for dev, s, e, name in rows:
        d = devs.setdefault(dev, {"lo": s, "hi": e, "cat": {}, "k": {}, "n": 0})
        d["lo"] = min(d["lo"], s)
        d["hi"] = max(d["hi"], e)
        dur = e - s
        c = cat_of(name)
        d["cat"][c] = d["cat"].get(c, 0) + dur
        kk = d["k"].setdefault(name, [0, 0])
        kk[0] += dur
        kk[1] += 1
        d["n"] += 1
    out = []
    for dev in sorted(devs):
        d = devs[dev]
        win = float(d["hi"] - d["lo"])
        busy = sum(v for c, v in d["cat"].items() if c != "nccl")
        tops = sorted(d["k"].items(), key=lambda x: -x[1][0])[:top]
        out.append((dev, win, d, busy, tops))
    return out


def main():
    args = sys.argv[1:]
    top = 8
    if args and args[0] == "--top":
        top = int(args[1])
        args = args[2:]
    cats = [c for c, _ in CATS] + ["other"]
    for run in args:
        name = os.path.basename(os.path.normpath(run))
        for role in ("attn", "ffn", "colo"):
            p = os.path.join(run, role + ".sqlite")
            if not os.path.exists(p):
                continue
            for dev, win, d, busy, tops in analyze(p, top):
                print("\n== %s  %s  gpu%d  window %.0f ms  kernels %d  mean non-nccl %.1f us" % (
                    name, role, dev, win / 1e6, d["n"],
                    busy / 1e3 / max(1, d["n"] - sum(v[1] for k, v in d["k"].items() if "nccl" in k.lower()))))
                print("   " + "  ".join("%s %.1f%%" % (c, 100 * d["cat"].get(c, 0) / win) for c in cats))
                for kname, (t, n) in tops:
                    print("   %6.1f%%  n=%-7d %7.1f us  [%s] %s" % (
                        100 * t / win, n, t / 1e3 / n, cat_of(kname), kname[:90]))


if __name__ == "__main__":
    main()
