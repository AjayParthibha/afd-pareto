#!/bin/bash
# One-time setup on a Perlmutter login node: uv, pinned afd-plugin, venv, weights.
set -euo pipefail

AFD_ROOT=${AFD_ROOT:-$PSCRATCH/afd}
PLUGIN_COMMIT=${PLUGIN_COMMIT:-21f8ae7e1b2eb4b31bdff7d49dd98199a29f5dca}
MODEL_ID=deepseek-ai/DeepSeek-V2-Lite

mkdir -p "$AFD_ROOT"/{bin,cache,hf}
export UV_CACHE_DIR=$AFD_ROOT/cache/uv
export UV_PYTHON_INSTALL_DIR=$AFD_ROOT/cache/python
export HF_HOME=$AFD_ROOT/hf
export PATH=$AFD_ROOT/bin:$PATH

echo "== [1/4] uv"
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$AFD_ROOT/bin" UV_NO_MODIFY_PATH=1 sh
fi
uv --version

echo "== [2/4] afd-plugin @ $PLUGIN_COMMIT"
if [ ! -d "$AFD_ROOT/afd-plugin" ]; then
  git clone https://github.com/vllm-project/afd-plugin.git "$AFD_ROOT/afd-plugin"
fi
git -C "$AFD_ROOT/afd-plugin" fetch -q origin
git -C "$AFD_ROOT/afd-plugin" checkout -q "$PLUGIN_COMMIT"

echo "== [3/4] venv with vllm==0.32.0 + plugin"
cd "$AFD_ROOT/afd-plugin"
export UV_PROJECT_ENVIRONMENT=$AFD_ROOT/venv
uv sync --python 3.12 --group dev --group e2e-tests --extra vllm
"$AFD_ROOT/venv/bin/python" -c "import vllm, afd_plugin; print('vllm', vllm.__version__, '| afd_plugin ok')"

echo "== [4/4] weights + gsm8k"
HFCLI=$AFD_ROOT/venv/bin/hf; [ -x "$HFCLI" ] || HFCLI=$AFD_ROOT/venv/bin/huggingface-cli
"$HFCLI" download "$MODEL_ID" --local-dir "$AFD_ROOT/models/DeepSeek-V2-Lite"
"$AFD_ROOT/venv/bin/python" -c 'from datasets import load_dataset; load_dataset("openai/gsm8k", "main")'

cat > "$AFD_ROOT/env.sh" <<EOF
export AFD_ROOT=$AFD_ROOT
export HF_HOME=$AFD_ROOT/hf
export HF_HUB_OFFLINE=1
export MODEL_PATH=$AFD_ROOT/models/DeepSeek-V2-Lite
export PLUGIN_DIR=$AFD_ROOT/afd-plugin
export VLLM_USE_V2_MODEL_RUNNER=1
# caches off \$HOME: NERSC home has no flock
export FLASHINFER_WORKSPACE_BASE=$AFD_ROOT/cache
export XDG_CACHE_HOME=$AFD_ROOT/cache/xdg
export VLLM_CACHE_ROOT=$AFD_ROOT/cache/vllm
export TRITON_CACHE_DIR=$AFD_ROOT/cache/triton
export TORCHINDUCTOR_CACHE_DIR=$AFD_ROOT/cache/inductor
export PATH=$AFD_ROOT/bin:$AFD_ROOT/venv/bin:\$PATH
EOF
echo "=== SETUP DONE ==="
