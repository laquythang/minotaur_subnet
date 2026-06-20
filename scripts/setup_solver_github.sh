#!/usr/bin/env bash
# Git workflow: miner code lives in minotaur_subnet/miner_solver/ (same fork as subnet SDK).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"
load_github_env

SUBNET_URL="${MINOTAUR_SUBNET_REPO_URL:-https://github.com/laquythang/minotaur_subnet}"
SUBMIT_URL="${MINER_GITHUB_REPO_URL:-$SUBNET_URL}"
BRANCH="${MINER_SOLVER_BRANCH:-miner-solver}"

echo "=== Miner GitHub workflow (minotaur_subnet only) ==="
echo "subnet fork:  $SUBNET_URL"
echo "solver path:  $SUBNET/miner_solver"
echo "submit URL:   $SUBMIT_URL"
echo "submit branch:$BRANCH (solver.py at repo root on this branch)"
echo

if [[ ! -d "$SUBNET/.git" ]]; then
  echo "ERROR: $SUBNET is not a git repo"
  exit 1
fi

if [[ ! -f "$REPO/solver.py" ]]; then
  echo "ERROR: chưa có miner_solver — chạy: $SCRIPT_DIR/setup_miner_solver.sh"
  exit 1
fi

status="$(curl -s -o /dev/null -w '%{http_code}' "$SUBNET_URL")"
if [[ "$status" == "404" ]]; then
  echo "⚠️  Fork GitHub chưa tồn tại (HTTP 404): $SUBNET_URL"
  echo "  Fork https://github.com/subnet112/minotaur_subnet → laquythang/minotaur_subnet"
  exit 1
fi
echo "[ok] GitHub repo reachable (HTTP $status)"
echo

cd "$SUBNET"
echo "Uncommitted changes (subnet repo):"
git status -sb
echo
echo "1) Commit miner code vào fork minotaur_subnet:"
echo "   cd $SUBNET"
echo "   git add miner_solver/solver.py miner_solver/strategies/dex_aggregator/*_top.py"
echo "   git commit -m \"miner: zero-score guard + routing extensions\""
echo "   git push origin develop   # hoặc branch làm việc của bạn"
echo
echo "2) Publish branch submit (validator clone root = solver layout):"
echo "   ./scripts/publish_miner_solver.sh"
echo
echo "3) Submit testnet / mainnet:"
echo "   source scripts/miner_github.env"
echo "   export MINER_SOLVER_COMMIT=\$(cat scripts/.miner_solver_commit)"
echo "   ./scripts/local_miner_step6.sh"
