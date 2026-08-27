#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
capture_dir="${script_dir}/build_k14_recovery_speed/capture"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"
server_url="${HW_SERVER_URL:-127.0.0.1:3122}"
test_name="${1:-}"
cycles="${2:-1}"

case "${test_name}" in
    d4)
        remote_action=retrain-gen3-d4
        test_label=TEST_A_D4
        ;;
    rp-only)
        remote_action=retrain-gen3-rp-only
        test_label=TEST_B_RP_ONLY
        ;;
    *)
        echo "用法：$0 <d4|rp-only> [cycles]" >&2
        exit 2
        ;;
esac
if [[ ! "${cycles}" =~ ^[1-9][0-9]*$ ]]; then
    echo "错误：循环次数必须是正整数：${cycles}" >&2
    exit 2
fi

mkdir -p "${capture_dir}"
cd "${project_dir}"

for ((cycle = 1; cycle <= cycles; cycle++)); do
    stamp="$(date +%Y%m%d_%H%M%S)"
    vivado_log="${capture_dir}/${stamp}_${test_label}_cycle${cycle}_vivado.log"
    remote_log="${capture_dir}/${stamp}_${test_label}_cycle${cycle}_remote.log"
    analysis_log="${capture_dir}/${stamp}_${test_label}_cycle${cycle}_analysis.log"

    env K14_POST_PROGRAM_SETTLE_MS="${K14_POST_PROGRAM_SETTLE_MS:-2000}" \
        K14_ILA_TRIGGER_COMPARE="${K14_ILA_TRIGGER_COMPARE:-eq4'h8}" \
        K14_ILA_RATE_COMPARE="${K14_ILA_RATE_COMPARE-eq2'h2}" \
        K14_ILA_TRIGGER_POS="${K14_ILA_TRIGGER_POS:-2048}" \
        timeout 75 "${vivado_bin}" -mode batch \
        -source fpga/kcu105/run_k14_recovery_speed_ila_hw.tcl \
        -tclargs "${server_url}" program-capture-wait \
        -nojournal -nolog >"${vivado_log}" 2>&1 &
    vivado_pid=$!

    armed=0
    for ((poll = 1; poll <= 45; poll++)); do
        if rg -q 'K14_RECOVERY_ILA_ARM_PASS' "${vivado_log}"; then
            armed=1
            break
        fi
        if ! kill -0 "${vivado_pid}" 2>/dev/null; then
            wait "${vivado_pid}" || true
            tail -n 80 "${vivado_log}" >&2
            echo "错误：${test_label} 第 ${cycle} 轮 Vivado 在 ILA arm 前退出" >&2
            exit 1
        fi
        sleep 1
    done
    if [[ "${armed}" -ne 1 ]]; then
        kill -TERM "${vivado_pid}" 2>/dev/null || true
        wait "${vivado_pid}" || true
        echo "错误：${test_label} 第 ${cycle} 轮等待 ILA arm 超时" >&2
        exit 1
    fi

    ./scripts/remote_pcie_host.sh "${remote_action}" | tee "${remote_log}"
    if ! wait "${vivado_pid}"; then
        tail -n 80 "${vivado_log}" >&2
        echo "错误：${test_label} 第 ${cycle} 轮 ILA capture 失败" >&2
        exit 1
    fi

    csv_path="$(sed -n 's/.*K14_RECOVERY_ILA_CAPTURE_PASS csv=\([^ ]*\).*/\1/p' \
        "${vivado_log}" | tail -n 1)"
    if [[ -z "${csv_path}" || ! -f "${csv_path}" ]]; then
        echo "错误：${test_label} 第 ${cycle} 轮未生成 capture CSV" >&2
        exit 1
    fi
    python3 scripts/analyze_k02_golden_trace.py "${csv_path}" | \
        tee "${analysis_log}"
    echo "K14_${test_label}_CYCLE_PASS cycle=${cycle} csv=${csv_path}"
done

echo "K14_${test_label}_PASS cycles=${cycles}"
