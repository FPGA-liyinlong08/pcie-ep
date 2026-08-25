#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCACHE_DISABLE=1 make -C "${script_dir}" SIM_BUILD=sim_build

if grep -q '<failure' "${script_dir}/results.xml"; then
    echo "ERROR: Phase E Gen3 block regression failed" >&2
    exit 1
fi

echo "PHASE_E_GEN3_BLOCK_PASS randomized_rate_changes=1000"
