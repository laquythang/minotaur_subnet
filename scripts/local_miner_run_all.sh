#!/usr/bin/env bash
# Chạy tuần tự Bước 1–6 (logic_miner_top.md) cho miner local test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_step() {
  local script="$1"
  echo
  echo "################################################################"
  echo "# $script"
  echo "################################################################"
  bash "$SCRIPT_DIR/$script"
}

run_step local_miner_step1.sh
run_step local_miner_step2.sh
run_step local_miner_step3.sh
run_step local_miner_step4.sh
run_step local_miner_step5.sh
run_step local_miner_step6.sh

echo
echo "=== All local miner steps (1–6) finished ==="
echo "Tiếp theo: Bước 7 mainnet — xem logic_miner_top.md"
