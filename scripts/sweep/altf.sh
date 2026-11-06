#!/bin/bash
# Optimization sweep: A < F splits (1A2F, 1A3F) + GSM8K + one trace.
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
bash scripts/env/apply_patch.sh
export MAX_MODEL_LEN=4400 MAX_SEQS=256 CAPTURE_SIZES=1,2,4,8,16,32,64,128,256
D="decode:1 decode:8 decode:32 decode:128 decode:256"
F="grep --line-buffered -E ^(AFD|colocated|READY|LAUNCH|POINT|POINTS|GSM8K|==.measure)|Output.token.throughput|Median.TPOT|exact_match"
echo "SWEEP ALTF start $(date -Is) on $(hostname)"
echo "--- $(date +%T) correctness: GSM8K 1A2F, 1A3F vs 1A1F (same harness)"
for af in "1 2" "1 3" "1 1"; do set -- $af
  A=$1 F=$2 SYSTEM=afd NAME=mlen-afd-${1}a${2}f bash scripts/bench/gsm8k_point.sh 2>&1 | $F
done
plan=(
  "SYSTEM=afd A=1 F=3 CONFIG=mlen-afd-1a3f POINTS='$D short:32 short:128 short:256'"
  "SYSTEM=afd A=1 F=2 CONFIG=mlen-afd-1a2f POINTS='$D'"
  "SYSTEM=afd A=1 F=1 CONFIG=mlen-afd-1a1f-seqs256 POINTS='decode:256'"
  "SYSTEM=afd A=2 F=2 CONFIG=mlen-afd-2a2f-seqs256 POINTS='decode:32'"
)
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  eval "env $line bash scripts/bench/run_point.sh" 2>&1 | $F
done
echo "--- $(date +%T) trace 1A3F decode c128"
TRACES=$PWD/traces SYSTEM=afd A=1 F=3 SHAPE=decode CONC=128 NAME=dsv2lite-vllm032-afd-1a3f-mlen4400-a100x4-decode-c128 \
  bash scripts/trace/trace_point.sh 2>&1 | tail -2
echo "SWEEP ALTF DONE $(date -Is)"
