#!/usr/bin/env bash
# Bước 1 (logic_miner_top.md): verify miner solver repo — screening + Docker smoke.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

load_env_if_needed
ensure_foundry_path

if [[ -n "${BASE_ALCHEMY_RPC_URL:-}" ]] && [[ "$BASE_ALCHEMY_RPC_URL" == *YOUR_KEY* ]]; then
  echo "WARN: BASE_ALCHEMY_RPC_URL still contains placeholder YOUR_KEY in $ENV_FILE"
  unset BASE_ALCHEMY_RPC_URL
fi

echo "=== Miner Step 1: baseline pipeline local ==="
echo "solver repo: $REPO"
echo "subnet SDK:  $SUBNET"
echo

if [[ ! -d "$REPO" ]] || [[ ! -f "$REPO/solver.py" ]]; then
  echo "ERROR: miner solver not found at $REPO"
  echo "  chạy: $SCRIPT_DIR/setup_miner_solver.sh"
  exit 1
fi

for f in Dockerfile solver.py README.md; do
  [[ -f "$REPO/$f" ]] || { echo "ERROR: missing $REPO/$f"; exit 1; }
done

grep -q '^SOLVER_CLASS' "$REPO/solver.py" || { echo "ERROR: solver.py missing SOLVER_CLASS"; exit 1; }
grep -qi 'ghcr.io/subnet112/solver-base' "$REPO/Dockerfile" || { echo "ERROR: Dockerfile missing solver-base"; exit 1; }
if grep -qiE '^\s*(CMD|ENTRYPOINT)\s' "$REPO/Dockerfile"; then
  echo "ERROR: Dockerfile must not contain CMD/ENTRYPOINT"
  exit 1
fi
echo "[ok] required files present"

activate_venv

python -c "
from minotaur_subnet.harness.screening import run_stage_1
r = run_stage_1('$REPO')
print('[screening stage 1] PASSED:', r.passed)
print(r.details)
assert r.passed, 'stage 1 failed'
"

echo
echo "[docker] building with --network=none (validator constraint) ..."
docker build --network=none --memory=4g -t "$IMAGE" "$REPO"

echo
echo "[docker] isolated import + initialize smoke ..."
docker run --rm --network=none --read-only \
  --tmpfs=/tmp:size=64m --memory=2g --cpus=1.0 \
  --entrypoint python "$IMAGE" \
  -c "
from solver import SOLVER_CLASS
s = SOLVER_CLASS()
s.initialize({'chain_ids': [8453]})
m = s.metadata()
print('class:', SOLVER_CLASS.__name__)
print('metadata:', m)
assert m.name and m.version, 'empty name/version'
"

echo
if bench_missing_deps; then
  echo "[optional] scoring_lab bench (limit 3) ..."
  run_bench 3 || echo "WARN: bench failed (check RPC / contract / scorer cache)"
fi

echo
echo "=== Step 1 complete ==="
echo "Docker image: $IMAGE"
echo "Next: ./scripts/local_miner_run_all.sh  hoặc  ./scripts/local_miner_step2.sh"
