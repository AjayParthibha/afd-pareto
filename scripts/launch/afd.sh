#!/bin/bash
# Launch AFD: attention on GPUs 0..A-1, FFN on A..A+F-1.  A=1 F=1 DBO=0 bash scripts/launch/afd.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"

A=${A:-1}; F=${F:-1}; ATT_TP=${ATT_TP:-1}
CAPTURE_SIZES=${CAPTURE_SIZES:-1,2,4,8,16,32,64,128}
MAX_SEQS=${MAX_SEQS:-128}; MAX_BATCHED_TOKENS=${MAX_BATCHED_TOKENS:-2048}
AFD_PORT=${AFD_PORT:-6269}

[ $((A % ATT_TP)) -eq 0 ] || { echo "A must be divisible by ATT_TP"; exit 1; }

att_gpus=$(seq -s, 0 $((A - 1)))
ffn_gpus=$(seq -s, "$A" $((A + F - 1)))

GATE=$([ "${GATE_ON_ATTN:-0}" = 1 ] && echo true || echo false)
afd_cfg() { echo "{\"afd\":{\"role\":\"$1\",\"connector\":\"P2pNcclAFDConnector\",\"host\":\"127.0.0.1\",\"port\":$AFD_PORT,\"num_attention_ranks\":$A,\"num_ffn_ranks\":$F,\"compute_gate_on_attention\":$GATE}}"; }

common=(--enable-expert-parallel --trust-remote-code
        --max-num-seqs "$MAX_SEQS" --max-num-batched-tokens "$MAX_BATCHED_TOKENS"
        $(graph_args) $(dbo_args) ${MAX_MODEL_LEN:+--max-model-len $MAX_MODEL_LEN})

echo "AFD ${A}A${F}F att_tp=$ATT_TP dbo=${DBO:-0} graph=${GRAPH:-1} | att GPUs $att_gpus, ffn GPUs $ffn_gpus"

CUDA_VISIBLE_DEVICES=$ffn_gpus ${WRAP_FFN:-} vllm serve "$MODEL_PATH" \
  --data-parallel-size "$F" --tensor-parallel-size 1 "${common[@]}" \
  --additional-config "$(afd_cfg ffn)" \
  --host 127.0.0.1 --port $((API_PORT + 1)) > "$LOG_DIR/ffn.log" 2>&1 &
ffn_pid=$!

CUDA_VISIBLE_DEVICES=$att_gpus ${WRAP_ATT:-} vllm serve "$MODEL_PATH" \
  --data-parallel-size $((A / ATT_TP)) --tensor-parallel-size "$ATT_TP" "${common[@]}" \
  --additional-config "$(afd_cfg attention)" \
  --host 127.0.0.1 --port "$API_PORT" > "$LOG_DIR/attn.log" 2>&1 &
att_pid=$!

echo "$att_pid $ffn_pid" > "$LOG_DIR/pids"
wait_ready "$LOG_DIR/attn.log" "$att_pid" "$ffn_pid"
