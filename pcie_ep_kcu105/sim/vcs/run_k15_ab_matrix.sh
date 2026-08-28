#!/usr/bin/env bash
set -u -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
dwell="${K15_AB_PRERATE_DWELL_CYCLES:-4}"
matrix_status=0

for variant in a0 a1 a2 a3; do
    case "${variant}" in
        a0) cdr=0; txeq=0 ;;
        a1) cdr=1; txeq=0 ;;
        a2) cdr=0; txeq=1 ;;
        a3) cdr=1; txeq=1 ;;
    esac
    log="${script_dir}/build/k15_ab_${variant}.log"
    echo "K15_PHY_AB_START variant=${variant} cdr=${cdr} txeq=${txeq} dwell=${dwell}"
    env K15_AB_CDR_HOLD="${cdr}" \
        K15_AB_PRERATE_TXEQ="${txeq}" \
        K15_AB_PRERATE_DWELL_CYCLES="${dwell}" \
        K15_AB_PRERATE_PRESET=4 \
        K15_VCS=1 \
        K11B_SKIP_SELFTEST=1 \
        K11B_SIM_TIMEOUT="${K15_SIM_TIMEOUT:-900}" \
        "${script_dir}/run_k15_gen3.sh" >"${log}" 2>&1
    status=$?
    if grep -q 'K15_VCS_PASS epochs=2' "${log}"; then
        echo "K15_PHY_AB_RESULT variant=${variant} result=PASS log=${log}"
    else
        echo "K15_PHY_AB_RESULT variant=${variant} result=FAIL status=${status} log=${log}"
        matrix_status=1
    fi
done

exit "${matrix_status}"
