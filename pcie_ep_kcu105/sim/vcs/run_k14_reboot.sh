#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

K14_REBOOT_VCS=1 \
K11B_SKIP_SELFTEST=1 \
K11B_SIM_TIMEOUT="${K14_REBOOT_SIM_TIMEOUT:-900}" \
exec "${script_dir}/run_k11b_serial.sh"
