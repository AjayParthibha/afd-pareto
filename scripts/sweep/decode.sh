#!/bin/bash
# Decode-heavy sweep (C) and AFD tuning pass (D).  bash scripts/sweep/decode.sh C|D
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
GRID="decode:1 decode:8 decode:32 decode:128 decode:256"

case "${1:?C or D}" in
  C) plan=(
      "SYSTEM=colocated N=4 TP=1"
      "SYSTEM=colocated N=4 TP=4"
      "SYSTEM=afd A=1 F=1 DBO=0"
      "SYSTEM=afd A=1 F=1 DBO=1"
      "SYSTEM=afd A=2 F=1 DBO=1 DBO_DECODE_THRESHOLD=32 CONFIG=afd-2a1f-dbo-t32"
    ) ;;
  D) T="decode:32 decode:128 short:32 short:128"
     plan=(
      "SYSTEM=afd A=2 F=1 DBO=0"
      "SYSTEM=afd A=1 F=1 DBO=1 GATE_ON_ATTN=1 CONFIG=tune-1a1f-dbo-gateattn POINTS='$T'"
      "SYSTEM=afd A=1 F=1 DBO=1 DBO_DECODE_THRESHOLD=8 CONFIG=tune-1a1f-dbo-t8 POINTS='$T'"
      "SYSTEM=afd A=1 F=1 DBO=1 MAX_SEQS=256 CAPTURE_SIZES=1,2,4,8,16,32,64,128,256 CONFIG=tune-1a1f-dbo-seqs256 POINTS='decode:128 decode:256 short:256'"
      "SYSTEM=afd A=2 F=1 DBO=1 ATT_TP=2 CONFIG=tune-2a1f-dbo-atttp2 POINTS='$T'"
      "SYSTEM=afd A=2 F=1 DBO=1 GATE_ON_ATTN=1 CONFIG=tune-2a1f-dbo-gateattn POINTS='$T'"
      "SYSTEM=afd A=2 F=1 DBO=1 DBO_DECODE_THRESHOLD=8 CONFIG=tune-2a1f-dbo-t8 POINTS='$T'"
    ) ;;
esac

echo "SWEEP DECODE-$1 start $(date -Is) on $(hostname), ${#plan[@]} launches"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  eval "env POINTS=\"\$GRID\" $line bash scripts/bench/run_point.sh" 2>&1 | grep --line-buffered -E "^(AFD|colocated|READY|LAUNCH|POINT|POINTS|== measure)|Output token throughput|Median TPOT"
done
echo "SWEEP DECODE-$1 DONE $(date -Is)"
