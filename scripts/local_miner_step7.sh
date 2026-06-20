#!/usr/bin/env bash
# Bước 7 (logic_miner_top.md): mainnet — hướng dẫn (không tự động hóa wallet/mainnet).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=local_miner_common.sh
source "$SCRIPT_DIR/local_miner_common.sh"
load_github_env

SUBNET_URL="${MINOTAUR_SUBNET_REPO_URL:-https://github.com/laquythang/minotaur_subnet}"
SUBMIT_URL="${MINER_GITHUB_REPO_URL:-$SUBNET_URL}"

cat <<EOF
=== Miner Step 7: Mainnet (manual) ===

Prerequisites:
  1. Local Bước 1–6 ổn (screening + Docker + bench loop).
  2. Bittensor wallet registered on subnet 112.
  3. miner_solver/ committed + ./scripts/publish_miner_solver.sh pushed branch miner-solver.

Typical flow:

  # 1. Commit + publish solver branch
  cd $SUBNET
  git add miner_solver/solver.py miner_solver/strategies/dex_aggregator/*_top.py
  git commit -m "miner: routing extensions"
  git push origin develop
  ./scripts/publish_miner_solver.sh

  # 2. Register / verify hotkey (if not done)
  btcli wallet new_coldkey --wallet.name my-miner
  btcli wallet new_hotkey --wallet.name my-miner --wallet.hotkey default
  btcli subnet register --netuid 112 --wallet.name my-miner --wallet.hotkey default

  # 3. Submit to production API
  export MINER_GITHUB_REPO_URL=$SUBMIT_URL
  export MINER_SOLVER_COMMIT=\$(cat scripts/.miner_solver_commit)
  cd $SUBNET && source .venv/bin/activate
  python -m minotaur_subnet.miner.main submit \\
    --repo-url "\$MINER_GITHUB_REPO_URL" \\
    --commit-hash "\$MINER_SOLVER_COMMIT" \\
    --hotkey default \\
    --validator-url https://api.minotaursubnet.com \\
    --poll

  # 4. Monitor champion
  curl -s https://api.minotaursubnet.com/v1/solver/champion | python3 -m json.tool

Docs: dev_miner.md Giai đoạn 6, docs/miner/custom-solver.md

EOF

echo
echo "=== Step 7 (info only) ==="
echo "Repo submit: $SUBMIT_URL (commit từ branch miner-solver, không phải develop)"
