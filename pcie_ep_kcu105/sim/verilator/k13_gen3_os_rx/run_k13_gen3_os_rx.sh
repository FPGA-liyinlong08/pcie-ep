#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
make -C "${script_dir}" SIM_BUILD=sim_build
cp "${script_dir}/results.xml" "${script_dir}/results_baseline.xml"

if grep -q '<failure' "${script_dir}/results.xml"; then
    echo "ERROR: Gen3 ordered-set focused regression failed" >&2
    exit 1
fi

echo "K13_GEN3_OS_RX_BASELINE_PASS tests=2"
