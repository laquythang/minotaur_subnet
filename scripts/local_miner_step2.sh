#!/usr/bin/env bash
# Bước 2 (logic_miner_top.md): zero-score guard — quote/plan never raise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

ensure_foundry_path
load_env_if_needed

echo "=== Miner Step 2: zero-score guard ==="
echo "solver repo: $REPO"
echo

[[ -d "$REPO" ]] || { echo "ERROR: solver repo not found at $REPO"; exit 1; }

activate_venv
export PYTHONPATH="$REPO:$SUBNET${PYTHONPATH:+:$PYTHONPATH}"

python - <<PY
import os, sys
sys.path.insert(0, os.environ["REPO"])
from minotaur_subnet.shared.types import AppIntentDefinition, IntentState, AppIntentConfig
from minotaur_subnet.sdk.intent_solver import MarketSnapshot
from solver import SOLVER_CLASS

intent = AppIntentDefinition(
    app_id="dex", name="Dex", version="1.0.0", intent_type="swap",
    js_code="", config=AppIntentConfig(),
)
# Deliberately awkward state — guard must not raise.
state = IntentState(
    contract_address="0x0AeA6Ab70B384ADC6493d40e927ce53A7cefE035",
    chain_id=8453,
    nonce=0,
    owner="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    raw_params={
        "input_token": "0x4200000000000000000000000000000000000006",
        "output_token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "input_amount": "500000000000000",
        "min_output_amount": "1",
        "receiver": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    },
)
solver = SOLVER_CLASS()
solver.initialize({"chain_ids": [8453]})
snap = MarketSnapshot.empty(8453)

plan = solver.generate_plan(intent, state, snap)
assert plan is not None, "plan is None"
assert plan.intent_id, "missing intent_id"
assert plan.interactions, "empty interactions"
assert plan.deadline > 0, "bad deadline"
print("[ok] generate_plan returned valid structure:", plan.intent_id, "ix=", len(plan.interactions))

q = solver.quote(intent, state, snap)
assert q is not None, "quote is None"
assert int(q.estimated_output) >= 0, "bad estimated_output"
print("[ok] quote returned:", q.estimated_output, q.route_summary[:40])
PY

echo
if bench_missing_deps; then
  echo "[bench] zero-score guard + routing (limit 10) ..."
  run_bench 10 || echo "WARN: bench finished with errors (scoreIntent fork issue may still apply)"
else
  echo "[skip] bench — thiếu RPC/anvil (guard unit test above still passed)"
fi

echo
echo "=== Step 2 complete ==="
echo "Next: ./scripts/local_miner_step3.sh (pool discovery bench)"
