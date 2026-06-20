#!/usr/bin/env bash
# Bootstrap miner_solver/ inside minotaur_subnet (no separate minotaur-solver clone).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

UPSTREAM_SOLVER="${MINOTAUR_SOLVER_UPSTREAM:-https://github.com/subnet112/minotaur-solver.git}"
SOLVER_DIR="$SUBNET/miner_solver"

echo "=== Setup miner_solver (inside minotaur_subnet) ==="
echo "subnet:      $SUBNET"
echo "solver dir:  $SOLVER_DIR"
echo "upstream:    $UPSTREAM_SOLVER"
echo

if [[ -f "$SOLVER_DIR/solver.py" ]] && [[ -f "$SOLVER_DIR/Dockerfile" ]]; then
  echo "[ok] miner_solver already present"
  for f in solver.py Dockerfile README.md; do
    [[ -f "$SOLVER_DIR/$f" ]] || { echo "ERROR: missing $SOLVER_DIR/$f"; exit 1; }
  done
  echo
  echo "Chỉnh sửa code tại: $SOLVER_DIR"
  echo "Commit vào fork minotaur_subnet:"
  echo "  cd $SUBNET"
  echo "  git add miner_solver/solver.py miner_solver/strategies/dex_aggregator/*_top.py"
  echo "  git commit -m \"miner: routing extensions\""
  echo "Publish branch submit (validator clone root = solver):"
  echo "  ./scripts/publish_miner_solver.sh"
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[fetch] cloning upstream baseline (shallow) ..."
git clone --depth 1 "$UPSTREAM_SOLVER" "$tmpdir/upstream"

mkdir -p "$SOLVER_DIR"
rsync -a --delete \
  --exclude='.git' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  "$tmpdir/upstream/" "$SOLVER_DIR/"

echo "[ok] miner_solver bootstrapped from subnet112/minotaur-solver"
echo
echo "Tiếp theo:"
echo "  1. Copy/merge các file *_top.py và solver.py miner (nếu chưa có)"
echo "  2. ./scripts/local_miner_step1.sh"
echo "  3. git add miner_solver/ ... && commit trên laquythang/minotaur_subnet"
echo "  4. ./scripts/publish_miner_solver.sh  → push branch miner-solver cho submit"
