#!/bin/bash
# GSM8K correctness via the plugin's E2E runner (colocated vs AFD).
set -uo pipefail
: "${PLUGIN_DIR:?source \$PSCRATCH/afd/env.sh first}"
export AFD_GSM8K_LIMIT=${AFD_GSM8K_LIMIT:-128}
OUT=${OUT:-$PWD/results/gsm8k}
SCENARIOS=${SCENARIOS:-"baseline-graph afd-v2-eager-1a1f afd-v2-graph-1a1f"}
mkdir -p "$OUT"

devices_for() {
  case "$1" in
    baseline-graph) echo "--attention-devices 0,1,2,3" ;;
    *1a1f)          echo "--attention-devices 0 --ffn-devices 1" ;;
    *2a1f)          echo "--attention-devices 0,1 --ffn-devices 2" ;;
    *)              echo "--attention-devices 0,1 --ffn-devices 2,3" ;;
  esac
}

cd "$PLUGIN_DIR"
export PYTHONPATH=$PLUGIN_DIR${PYTHONPATH:+:$PYTHONPATH}
for s in $SCENARIOS; do
  echo "=== $s"
  python tests/e2e/runner.py --model "$MODEL_PATH" --device-backend gpu --scenario "$s" \
    $(devices_for "$s") --gsm8k-output-path "$OUT/$s" \
    --api-port-base 18000 --afd-port 6239 --common-vllm-arg=--trust-remote-code \
    > "$OUT/$s.log" 2>&1
  rc=$?
  echo "$s exit=$rc"; grep -E "gsm8k|strict-match|flexible-extract|PASSED|FAILED" "$OUT/$s.log" | tail -4
  bash "$(dirname "$0")/../launch/stop.sh" >/dev/null 2>&1 || true
done
