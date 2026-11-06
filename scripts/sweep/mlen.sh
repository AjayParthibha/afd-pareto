#!/bin/bash
# Rerun key points with --max-model-len 4400 (attention-kernel fix) + one trace.
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
export MAX_MODEL_LEN=4400
D="decode:1 decode:8 decode:32 decode:128 decode:256"
plan=(
  "SYSTEM=colocated N=4 TP=1 CONFIG=mlen-colo-dp4 POINTS='$D short:32 short:128 short:256'"
  "SYSTEM=afd A=1 F=1 DBO=1 MAX_SEQS=256 CAPTURE_SIZES=1,2,4,8,16,32,64,128,256 CONFIG=mlen-afd-1a1f-dbo-seqs256 POINTS='$D short:32 short:128 short:256'"
  "SYSTEM=afd A=2 F=1 DBO=1 DBO_DECODE_THRESHOLD=32 CONFIG=mlen-afd-2a1f-dbo-t32 POINTS='decode:32 decode:128 decode:256'"
  "SYSTEM=afd A=1 F=1 DBO=0 CONFIG=mlen-afd-1a1f POINTS='decode:1 decode:8 decode:32 decode:128'"
  "SYSTEM=colocated N=4 TP=4 CONFIG=mlen-colo-tp4 POINTS='decode:1 decode:8 decode:32'"
  "SYSTEM=afd A=3 F=1 DBO=1 DBO_DECODE_THRESHOLD=32 CONFIG=mlen-afd-3a1f-dbo-t32 POINTS='decode:128 decode:256'"
  "SYSTEM=afd A=2 F=2 DBO=0 CONFIG=mlen-afd-2a2f POINTS='decode:128 decode:256'"
)
echo "SWEEP MLEN start $(date -Is) on $(hostname), ${#plan[@]} launches"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  eval "env $line bash scripts/bench/run_point.sh" 2>&1 | grep --line-buffered -E "^(AFD|colocated|READY|LAUNCH|POINT|POINTS|== measure)|Output token throughput|Median TPOT"
done
echo "--- $(date +%T) verification trace (1A1F+DBO decode c128)"
TRACES=$PWD/traces SYSTEM=afd A=1 F=1 DBO=1 SHAPE=decode CONC=128 NAME=dsv2lite-vllm032-afd-1a1f-dbo-mlen4400-a100x2-decode-c128 \
  bash scripts/trace/trace_point.sh 2>&1 | tail -3
echo "SWEEP MLEN DONE $(date -Is)"
