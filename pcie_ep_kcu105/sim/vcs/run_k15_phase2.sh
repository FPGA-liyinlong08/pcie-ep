#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

K15_VCS=1 \
K15_PHASE2_ONLY=1 \
K11B_SKIP_SELFTEST=1 \
K11B_SIM_TIMEOUT="${K15_SIM_TIMEOUT:-900}" \
exec "${script_dir}/run_k11b_serial.sh"
