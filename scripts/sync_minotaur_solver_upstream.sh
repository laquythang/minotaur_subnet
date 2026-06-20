#!/usr/bin/env bash
# Refresh solver from owner upstream (subnet112/minotaur-solver).
#
#   ./scripts/sync_minotaur_solver_upstream.sh
#       → clone/update ~/minotaur-solver (layout owner, khuyến nghị)
#
#   ./scripts/sync_minotaur_solver_upstream.sh --in-repo
#       → thay miner_solver/ trong minotaur_subnet
#
#   ./scripts/sync_minotaur_solver_upstream.sh --keep-ext
#       → sau sync, khôi phục *_top.py + solver.py miner từ backup
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"

UPSTREAM="${MINOTAUR_SOLVER_UPSTREAM:-https://github.com/subnet112/minotaur-solver.git}"
IN_REPO=false
KEEP_EXT=false
for arg in "$@"; do
  case "$arg" in
    --in-repo) IN_REPO=true ;;
    --keep-ext) KEEP_EXT=true ;;
  esac
done

if $IN_REPO; then
  TARGET="$SUBNET/miner_solver"
else
  TARGET="${MINOTAUR_SOLVER_REPO:-$HOME/minotaur-solver}"
fi

BACKUP_DIR="$SUBNET/scripts/.miner_solver_backup_latest"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "=== Sync solver from owner upstream ==="
echo "upstream: $UPSTREAM"
echo "target:   $TARGET"
echo

mkdir -p "$BACKUP_DIR"
for f in solver.py \
  strategies/dex_aggregator/zero_score_guard_top.py \
  strategies/dex_aggregator/routing_top.py \
  strategies/dex_aggregator/extra_dex_top.py \
  strategies/dex_aggregator/split_routing_top.py; do
  if [[ -f "$TARGET/$f" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$TARGET/$f" "$BACKUP_DIR/$f"
  fi
done
echo "[backup] → $BACKUP_DIR"

echo "[fetch] git clone --depth 1 ..."
git clone --depth 1 "$UPSTREAM" "$tmpdir/upstream"

if [[ -d "$TARGET/.git" ]]; then
  echo "[sync] reset existing git repo ..."
  git -C "$TARGET" fetch --depth 1 origin main
  git -C "$TARGET" reset --hard origin/main
else
  rm -rf "$TARGET"
  if $IN_REPO; then
    rsync -a --delete --exclude='.git' --exclude='__pycache__' \
      "$tmpdir/upstream/" "$TARGET/"
  else
    cp -a "$tmpdir/upstream" "$TARGET"
  fi
fi

if $KEEP_EXT; then
  echo "[restore] miner extensions ..."
  for f in strategies/dex_aggregator/zero_score_guard_top.py \
    strategies/dex_aggregator/routing_top.py \
    strategies/dex_aggregator/extra_dex_top.py \
    strategies/dex_aggregator/split_routing_top.py; do
    [[ -f "$BACKUP_DIR/$f" ]] || continue
    cp "$BACKUP_DIR/$f" "$TARGET/$f"
    echo "  + $f"
  done
  if [[ -f "$BACKUP_DIR/solver.py" ]] && grep -q '_top' "$BACKUP_DIR/solver.py" 2>/dev/null; then
    cp "$BACKUP_DIR/solver.py" "$TARGET/solver.py"
    echo "  + solver.py (miner wiring)"
  fi
fi

echo
echo "=== Done ==="
echo "Path:   $TARGET"
echo "Verify: ./scripts/local_miner_step1.sh"
if ! $IN_REPO; then
  echo "Export: export MINOTAUR_SOLVER_REPO=$TARGET"
  echo "Fork:   https://github.com/subnet112/minotaur-solver → laquythang/minotaur-solver"
fi
