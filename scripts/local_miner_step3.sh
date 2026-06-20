#!/usr/bin/env bash
# Bước 3 (logic_miner_top.md): extended pool discovery — bench vs genesis.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

ensure_foundry_path
load_env_if_needed

echo "=== Miner Step 3: pool discovery (routing_top) ==="
echo "solver repo: $REPO"
echo

activate_venv
export PYTHONPATH="$REPO:$SUBNET${PYTHONPATH:+:$PYTHONPATH}"

python - <<PY
import os, sys
sys.path.insert(0, os.environ["REPO"])
from strategies.dex_aggregator.routing_top import EXTRA_KNOWN_POOLS, EXTRA_INTERMEDIARIES
from solver import SOLVER_CLASS

print("[ok] routing_top extra Base pools:", len(EXTRA_KNOWN_POOLS.get(8453, [])))
print("[ok] routing_top extra intermediaries:", len(EXTRA_INTERMEDIARIES.get(8453, [])))

solver = SOLVER_CLASS()
solver.initialize({"chain_ids": [8453], "rpc_urls": {8453: "http://127.0.0.1:1"}})
pools = solver._discover_pools(8453)
print("[ok] _discover_pools hook callable (offline rpc -> %d cached pools)" % len(pools))
PY

echo
if bench_missing_deps; then
  echo "[bench] compare genesis vs candidate (limit 10) ..."
  run_bench 10 || echo "WARN: bench errors — xem log scoreIntent nếu on_chain=—"
else
  echo "[skip] bench — cần BASE_ALCHEMY_RPC_URL + anvil"
fi

echo
echo "=== Step 3 complete ==="
echo "Next: ./scripts/local_miner_step4.sh (cross-DEX / extra factories)"
