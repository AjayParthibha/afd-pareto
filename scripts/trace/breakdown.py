#!/usr/bin/env python3
"""Per-GPU compute / NCCL / idle time from Nsight .sqlite exports.  breakdown.py traces/<run> ..."""
import os
import sqlite3
import sys


def union(intervals):
    out = []
    for s, e in sorted(intervals):
        if out and s <= out[-1][1]:
            if e > out[-1][1]:
                out[-1][1] = e
        else:
            out.append([s, e])
    return out


def length(iv):
    return sum(e - s for s, e in iv)


def intersect(a, b):
    i = j = 0
    tot = 0
    while i < len(a) and j < len(b):
        s, e = max(a[i][0], b[j][0]), min(a[i][1], b[j][1])
        if s < e:
            tot += e - s
        if a[i][1] < b[j][1]:
            i += 1
        else:
            j += 1
    return tot


def breakdown(sqlite_path):
    con = sqlite3.connect(sqlite_path)
    rows = con.execute(
        "select k.deviceId, k.start, k.end, s.value like '%nccl%' "
        "from CUPTI_ACTIVITY_KIND_KERNEL k join StringIds s on k.shortName = s.id"
    ).fetchall()
    by_dev = {}
    for dev, s, e, is_nccl in rows:
        d = by_dev.setdefault(dev, ([], []))
        d[1 if is_nccl else 0].append((s, e))
    res = []
    for dev in sorted(by_dev):
        comp, nccl = union(by_dev[dev][0]), union(by_dev[dev][1])
        allk = union([tuple(x) for x in comp] + [tuple(x) for x in nccl])
        lo = min(x[0] for x in allk)
        hi = max(x[1] for x in allk)
        win = hi - lo
        res.append({
            "dev": dev, "window_ms": win / 1e6,
            "compute_ms": length(comp) / 1e6, "nccl_ms": length(nccl) / 1e6,
            "overlap_ms": intersect(comp, nccl) / 1e6,
            "idle_ms": (win - length(allk)) / 1e6,
        })
    return res


def main():
    print("run,role,dev,window_ms,compute_ms,nccl_ms,overlap_ms,idle_ms,compute_pct,nccl_only_pct,idle_pct")
    for run in sys.argv[1:]:
        name = os.path.basename(os.path.normpath(run))
        for role in ("attn", "ffn", "colo"):
            p = os.path.join(run, role + ".sqlite")
            if not os.path.exists(p):
                continue
            for r in breakdown(p):
                w = r["window_ms"]
                nccl_only = r["nccl_ms"] - r["overlap_ms"]
                print("%s,%s,%d,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f" % (
                    name, role, r["dev"], w, r["compute_ms"], r["nccl_ms"], r["overlap_ms"],
                    r["idle_ms"], 100 * r["compute_ms"] / w, 100 * nccl_only / w, 100 * r["idle_ms"] / w))


if __name__ == "__main__":
    main()
