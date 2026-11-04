#!/bin/bash
# Baseline grid, split across two nodes.  bash scripts/sweep/sweep.sh A|B
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"

GRID="short:1 short:8 short:32 short:128 short:256 long:1 long:8 long:32 long:128"
REP="short:32"

case "${1:?A or B}" in
  A) plan=(
      "SYSTEM=colocated N=4 TP=1"
      "SYSTEM=colocated N=4 TP=2"
      "SYSTEM=colocated N=4 TP=4"
      "SYSTEM=afd A=1 F=1 DBO=0"
      "SYSTEM=afd A=2 F=1 DBO=0"
      "SYSTEM=colocated N=4 TP=1 CONFIG=colo-dp4-rep1 POINTS=$REP"
      "SYSTEM=colocated N=4 TP=1 CONFIG=colo-dp4-rep2 POINTS=$REP"
      "SYSTEM=afd A=1 F=1 DBO=0 CONFIG=afd-1a1f-rep1 POINTS=$REP"
      "SYSTEM=afd A=1 F=1 DBO=0 CONFIG=afd-1a1f-rep2 POINTS=$REP"
    ) ;;
  B) plan=(
      "SYSTEM=afd A=2 F=2 DBO=0"
      "SYSTEM=afd A=3 F=1 DBO=0"
      "SYSTEM=afd A=1 F=1 DBO=1"
      "SYSTEM=afd A=2 F=1 DBO=1"
      "SYSTEM=afd A=2 F=2 DBO=1"
      "SYSTEM=afd A=3 F=1 DBO=1"
      "SYSTEM=afd A=2 F=2 DBO=1 CONFIG=afd-2a2f-dbo-rep1 POINTS=$REP"
      "SYSTEM=afd A=2 F=2 DBO=1 CONFIG=afd-2a2f-dbo-rep2 POINTS=$REP"
    ) ;;
esac

echo "SWEEP $1 start $(date -Is) on $(hostname), ${#plan[@]} launches"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  env POINTS="$GRID" $line bash scripts/bench/run_point.sh 2>&1 | grep --line-buffered -E "^(AFD|colocated|READY|LAUNCH|POINT|POINTS|== measure)|Output token throughput|Median TPOT"
done
echo "SWEEP $1 DONE $(date -Is)"
