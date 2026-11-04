#!/bin/bash
# One Nsight-traced run (CCL-Bench layout).  SYSTEM=afd A=2 F=2 SHAPE=short CONC=32 bash scripts/trace/trace_point.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
SYSTEM=${SYSTEM:?afd or colocated}; SHAPE=${SHAPE:-short}; CONC=${CONC:-32}
case "$SHAPE" in short) IN=1024; OUT=128 ;; long) IN=4096; OUT=256 ;; decode) IN=128; OUT=512 ;; esac

if [ "$SYSTEM" = afd ]; then
  export A=${A:-1} F=${F:-1}; NGPU=$((A + F))
  cfg=afd-${A}a${F}f$([ "${DBO:-0}" = 1 ] && echo -dbo)
  sessions="afd_attn afd_ffn"
else
  export N=${N:-4} TP=${TP:-1}; NGPU=$N
  cfg=colo-dp$((N / TP))$([ "$TP" -gt 1 ] && echo "tp$TP")
  sessions="colo"
fi
NAME=${NAME:-dsv2lite-vllm032-${cfg}-a100x${NGPU}-${SHAPE}-c${CONC}}
OUT_DIR=${TRACES:-$repo/traces}/$NAME
export LOG_DIR=$OUT_DIR/logs
mkdir -p "$LOG_DIR"

NSYS_LAUNCH="--trace=cuda,nvtx --cuda-graph-trace=node --trace-fork-before-exec=true"
for s in $sessions; do nsys sessions list 2>/dev/null | grep -q " $s " && nsys shutdown --session="$s" >/dev/null 2>&1; done
if [ "$SYSTEM" = afd ]; then
  export WRAP_ATT="nsys launch --session-new=afd_attn $NSYS_LAUNCH"
  export WRAP_FFN="nsys launch --session-new=afd_ffn $NSYS_LAUNCH"
  launch=$repo/scripts/launch/afd.sh
else
  export WRAP="nsys launch --session-new=colo $NSYS_LAUNCH"
  launch=$repo/scripts/launch/colocated.sh
fi

bash "$repo/scripts/launch/stop.sh" >/dev/null 2>&1
echo "== $NAME: launching under nsys"
bash "$launch" || { bash "$repo/scripts/launch/stop.sh"; echo "TRACE FAILED $NAME (launch)"; exit 1; }

bench() {
  local n=$1; shift
  vllm bench serve --host 127.0.0.1 --port "${API_PORT:-18305}" --model "$MODEL_PATH" \
    --trust-remote-code --dataset-name random --random-input-len "$IN" --random-output-len "$OUT" \
    --ignore-eos --seed 1 --num-prompts "$n" --request-rate inf --max-concurrency "$CONC" "$@"
}
echo "== warmup"; bench $((CONC * 2)) > "$LOG_DIR/warmup.log" 2>&1

echo "== capture"
for s in $sessions; do
  role=${s#afd_}
  nsys start --session="$s" -s none --cpuctxsw=none -f true -o "$OUT_DIR/$role" --export=sqlite || echo "nsys start failed for $s"
done
bench $((CONC * 2)) --save-result --result-dir "$OUT_DIR" --result-filename latency.json > "$LOG_DIR/capture.log" 2>&1
for s in $sessions; do nsys stop --session="$s" || echo "nsys stop failed for $s"; done

bash "$repo/scripts/launch/stop.sh"
for s in $sessions; do nsys shutdown --session="$s" >/dev/null 2>&1; done

# CCL-Bench workload card
if [ "$SYSTEM" = afd ]; then
  par="    dp: $A
    tp: 1
    ep: $F
    afd: {attention_ranks: $A, ffn_ranks: $F, connector: P2pNcclAFDConnector, dbo: ${DBO:-0}}"
else
  par="    dp: $((N / TP))
    tp: $TP
    ep: $N"
fi
cat > "$OUT_DIR/$NAME.yaml" <<EOF
version: 1
description: >
  DeepSeek-V2-Lite serving on vLLM 0.32.0 ($cfg), random dataset ${IN} in / ${OUT} out,
  closed-loop concurrency $CONC. Nsight capture covers steady state after warmup
  ($((CONC * 2)) requests: prefill + $OUT decode steps each). afd-pareto, Cornell CS5470 Team 32.
hf_url: https://huggingface.co/deepseek-ai/DeepSeek-V2-Lite
trace_url: $OUT_DIR
contributor: Team 32 (afd-pareto)
contact: ''
workload:
  model:
    phase: serving
    moe: true
    granularity: model_fwd
    model_family: deepseek-v2-lite
    precision: bf16
    iteration: $((CONC * 2))
    model_arch:
      num_params: 15706484224
      num_active_params: 2400000000
      num_layers: 27
      num_heads: 16
      hidden_size: 2048
      vocab_size: 102400
      num_experts: 64
      num_shared_experts: 2
      num_experts_per_tok: 6
  data:
    batch_size: $CONC
    input_len: $IN
    output_len: $OUT
    dataset: random
  hardware:
    network_topo:
      topology: nvlink_single_node
      bandwidth_gbps: [200, 2400]
    xpu_spec:
      type: GPU
      model: nvidia_a100_sxm4_80gb
      total_count: $NGPU
      count_per_node: 4
    driver_version: cuda_13.2
Model-executor:
  framework:
    name: vllm
    version: 0.32.0
    plugin: afd-plugin@21f8ae7e
    compiler_tool_selection: cuda_graph_full_decode_only
  model_plan_parallelization:
$par
  communication_library:
    name: NCCL
    version: bundled-with-torch
  protocol_selection: [p2p]
metric_source:
  traces: [nsys]
  metrics_specific_trace: [latency.json]
EOF
ls -la "$OUT_DIR" | grep -E "nsys-rep|sqlite|json|yaml"
echo "TRACE DONE $NAME"
