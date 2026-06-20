#!/usr/bin/env bash
# Publish miner_solver/ as orphan-style branch (solver.py at repo root) for validator submit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"
load_github_env

BRANCH="${MINER_SOLVER_BRANCH:-miner-solver}"
SOLVER_SRC="$SUBNET/miner_solver"
PUBLISH_REPO_URL="${MINER_GITHUB_REPO_URL:-${MINOTAUR_SUBNET_REPO_URL:-https://github.com/laquythang/minotaur_subnet}}"
COMMIT_FILE="$SUBNET/scripts/.miner_solver_commit"

echo "=== Publish miner solver for validator submit ==="
echo "source:      $SOLVER_SRC"
echo "subnet git:  $SUBNET"
echo "push branch: $BRANCH"
echo "repo URL:    $PUBLISH_REPO_URL"
echo

for f in Dockerfile solver.py README.md; do
  [[ -f "$SOLVER_SRC/$f" ]] || { echo "ERROR: missing $SOLVER_SRC/$f — chạy ./scripts/setup_miner_solver.sh"; exit 1; }
done

if [[ ! -d "$SUBNET/.git" ]]; then
  echo "ERROR: $SUBNET is not a git repo"
  exit 1
fi

worktree="$(mktemp -d)"
cleanup() {
  git -C "$SUBNET" worktree remove "$worktree" --force 2>/dev/null || true
  rm -rf "$worktree"
}
trap cleanup EXIT

cd "$SUBNET"

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git worktree add "$worktree" "$BRANCH"
else
  git worktree add -b "$BRANCH" "$worktree" HEAD
  (
    cd "$worktree"
    git rm -rf . >/dev/null 2>&1 || true
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true
  )
fi

rsync -a --delete --exclude='.git' "$SOLVER_SRC/" "$worktree/"

(
  cd "$worktree"
  git add -A
  if git diff --cached --quiet; then
    echo "[git] no file changes since last publish"
  else
    git commit -m "miner: publish solver $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  commit="$(git rev-parse HEAD)"
  echo "[git] commit=$commit"

  remote_url="$PUBLISH_REPO_URL"
  [[ "$remote_url" == *.git ]] || remote_url="${remote_url}.git"
  if git remote get-url publish >/dev/null 2>&1; then
    git remote set-url publish "$remote_url"
  else
    git remote add publish "$remote_url"
  fi
  git push -u publish "$BRANCH"
  printf '%s\n' "$commit" > "$COMMIT_FILE"
  echo
  echo "=== Publish OK ==="
  echo "MINER_SOLVER_COMMIT=$commit"
  echo "Submit với:"
  echo "  export MINER_GITHUB_REPO_URL=$PUBLISH_REPO_URL"
  echo "  export MINER_SOLVER_COMMIT=$commit"
  echo "  ./scripts/local_miner_step6.sh"
)
