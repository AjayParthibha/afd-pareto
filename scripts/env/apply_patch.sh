#!/bin/bash
# Apply the A < F patch to the plugin checkout (idempotent).
set -euo pipefail
: "${PLUGIN_DIR:?source \$PSCRATCH/afd/env.sh first}"
patch=$(cd "$(dirname "$0")" && pwd)/afd-plugin-a-lt-f.patch
if git -C "$PLUGIN_DIR" apply --reverse --check "$patch" 2>/dev/null; then
  echo "A<F patch already applied"
else
  git -C "$PLUGIN_DIR" apply "$patch" && echo "A<F patch applied"
fi
git -C "$PLUGIN_DIR" diff --stat
