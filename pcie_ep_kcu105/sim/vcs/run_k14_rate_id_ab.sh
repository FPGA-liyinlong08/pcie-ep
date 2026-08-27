#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"

for rate_id in 02 0e; do
    K14_RATE_AB_VCS=1 \
    K14_EP_TX_RATE_ID="${rate_id}" \
    K11B_SKIP_SELFTEST=1 \
    K11B_SIM_TIMEOUT="${K14_RATE_AB_SIM_TIMEOUT:-900}" \
        "${script_dir}/run_k11b_serial.sh"
done

rate02_log="${project_dir}/sim/vcs/build/k14_rate_id_02_simulate.log"
rate0e_log="${project_dir}/sim/vcs/build/k14_rate_id_0e_simulate.log"
rate02_result="$(grep 'K14_RATE_ID_CAPTURE_PASS' "${rate02_log}" | tail -n 1)"
rate0e_result="$(grep 'K14_RATE_ID_CAPTURE_PASS' "${rate0e_log}" | tail -n 1)"

echo "K14_RATE_ID_AB_RESULT rate02: ${rate02_result}"
echo "K14_RATE_ID_AB_RESULT rate0e: ${rate0e_result}"
echo "K14_RATE_ID_AB_VCS_PASS"
