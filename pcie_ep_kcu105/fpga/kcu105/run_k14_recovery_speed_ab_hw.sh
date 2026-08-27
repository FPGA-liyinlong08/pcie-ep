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
    reboot)
        remote_action=
        test_label=TEST_C_REBOOT
        ;;
    *)
        echo "用法：$0 <d4|rp-only|reboot> [cycles]" >&2
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
    reboot_log="${capture_dir}/${stamp}_${test_label}_cycle${cycle}_reboot.log"
    analysis_log="${capture_dir}/${stamp}_${test_label}_cycle${cycle}_analysis.log"

    if [[ "${test_name}" == reboot ]]; then
        trigger_probe="k14_event_state_w"
        case "${K14_C_TRIGGER:-success}" in
            success)
                # Match Test A exactly: capture only a completed Gen3 PHY op.
                trigger_compare="eq4'h8"
                rate_compare="eq2'h2"
                ;;
            recovery)
                trigger_probe="k14_ltssm_state_w"
                # Decimal LTSSM state 18 (Recovery.Speed) is 0x12.
                trigger_compare="eq6'h12"
                rate_compare=
                ;;
            detect)
                trigger_probe="k14_ltssm_state_w"
                trigger_compare="eq6'h00"
                rate_compare=
                ;;
            *)
                echo "错误：K14_C_TRIGGER 必须是 success、recovery 或 detect" >&2
                exit 2
                ;;
        esac
    else
        trigger_probe="k14_event_state_w"
        trigger_compare="${K14_ILA_TRIGGER_COMPARE:-eq4'h8}"
        rate_compare="${K14_ILA_RATE_COMPARE-eq2'h2}"
    fi
    env K14_POST_PROGRAM_SETTLE_MS="${K14_POST_PROGRAM_SETTLE_MS:-2000}" \
        K14_ILA_TRIGGER_PROBE="${K14_ILA_TRIGGER_PROBE:-${trigger_probe}}" \
        K14_ILA_TRIGGER_COMPARE="${K14_ILA_TRIGGER_COMPARE:-${trigger_compare}}" \
        K14_ILA_RATE_COMPARE="${K14_ILA_RATE_COMPARE-${rate_compare}}" \
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

    if [[ "${test_name}" == reboot ]]; then
        ./scripts/remote_pcie_host.sh reboot | tee "${reboot_log}"
        ./scripts/remote_pcie_host.sh wait-reboot | tee -a "${reboot_log}"
        ./scripts/remote_pcie_host.sh check | tee -a "${reboot_log}"
    fi
    if [[ -n "${remote_action}" ]]; then
        ./scripts/remote_pcie_host.sh "${remote_action}" | tee "${remote_log}"
    fi
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
    if [[ "${test_name}" == reboot ]]; then
        printf 'K14_TEST_C_REBOOT_CAPTURE_PASS csv=%s\n' "${csv_path}" | \
            tee "${analysis_log}"
    else
        python3 scripts/analyze_k02_golden_trace.py "${csv_path}" | \
            tee "${analysis_log}"
    fi
    echo "K14_${test_label}_CYCLE_PASS cycle=${cycle} csv=${csv_path}"
done

echo "K14_${test_label}_PASS cycles=${cycles}"
