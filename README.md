# afd-pareto

Colocated vs Attention–FFN Disaggregated (AFD) MoE serving on Perlmutter A100s (CS 5470, Team 32), built on
[vllm-project/afd-plugin](https://github.com/vllm-project/afd-plugin) (`P2pNcclAFDConnector`, pinned commit `21f8ae7e`)
with vLLM 0.32 and DeepSeek-V2-Lite.


## Layout
| Path | What |
|---|---|
| `docs/` | assignment and proposal |
| `scripts/env/` | Perlmutter setup; our plugin patch allowing fewer attention than FFN GPUs (`afd-plugin-a-lt-f.patch`) |
| `scripts/launch/` | start/stop AFD and colocated servers |
| `scripts/bench/` | one benchmark point, launch→points→stop, GSM8K accuracy, results → CSV |
| `scripts/sweep/` | every sweep we ran, in order (see below) |
| `scripts/trace/` | Nsight capture, time breakdown, per-kernel breakdown, attention-kernel micro-benchmark |
| `scripts/plots/` | `make_plots.py` → `figures/analysis/` (exploratory); `poster_plots.py` → `figures/poster/` (final) |
| `results/<config>/` | raw `vllm bench serve` JSON + run metadata per point; `summary_all.csv` = everything |
| `results/traces/` | Nsight summaries (CSV/TXT). Raw `.nsys-rep`/`.sqlite` traces are too large for git |
| `results/gsm8k/` | accuracy results |

Config naming: `afd-xAyF` = x attention GPUs, y FFN GPUs; `-dbo` = dual-batch overlap; `colo-dp4` etc. = colocated.
`mlen-*` = rerun with `--max-model-len 4400` (the attention-kernel fix); `tune-*` = single-setting tuning variants.

## Setup (once, login node)
```bash
bash scripts/env/setup_perlmutter.sh
bash scripts/env/apply_patch.sh
```

## Reproduce
```bash
salloc -N 1 -C "gpu&hbm80g" -G 4 -q interactive -t 04:00:00 -A m4999
source $PSCRATCH/afd/env.sh && cd <this repo>

bash scripts/bench/smoke_gsm8k.sh
bash scripts/sweep/sweep.sh A; bash scripts/sweep/sweep.sh B; bash scripts/sweep/fine1.sh
bash scripts/sweep/decode.sh C; bash scripts/sweep/decode.sh D
bash scripts/trace/trace_all.sh
bash scripts/sweep/mlen.sh
bash scripts/sweep/tune2.sh; bash scripts/sweep/tune3.sh A; bash scripts/sweep/tune3.sh B
bash scripts/sweep/altf.sh

python scripts/bench/collect.py results > results/summary_all.csv
.venv/bin/python scripts/plots/make_plots.py && .venv/bin/python scripts/plots/poster_plots.py
```
One point by hand: `SYSTEM=afd A=1 F=3 SHAPES=decode CONCS=128 MAX_MODEL_LEN=4400 bash scripts/bench/run_point.sh`.
