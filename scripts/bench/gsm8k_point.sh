#!/bin/bash
# GSM8K accuracy for any split.  SYSTEM=afd A=1 F=3 NAME=afd-1a3f bash scripts/bench/gsm8k_point.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${MODEL_PATH:?source \$PSCRATCH/afd/env.sh first}"
NAME=${NAME:?}; LIMIT=${LIMIT:-128}; API_PORT=${API_PORT:-18305}
OUT=${OUT:-$PWD/results/gsm8k}; mkdir -p "$OUT"
export LOG_DIR=$PWD/logs/gsm8k-$NAME; mkdir -p "$LOG_DIR"
launch=$here/../launch/$([ "${SYSTEM:?}" = afd ] && echo afd.sh || echo colocated.sh)
bash "$here/../launch/stop.sh" >/dev/null 2>&1
if ! bash "$launch"; then tail -40 "$LOG_DIR"/*.log; bash "$here/../launch/stop.sh"; echo "GSM8K FAILED $NAME (launch)"; exit 1; fi
python -m lm_eval --model local-completions \
  --model_args "model=$MODEL_PATH,base_url=http://127.0.0.1:$API_PORT/v1/completions,max_gen_toks=512,tokenized_requests=False,num_concurrent=32,tokenizer=$MODEL_PATH" \
  --tasks gsm8k --num_fewshot 8 --limit "$LIMIT" --output_path "$OUT/$NAME" > "$OUT/$NAME.log" 2>&1
rc=$?
bash "$here/../launch/stop.sh"
echo "GSM8K $NAME rc=$rc"; grep -E "exact_match" "$OUT/$NAME.log" | head -4
