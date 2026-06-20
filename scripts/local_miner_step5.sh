#!/usr/bin/env bash
# Bước 5 (logic_miner_top.md): split routing — widen pools for large orders.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

ensure_foundry_path
load_env_if_needed

echo "=== Miner Step 5: split routing (split_routing_top) ==="
echo "solver repo: $REPO"
echo

activate_venv
export PYTHONPATH="$REPO:$SUBNET${PYTHONPATH:+:$PYTHONPATH}"

python - <<PY
import os, sys
sys.path.insert(0, os.environ["REPO"])
from strategies.dex_aggregator.split_routing_top import SPLIT_THRESHOLD_WEI
print(f"[ok] SPLIT_THRESHOLD_WEI = {SPLIT_THRESHOLD_WEI} ({SPLIT_THRESHOLD_WEI/1e18:.4f} WETH)")
print("[info] orders >= threshold trigger extra pool discovery before generate_plan")
PY

echo
if bench_missing_deps; then
  echo "[bench] limit 10 (includes medium scenarios if manifest has them) ..."
  run_bench 10 || echo "WARN: bench errors"
else
  echo "[skip] bench — cần RPC + anvil"
fi

echo
echo "=== Step 5 complete ==="
echo "Next: ./scripts/local_miner_step6.sh (testnet submit loop)"
