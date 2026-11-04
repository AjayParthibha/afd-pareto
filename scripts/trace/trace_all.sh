#!/bin/bash
# Traced subset: every AFD split, DBO off/on, 8 and 128 requests, plus colocated DP4.
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
plan=(
  "SYSTEM=afd A=2 F=2 DBO=0 CONC=128"
  "SYSTEM=afd A=2 F=2 DBO=1 CONC=128"
  "SYSTEM=colocated N=4 TP=1 CONC=128"
  "SYSTEM=afd A=1 F=1 DBO=0 CONC=8"
  "SYSTEM=afd A=1 F=1 DBO=1 CONC=8"
  "SYSTEM=colocated N=4 TP=1 CONC=8"
  "SYSTEM=afd A=2 F=2 DBO=0 CONC=8"
  "SYSTEM=afd A=2 F=2 DBO=1 CONC=8"
  "SYSTEM=afd A=3 F=1 DBO=0 CONC=128"
  "SYSTEM=afd A=3 F=1 DBO=1 CONC=128"
  "SYSTEM=afd A=2 F=1 DBO=0 CONC=128"
  "SYSTEM=afd A=2 F=1 DBO=1 CONC=128"
  "SYSTEM=afd A=1 F=1 DBO=0 CONC=128"
  "SYSTEM=afd A=1 F=1 DBO=1 CONC=128"
  "SYSTEM=afd A=3 F=1 DBO=0 CONC=8"
  "SYSTEM=afd A=3 F=1 DBO=1 CONC=8"
  "SYSTEM=afd A=2 F=1 DBO=0 CONC=8"
  "SYSTEM=afd A=2 F=1 DBO=1 CONC=8"
)
echo "TRACES start $(date -Is), ${#plan[@]} runs"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  env SHAPE=short $line bash scripts/trace/trace_point.sh 2>&1 | grep --line-buffered -E "^(== |TRACE|LAUNCH|READY)|nsys (start|stop) failed|\.(nsys-rep|sqlite)$"
done
echo "TRACES DONE $(date -Is)"
