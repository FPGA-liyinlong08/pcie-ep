#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/run_k14_recovery_speed_ab_hw.sh" reboot "${1:-1}"
