#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K11B2_MODE=1 K11B2_STRESS_MODE=1 "${script_dir}/run_k11b_serial.sh"
