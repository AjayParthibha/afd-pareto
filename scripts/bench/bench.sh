#!/bin/bash
# One benchmark point against a running server -> results/<CONFIG>/<SHAPE>_c<CONC>.json
set -euo pipefail
: "${MODEL_PATH:?source \$PSCRATCH/afd/env.sh first}"
: "${CONFIG:?set CONFIG, e.g. afd-2a2f-dbo or colo-dp4}"
: "${NGPU:?set NGPU (GPUs used by this config)}"
SHAPE=${SHAPE:-short}; CONC=${CONC:-32}
API_PORT=${API_PORT:-18305}
RESULTS=${RESULTS:-$PWD/results}

case "$SHAPE" in
  short) IN=1024; OUT=128 ;;
  long)  IN=4096; OUT=256 ;;
  decode) IN=128; OUT=512 ;; 
  *) echo "unknown SHAPE $SHAPE"; exit 1 ;;
esac
N=$(( CONC * 8 > 32 ? CONC * 8 : 32 ))
out_dir=$RESULTS/$CONFIG; mkdir -p "$out_dir"
name=${SHAPE}_c${CONC}

run() {
  local n=$1; shift
  vllm bench serve --host 127.0.0.1 --port "$API_PORT" --model "$MODEL_PATH" \
    --trust-remote-code --dataset-name random \
    --random-input-len "$IN" --random-output-len "$OUT" --ignore-eos --seed 0 \
    --num-prompts "$n" --request-rate inf --max-concurrency "$CONC" \
    --percentile-metrics ttft,tpot,itl,e2el --metric-percentiles 50,90,99 "$@"
}

echo "== warmup ($((CONC * 2)) prompts)"
run $((CONC * 2)) > "$out_dir/${name}.warmup.log" 2>&1
echo "== measure $CONFIG $SHAPE conc=$CONC ($N prompts)"
run "$N" --save-result --result-dir "$out_dir" --result-filename "${name}.json" | tee "$out_dir/${name}.log"

cat > "$out_dir/${name}.meta.json" <<EOF
{"config": "$CONFIG", "ngpu": $NGPU, "shape": "$SHAPE", "input_len": $IN, "output_len": $OUT,
 "concurrency": $CONC, "num_prompts": $N, "host": "$(hostname)", "date": "$(date -Is)",
 "knobs": {"A": "${A:-}", "F": "${F:-}", "DBO": "${DBO:-}", "GRAPH": "${GRAPH:-}",
           "MAX_SEQS": "${MAX_SEQS:-}", "MAX_BATCHED_TOKENS": "${MAX_BATCHED_TOKENS:-}",
           "CAPTURE_SIZES": "${CAPTURE_SIZES:-}"}}
EOF
