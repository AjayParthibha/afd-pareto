#!/bin/bash
set -f  # JSON args contain [..]
: "${MODEL_PATH:?source \$PSCRATCH/afd/env.sh first}"
LOG_DIR=${LOG_DIR:-$PWD/logs}
API_PORT=${API_PORT:-18305}
mkdir -p "$LOG_DIR"

graph_args() {
  if [ "${GRAPH:-1}" = 1 ]; then
    local max=${CAPTURE_SIZES##*,}
    echo "--max-cudagraph-capture-size $max --compilation-config {\"cudagraph_mode\":\"FULL_DECODE_ONLY\",\"cudagraph_capture_sizes\":[${CAPTURE_SIZES}]}"
  else
    echo "--enforce-eager"
  fi
}

dbo_args() {
  if [ "${DBO:-0}" = 1 ]; then
    echo "--enable-dbo --dbo-decode-token-threshold ${DBO_DECODE_THRESHOLD:-2} --dbo-prefill-token-threshold ${DBO_PREFILL_THRESHOLD:-12}"
  fi
}

wait_ready() {
  local log=$1; shift
  local deadline=$(( $(date +%s) + ${STARTUP_TIMEOUT:-900} ))
  until grep -q "Application startup complete" "$log" 2>/dev/null; do
    for p in "$@"; do
      if ! kill -0 "$p" 2>/dev/null; then echo "LAUNCH FAILED: pid $p exited; see $LOG_DIR"; return 1; fi
    done
    if [ "$(date +%s)" -gt "$deadline" ]; then echo "LAUNCH FAILED: timeout; see $LOG_DIR"; return 1; fi
    sleep 5
  done
  echo "READY on port $API_PORT"
}
