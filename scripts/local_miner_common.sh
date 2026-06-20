#!/usr/bin/env bash
# Shared helpers for local_miner_step*.sh (logic_miner_top.md)
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_DEFAULT_SUBNET="$(cd "$_SCRIPT_DIR/.." && pwd)"
export SUBNET="${MINOTAUR_SUBNET_ROOT:-$_DEFAULT_SUBNET}"
export REPO="${MINOTAUR_SOLVER_REPO:-${HOME}/minotaur-solver}"
# Fallback nếu chưa clone repo riêng:
if [[ ! -f "$REPO/solver.py" ]] && [[ -f "$SUBNET/miner_solver/solver.py" ]]; then
  export REPO="$SUBNET/miner_solver"
fi
unset _SCRIPT_DIR _DEFAULT_SUBNET
export IMAGE="${MINER_DOCKER_IMAGE:-my-solver:local}"
export ENV_FILE="${MINOTAUR_ENV_FILE:-$SUBNET/platform/local_testnet/.env}"
export GITHUB_ENV_FILE="${MINER_GITHUB_ENV:-$SUBNET/scripts/miner_github.env}"

load_github_env() {
  if [[ -f "$GITHUB_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$GITHUB_ENV_FILE"
    set +a
  fi
}

ensure_foundry_path() {
  command -v anvil >/dev/null 2>&1 && return
  for dir in "$HOME/.foundry/bin" "/root/.foundry/bin"; do
    if [[ -x "$dir/anvil" ]]; then
      export PATH="$dir:$PATH"
      echo "[env] added Foundry to PATH: $dir"
      return
    fi
  done
}

ensure_dex_scorer() {
  local scorer="${MINOTAUR_DEX_SCORER:-$SUBNET/scripts/fixtures/dex_aggregator_scoring.js}"
  if [[ -f "$scorer" ]]; then
    printf '%s\n' "$scorer"
    return
  fi
  echo "[env] fetching DexAggregator scoring JS (one-time cache) ..." >&2
  mkdir -p "$SUBNET/scripts/fixtures"
  python3 - "$scorer" <<'PY' >&2
import json, pathlib, sys, urllib.request
out = pathlib.Path(sys.argv[1])
apps = json.load(urllib.request.urlopen("https://api.minotaursubnet.com/v1/apps/", timeout=60))
for app in apps.get("apps", []):
    if "DexAggregator" in (app.get("name") or "") and app.get("js_code"):
        out.write_text(app["js_code"])
        print(f"[env] cached scorer -> {out} ({len(app['js_code'])} bytes)")
        sys.exit(0)
raise SystemExit("DexAggregator js_code not found on production API")
PY
  printf '%s\n' "$scorer"
}

load_env_if_needed() {
  load_github_env
  if [[ -n "${BASE_ALCHEMY_RPC_URL:-}" ]]; then
    return
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi
  echo "[env] loading BASE_ALCHEMY_RPC_URL from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

activate_venv() {
  cd "$SUBNET"
  # shellcheck disable=SC1091
  source .venv/bin/activate
}

bench_missing_deps() {
  local -a missing=()
  [[ -z "${BASE_ALCHEMY_RPC_URL:-}" ]] && missing+=("BASE_ALCHEMY_RPC_URL (export hoặc đặt trong $ENV_FILE)")
  if ! command -v anvil >/dev/null 2>&1; then
    missing+=("anvil — cài Foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[skip] scoring_lab bench — thiếu:"
    for m in "${missing[@]}"; do echo "  - $m"; done
    return 1
  fi
  if [[ "${BASE_ALCHEMY_RPC_URL:-}" == *YOUR_KEY* ]]; then
    echo "WARN: BASE_ALCHEMY_RPC_URL still contains placeholder YOUR_KEY"
    return 1
  fi
  return 0
}

resolve_solver_commit() {
  if [[ -n "${MINER_SOLVER_COMMIT:-}" ]]; then
    printf '%s\n' "$MINER_SOLVER_COMMIT"
    return 0
  fi
  local commit_file="$SUBNET/scripts/.miner_solver_commit"
  if [[ -f "$commit_file" ]]; then
    tr -d '[:space:]' < "$commit_file"
    return 0
  fi
  if git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$REPO" rev-parse HEAD
    return 0
  fi
  printf 'unknown\n'
}

run_bench() {
  local limit="${1:-3}"
  export MINOTAUR_SOLVER_OSS="$REPO"
  local dex_contract="${SCORING_LAB_DEX_CONTRACT:-0x0AeA6Ab70B384ADC6493d40e927ce53A7cefE035}"
  local dex_scorer
  dex_scorer="$(ensure_dex_scorer)"
  echo "[bench] contract=$dex_contract scorer=$(basename "$dex_scorer") limit=$limit"
  python - <<PY
import os, sys
from minotaur_subnet.harness import protocol as p
# Cold pool discovery on first fork run can exceed default plan budget (see fork.py).
p.TIMEOUTS[p.Command.QUOTE] = max(p.TIMEOUTS.get(p.Command.QUOTE, 5.0), 45.0)
p.TIMEOUTS[p.Command.GENERATE_PLAN] = max(p.TIMEOUTS.get(p.Command.GENERATE_PLAN, 30.0), 90.0)
sys.argv = [
    "scoring_lab", "bench",
    "--base-rpc", os.environ["BASE_ALCHEMY_RPC_URL"],
    "--candidate", "$REPO/solver.py",
    "--contract", "$dex_contract",
    "--scorer", "$dex_scorer",
    "--limit", "$limit",
]
from minotaur_subnet.harness.scoring_lab.cli import main
main()
PY
}
