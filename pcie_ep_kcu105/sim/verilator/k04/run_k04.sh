#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
random_seed="${K04_RANDOM_SEED:-20260806}"
random_packets="${K04_RANDOM_PACKETS:-10000}"

cd "${script_dir}"
rm -f results.xml
K04_RANDOM_SEED="${random_seed}" K04_RANDOM_PACKETS="${random_packets}" \
    make SIM_BUILD=sim_build
cp results.xml results_behavioral.xml

echo "K04_VERILATOR_PASS packets=${random_packets} seed=${random_seed}"
