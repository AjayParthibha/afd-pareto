#!/bin/bash
# Post-fix tuning of unmodified AFD (DBO off, 2A2F curve, 512 requests).
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
export MAX_MODEL_LEN=4400 MAX_SEQS=256 CAPTURE_SIZES=1,2,4,8,16,32,64,128,256
F="grep --line-buffered -E ^(AFD|colocated|READY|POINT|POINTS|==.measure)|Output.token.throughput|Median.TPOT"
plan=(
  "SYSTEM=afd A=2 F=2 CONFIG=mlen-afd-2a2f-s256 POINTS='decode:1 decode:8 decode:128 decode:256 decode:512'"
  "SYSTEM=afd A=2 F=1 CONFIG=mlen-afd-2a1f POINTS='decode:128 decode:256'"
  "SYSTEM=afd A=3 F=1 CONFIG=mlen-afd-3a1f POINTS='decode:128 decode:256'"
  "SYSTEM=afd A=2 F=2 DBO=1 DBO_DECODE_THRESHOLD=32 CONFIG=mlen-afd-2a2f-dbo-t32 POINTS='decode:128 decode:256'"
  "SYSTEM=colocated N=4 TP=1 CONFIG=mlen-colo-dp4-s256 POINTS='decode:512'"
)
echo "SWEEP TUNE2 start $(date -Is) on $(hostname)"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  eval "env $line bash scripts/bench/run_point.sh" 2>&1 | $F
done
echo "SWEEP TUNE2 DONE $(date -Is)"
