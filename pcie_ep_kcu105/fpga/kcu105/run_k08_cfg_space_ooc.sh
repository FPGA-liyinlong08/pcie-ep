#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k08"
warning_allowlist="${script_dir}/k08_vivado_warning_allowlist.txt"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

if [[ "${K08_REUSE_BUILD:-0}" != "1" ]]; then
    "${vivado_bin}" -mode batch \
        -source "${script_dir}/run_k08_cfg_space_ooc.tcl" \
        -nojournal -log "${build_dir}/vivado.log"
fi

for required in vivado.log summary.txt timing_summary.rpt check_timing.rpt \
                cdc.rpt drc.rpt utilization.rpt; do
    if [[ ! -s "${build_dir}/${required}" ]]; then
        echo "错误：K08缺少Vivado产物 ${required}" >&2
        exit 1
    fi
done

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
    echo "错误：K08 Vivado日志存在Error" >&2
    exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
    echo "错误：K08 Vivado日志存在Critical Warning" >&2
    exit 1
fi

grep '^WARNING:' "${build_dir}/vivado.log" \
    | sed -n 's/^WARNING: \[\([^]]*\)\].*/\1/p' \
    | sort | uniq -c \
    | awk '{$1=$1; print $2 " " $3 " " $1}' \
    > "${build_dir}/warnings_actual.txt"
if ! diff -u "${warning_allowlist}" "${build_dir}/warnings_actual.txt"; then
    echo "错误：K08 Vivado普通Warning不符合固定Allowlist" >&2
    exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
        "${build_dir}/drc.rpt"; then
    echo "错误：K08 DRC存在Critical Warning或Error" >&2
    exit 1
fi
grep -Eq '^\|[[:space:]]*CFGBVS-1[[:space:]]*\|[[:space:]]*Warning[[:space:]]*\|.*\|[[:space:]]*1[[:space:]]*\|' \
    "${build_dir}/drc.rpt"
if ! awk -F'|' \
    '/^\|/ && $3 ~ /(Warning|Critical Warning|Error)/ && $2 !~ /CFGBVS-1/ {exit 1}' \
    "${build_dir}/drc.rpt"; then
    echo "错误：K08 DRC存在Allowlist之外的违例" >&2
    exit 1
fi

if grep -Eq 'CDC-[0-9]+[[:space:]]+(Critical|Warning)' \
        "${build_dir}/cdc.rpt"; then
    echo "错误：K08 CDC存在Warning/Critical" >&2
    exit 1
fi
# 所有同步端口都有显式input delay后，Vivado不再把异步复位入口列为CDC-9，
# 而是给出无跨域违例的确定性结论；该结论也防止空/截断报告误通过。
grep -q '^All paths are Safely Timed\.$' "${build_dir}/cdc.rpt"

grep -q '^1\. checking no_clock (0)$' "${build_dir}/check_timing.rpt"
grep -q '^4\. checking unconstrained_internal_endpoints (0)$' \
    "${build_dir}/check_timing.rpt"
grep -q '^5\. checking no_input_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^6\. checking no_output_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^10\. checking partial_input_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^11\. checking partial_output_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^K08_VIVADO_PASS$' "${build_dir}/summary.txt"
grep -q '^TNS=0\.000$' "${build_dir}/summary.txt"
grep -q '^THS=0\.000$' "${build_dir}/summary.txt"
grep -q '^TIMING_FAIL_ENDPOINTS=0$' "${build_dir}/summary.txt"
grep -Eq '^CFG_RSP_DYNAMIC=[1-9][0-9]*$' "${build_dir}/summary.txt"
grep -Eq '^BDF_DYNAMIC=[1-9][0-9]*$' "${build_dir}/summary.txt"
grep -Eq '^BAR0_DYNAMIC=[1-9][0-9]*$' "${build_dir}/summary.txt"
grep -Eq '^MSE_DYNAMIC=[1-9][0-9]*$' "${build_dir}/summary.txt"
grep -q '^BRAM=0$' "${build_dir}/summary.txt"
grep -q '^DSP=0$' "${build_dir}/summary.txt"
grep -q '^PCIE_HARD_BLOCK=0$' "${build_dir}/summary.txt"

cat "${build_dir}/summary.txt"
