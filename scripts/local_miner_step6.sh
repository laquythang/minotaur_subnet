#!/usr/bin/env bash
# Bước 6 (logic_miner_top.md): bench loop + optional local testnet submit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

ensure_foundry_path
load_env_if_needed

echo "=== Miner Step 6: bench loop + testnet submit ==="
echo "solver repo: $REPO"
echo "subnet:      $SUBNET"
echo

GITHUB_REPO_URL="${MINER_GITHUB_REPO_URL:-}"
if [[ -z "$GITHUB_REPO_URL" ]]; then
  echo "[info] MINER_GITHUB_REPO_URL chưa set."
  echo "       Để submit testnet, export fork GitHub URL, ví dụ:"
  echo "       export MINER_GITHUB_REPO_URL=https://github.com/laquythang/minotaur_subnet"
  echo "       ./scripts/publish_miner_solver.sh   # tạo commit trên branch miner-solver"
  echo
fi

activate_venv

echo "[docker] rebuild image (offline build) ..."
docker build --network=none --memory=4g -t "$IMAGE" "$REPO"

echo
if bench_missing_deps; then
  echo "[bench] full loop limit 10 ..."
  run_bench 10 || echo "WARN: bench errors — kiểm tra scoreIntent / RPC"
else
  echo "[skip] bench — thiếu BASE_ALCHEMY_RPC_URL hoặc anvil"
fi

echo
echo "--- Local testnet submit (optional) ---"
if curl -sf "http://localhost:8080/health" >/dev/null 2>&1 || curl -sf "http://127.0.0.1:8080/health" >/dev/null 2>&1; then
  echo "[ok] validator API reachable on :8080"
  if [[ -z "$GITHUB_REPO_URL" ]]; then
    echo "[skip] submit — set MINER_GITHUB_REPO_URL trước"
  else
    COMMIT="$(resolve_solver_commit)"
    if [[ "$COMMIT" == "unknown" ]]; then
      echo "[skip] submit — chưa có commit publish. Chạy: ./scripts/publish_miner_solver.sh"
    else
      echo "[submit] repo=$GITHUB_REPO_URL commit=$COMMIT (branch miner-solver)"
      python -m minotaur_subnet.miner.main submit \
        --repo-url "$GITHUB_REPO_URL" \
        --commit-hash "$COMMIT" \
        --hotkey "${MINER_HOTKEY:-default}" \
        --validator-url "${VALIDATOR_URL:-http://localhost:8080}" \
        --poll || echo "WARN: submit failed — kiểm tra wallet / testnet logs"
    fi
  fi
else
  echo "[skip] testnet chưa chạy. Khởi động:"
  echo "  cd $SUBNET && make testnet-up"
  echo "  Sau đó chạy lại step 6 với MINER_GITHUB_REPO_URL nếu cần submit."
fi

echo
echo "=== Step 6 complete ==="
echo "Bước 7 (mainnet): register subnet 112 → submit https://api.minotaursubnet.com"
echo "  xem logic_miner_top.md § Bước 7 và dev_miner.md Giai đoạn 6"
