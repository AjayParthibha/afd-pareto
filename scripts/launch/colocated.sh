#!/bin/bash
# Launch colocated vLLM (DP/TP + expert parallel) on N GPUs.  N=4 TP=1 bash scripts/launch/colocated.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"

N=${N:-4}; TP=${TP:-1}
MAX_SEQS=${MAX_SEQS:-128}; MAX_BATCHED_TOKENS=${MAX_BATCHED_TOKENS:-2048}
CAPTURE_SIZES=${CAPTURE_SIZES:-1,2,4,8,16,32,64,128}
[ $((N % TP)) -eq 0 ] || { echo "N must be divisible by TP"; exit 1; }

case "${GRAPH:-1}" in
  1) gargs=() ;;
  decode) gargs=($(GRAPH=1 graph_args)) ;;
  0) gargs=(--enforce-eager) ;;
esac

echo "colocated N=$N DP=$((N / TP)) TP=$TP graph=${GRAPH:-1}"
CUDA_VISIBLE_DEVICES=$(seq -s, 0 $((N - 1))) ${WRAP:-} vllm serve "$MODEL_PATH" \
  --data-parallel-size $((N / TP)) --tensor-parallel-size "$TP" --enable-expert-parallel \
  --trust-remote-code --max-num-seqs "$MAX_SEQS" --max-num-batched-tokens "$MAX_BATCHED_TOKENS" \
  "${gargs[@]}" ${MAX_MODEL_LEN:+--max-model-len $MAX_MODEL_LEN} --host 127.0.0.1 --port "$API_PORT" > "$LOG_DIR/colocated.log" 2>&1 &
pid=$!
echo "$pid" > "$LOG_DIR/pids"
wait_ready "$LOG_DIR/colocated.log" "$pid"
