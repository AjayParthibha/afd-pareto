#!/usr/bin/env python3
"""All results/<config>/*.json -> one CSV with per-GPU throughput and a Pareto flag."""
import csv
import json
import sys
from pathlib import Path

FIELDS = [
    "config", "shape", "concurrency", "ngpu",
    "output_tok_s", "output_tok_s_per_gpu", "total_tok_s",
    "tpot_p50_ms", "tpot_p99_ms", "ttft_p50_ms", "ttft_p99_ms",
    "completed", "pareto",
]


def load(root: Path) -> list[dict]:
    rows = []
    for meta_path in sorted(root.glob("*/*.meta.json")):
        res_path = meta_path.with_name(meta_path.name.replace(".meta.json", ".json"))
        if not res_path.exists():
            continue
        meta, res = json.loads(meta_path.read_text()), json.loads(res_path.read_text())
        out = res["output_throughput"]
        rows.append({
            "config": meta["config"], "shape": meta["shape"],
            "concurrency": meta["concurrency"], "ngpu": meta["ngpu"],
            "output_tok_s": round(out, 1),
            "output_tok_s_per_gpu": round(out / meta["ngpu"], 1),
            "total_tok_s": round(res.get("total_token_throughput", 0.0), 1),
            "tpot_p50_ms": round(res["median_tpot_ms"], 2),
            "tpot_p99_ms": round(res["p99_tpot_ms"], 2),
            "ttft_p50_ms": round(res["median_ttft_ms"], 1),
            "ttft_p99_ms": round(res["p99_ttft_ms"], 1),
            "completed": res.get("completed"),
        })
    return rows


def mark_pareto(rows: list[dict]) -> None:
    for r in rows:
        r["pareto"] = not any(
            o is not r and o["shape"] == r["shape"]
            and o["tpot_p50_ms"] <= r["tpot_p50_ms"]
            and o["output_tok_s_per_gpu"] >= r["output_tok_s_per_gpu"]
            and (o["tpot_p50_ms"] < r["tpot_p50_ms"]
                 or o["output_tok_s_per_gpu"] > r["output_tok_s_per_gpu"])
            for o in rows
        )


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "results")
    rows = load(root)
    mark_pareto(rows)
    rows.sort(key=lambda r: (r["shape"], r["config"], r["concurrency"]))
    w = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
    w.writeheader()
    w.writerows(rows)


if __name__ == "__main__":
    main()
