#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k09"
warning_allowlist="${script_dir}/k09_vivado_warning_allowlist.txt"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

reuse_build="${K09_REUSE_BUILD:-0}"
summary_file="${build_dir}/summary.txt"
candidate_file="${build_dir}/summary_candidate.txt"

# 任一Shell后置门禁失败都删除摘要，避免Tcl阶段的候选结果被误认成PASS。
trap 'status=$?; if [[ ${status} -ne 0 ]]; then rm -f "${summary_file}" "${candidate_file}"; fi' EXIT

if [[ "${reuse_build}" != "1" ]]; then
    rm -f "${summary_file}" "${candidate_file}"
    "${vivado_bin}" -mode batch \
        -source "${script_dir}/run_k09_bar_axil_ooc.tcl" \
        -nojournal -log "${build_dir}/vivado.log"
    summary_to_check="${candidate_file}"
else
    summary_to_check="${summary_file}"
fi

for required in vivado.log timing_summary.rpt check_timing.rpt \
                cdc.rpt drc.rpt route_status.rpt utilization.rpt \
                timing_interface_input.rpt timing_interface_output.rpt \
                timing_interface_input_hold.rpt \
                timing_interface_output_hold.rpt \
                timing_internal_setup.rpt timing_internal_hold.rpt \
                k09_synth.dcp k09_placed.dcp k09_routed.dcp; do
    if [[ ! -s "${build_dir}/${required}" ]]; then
        echo "错误：K09缺少Vivado产物 ${required}" >&2
        exit 1
    fi
done
if [[ ! -s "${summary_to_check}" ]]; then
    echo "错误：K09缺少待签核摘要 ${summary_to_check}" >&2
    exit 1
fi

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
    echo "错误：K09 Vivado日志存在Error" >&2
    exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
    echo "错误：K09 Vivado日志存在Critical Warning" >&2
    exit 1
fi

grep '^WARNING:' "${build_dir}/vivado.log" \
    | sed -n 's/^WARNING: \[\([^]]*\)\].*/\1/p' \
    | sort | uniq -c \
    | awk '{$1=$1; print $2 " " $3 " " $1}' \
    > "${build_dir}/warnings_actual.txt"
if ! diff -u "${warning_allowlist}" "${build_dir}/warnings_actual.txt"; then
    echo "错误：K09 Vivado普通Warning不符合固定Allowlist" >&2
    exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
        "${build_dir}/drc.rpt"; then
    echo "错误：K09 DRC存在Critical Warning或Error" >&2
    exit 1
fi
grep -Eq '^\|[[:space:]]*CFGBVS-1[[:space:]]*\|[[:space:]]*Warning[[:space:]]*\|.*\|[[:space:]]*1[[:space:]]*\|' \
    "${build_dir}/drc.rpt"
if ! awk -F'|' \
    '/^\|/ && $3 ~ /(Warning|Critical Warning|Error)/ && $2 !~ /CFGBVS-1/ {exit 1}' \
    "${build_dir}/drc.rpt"; then
    echo "错误：K09 DRC存在Allowlist之外的违例" >&2
    exit 1
fi

if grep -Eq 'CDC-[0-9]+[[:space:]]+(Critical|Warning)' \
        "${build_dir}/cdc.rpt"; then
    echo "错误：K09 CDC存在Warning/Critical" >&2
    exit 1
fi
grep -q '^All paths are Safely Timed\.$' "${build_dir}/cdc.rpt"

grep -q '^1\. checking no_clock (0)$' "${build_dir}/check_timing.rpt"
grep -q '^4\. checking unconstrained_internal_endpoints (0)$' \
    "${build_dir}/check_timing.rpt"
grep -q '^5\. checking no_input_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^6\. checking no_output_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^10\. checking partial_input_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^11\. checking partial_output_delay (0)$' "${build_dir}/check_timing.rpt"
grep -Eq '^ *# of fully routed nets\.* *: *[1-9][0-9]* *:$' \
    "${build_dir}/route_status.rpt"
grep -Eq '^ *# of nets with routing errors\.* *: *0 *:$' \
    "${build_dir}/route_status.rpt"

grep -q '^K09_VIVADO_PASS$' "${summary_to_check}"
grep -q '^IMPLEMENTATION=ROUTED$' "${summary_to_check}"
grep -q '^TNS=0\.000$' "${summary_to_check}"
grep -q '^THS=0\.000$' "${summary_to_check}"
grep -q '^TIMING_FAIL_SETUP=0$' "${summary_to_check}"
grep -q '^TIMING_FAIL_HOLD=0$' "${summary_to_check}"
grep -q '^IO_DELAY_MAX_NS=1\.000$' "${summary_to_check}"
grep -q '^INPUT_TOTAL_MAX_NS=4\.000$' "${summary_to_check}"
grep -q '^INPUT_EFFECTIVE_DATA_BUDGET_NS=3\.000$' "${summary_to_check}"
grep -q '^OUTPUT_TOTAL_MAX_NS=4\.000$' "${summary_to_check}"
grep -q '^OUTPUT_EFFECTIVE_DATA_BUDGET_NS=3\.000$' "${summary_to_check}"
grep -q '^INTERFACE_INPUT_MIN_DELAY_NS=-1\.000$' "${summary_to_check}"
grep -q '^INTERFACE_OUTPUT_MIN_DELAY_NS=0\.000$' "${summary_to_check}"
grep -Eq '^INTERFACE_INPUT_SETUP_SLACK=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_OUTPUT_SETUP_SLACK=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_INPUT_DATA_PATH_NS=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_OUTPUT_DATA_PATH_NS=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_INPUT_HOLD_SLACK=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_OUTPUT_HOLD_SLACK=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_INPUT_MIN_DATA_PATH_NS=[0-9]' "${summary_to_check}"
grep -Eq '^INTERFACE_OUTPUT_MIN_DATA_PATH_NS=[0-9]' "${summary_to_check}"
grep -Eq '^INTERNAL_WNS=[0-9]' "${summary_to_check}"
grep -Eq '^INTERNAL_WHS=[0-9]' "${summary_to_check}"
grep -Eq '^BUSY_DYNAMIC=[1-9][0-9]*$' "${summary_to_check}"
grep -Eq '^AXI_AWVALID_DYNAMIC=[1-9][0-9]*$' "${summary_to_check}"
grep -Eq '^AXI_ARVALID_DYNAMIC=[1-9][0-9]*$' "${summary_to_check}"
grep -Eq '^CPL_REQ_VALID_DYNAMIC=[1-9][0-9]*$' "${summary_to_check}"
grep -Eq '^CPL_DATA_VALID_DYNAMIC=[1-9][0-9]*$' "${summary_to_check}"
grep -Eq '^PARTPIN_DYNAMIC_PORTS=[1-9][0-9]*$' "${summary_to_check}"
grep -q '^DSP=0$' "${summary_to_check}"
grep -q '^PCIE_HARD_BLOCK=0$' "${summary_to_check}"

if [[ "${reuse_build}" != "1" ]]; then
    mv "${candidate_file}" "${summary_file}"
fi
trap - EXIT
cat "${summary_file}"
