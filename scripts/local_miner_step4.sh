#!/usr/bin/env bash
# Bước 4 (logic_miner_top.md): cross-DEX — PancakeSwap V3 factory on Base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

ensure_foundry_path
load_env_if_needed

echo "=== Miner Step 4: cross-DEX (extra_dex_top) ==="
echo "solver repo: $REPO"
echo

activate_venv
export PYTHONPATH="$REPO:$SUBNET${PYTHONPATH:+:$PYTHONPATH}"

python - <<PY
import os, sys
sys.path.insert(0, os.environ["REPO"])
from strategies.dex_aggregator.extra_dex_top import EXTRA_V3_FACTORIES

for chain_id, factories in EXTRA_V3_FACTORIES.items():
    for name, addr in factories:
        print(f"[ok] extra factory chain={chain_id} {name} @ {addr[:10]}...")
PY

echo
if bench_missing_deps; then
  echo "[bench] limit 20 scenarios ..."
  run_bench 20 || echo "WARN: bench errors (lab fork / scoreIntent)"
else
  echo "[skip] bench — cần RPC + anvil"
fi

echo
echo "=== Step 4 complete ==="
echo "Next: ./scripts/local_miner_step5.sh (split routing threshold)"
