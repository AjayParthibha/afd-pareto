#!/bin/bash
# Long prompts at concurrency 256 for every config.
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
plan=(
  "SYSTEM=colocated N=4 TP=1"
  "SYSTEM=colocated N=4 TP=2"
  "SYSTEM=colocated N=4 TP=4"
  "SYSTEM=afd A=1 F=1 DBO=1"
  "SYSTEM=afd A=2 F=1 DBO=1"
  "SYSTEM=afd A=2 F=2 DBO=0"
  "SYSTEM=afd A=3 F=1 DBO=0"
  "SYSTEM=afd A=1 F=1 DBO=0"
  "SYSTEM=afd A=2 F=1 DBO=0"
  "SYSTEM=afd A=2 F=2 DBO=1"
  "SYSTEM=afd A=3 F=1 DBO=1"
)
echo "SWEEP FINE1 start $(date -Is) on $(hostname), ${#plan[@]} launches"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  env POINTS="long:256" $line bash scripts/bench/run_point.sh 2>&1 | grep --line-buffered -E "^(AFD|colocated|READY|LAUNCH|POINT|POINTS|== measure)|Output token throughput|Median TPOT"
done
echo "SWEEP FINE1 DONE $(date -Is)"
