#!/bin/bash
# Post-fix tuning: A < F with DBO / higher load (A), 4 attention splits + NCCL protocol (B).
set -uo pipefail
cd "$(dirname "$0")/../.."
source "$PSCRATCH/afd/env.sh"
bash scripts/env/apply_patch.sh >/dev/null
export MAX_MODEL_LEN=${MAX_MODEL_LEN:-4400}
S256="MAX_SEQS=256 CAPTURE_SIZES=1,2,4,8,16,32,64,128,256"
S512="MAX_SEQS=512 CAPTURE_SIZES=1,2,4,8,16,32,64,128,256,512"
case "${1:?A or B}" in
  A) plan=(
      "SYSTEM=afd A=1 F=3 $S512 CONFIG=mlen-afd-1a3f-s512 POINTS='decode:512'"
      "SYSTEM=afd A=1 F=3 DBO=1 DBO_DECODE_THRESHOLD=64 $S512 CONFIG=mlen-afd-1a3f-dbo-t64 POINTS='decode:32 decode:128 decode:256 decode:512'"
      "SYSTEM=afd A=1 F=2 DBO=1 DBO_DECODE_THRESHOLD=64 $S512 CONFIG=mlen-afd-1a2f-dbo-t64 POINTS='decode:128 decode:256 decode:512'"
      "SYSTEM=afd A=1 F=2 $S512 CONFIG=mlen-afd-1a2f-s512 POINTS='decode:512'"
    ) ;;
  B) plan=(
      "MAX_MODEL_LEN=2048 SYSTEM=afd A=1 F=3 $S256 CONFIG=mlen2k-afd-1a3f POINTS='decode:32 decode:128 decode:256'"
      "MAX_MODEL_LEN=2048 SYSTEM=afd A=2 F=2 $S256 CONFIG=mlen2k-afd-2a2f POINTS='decode:128 decode:256 decode:512'"
      "MAX_MODEL_LEN=2048 SYSTEM=colocated N=4 TP=1 CONFIG=mlen2k-colo-dp4 POINTS='decode:32 decode:128 decode:256'"
      "NCCL_PROTO=Simple SYSTEM=afd A=1 F=3 $S256 CONFIG=mlen-afd-1a3f-ncclsimple POINTS='decode:32 decode:128'"
    ) ;;
esac
F="grep --line-buffered -E ^(AFD|colocated|READY|POINT|POINTS|==.measure)|Output.token.throughput|Median.TPOT"
echo "SWEEP TUNE3-$1 start $(date -Is) on $(hostname)"
for line in "${plan[@]}"; do
  echo "--- $(date +%T) $line"
  eval "env $line bash scripts/bench/run_point.sh" 2>&1 | $F
done
echo "SWEEP TUNE3-$1 DONE $(date -Is)"
