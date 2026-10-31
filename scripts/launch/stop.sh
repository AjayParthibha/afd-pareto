#!/bin/bash
# Stop servers and wait until GPUs are free.
LOG_DIR=${LOG_DIR:-$PWD/logs}
if [ -f "$LOG_DIR/pids" ]; then
  for p in $(cat "$LOG_DIR/pids"); do kill -INT "$p" 2>/dev/null; done
  sleep 15
  for p in $(cat "$LOG_DIR/pids"); do pkill -KILL -P "$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
  rm -f "$LOG_DIR/pids"
fi
pkill -KILL -u "$USER" -f "vllm serve" 2>/dev/null
pkill -KILL -u "$USER" -f "VLLM::" 2>/dev/null
for _ in $(seq 30); do
  used=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | wc -l)
  [ "$used" -eq 0 ] && { echo "GPUs free"; exit 0; }
  sleep 2
done
echo "WARNING: GPU processes still present:"; nvidia-smi --query-compute-apps=pid,process_name --format=csv
exit 1
