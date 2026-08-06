#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_m02"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

"${project_dir}/sim/common/check_afifo_dependency.sh"
mkdir -p "${build_dir}"
cd "${project_dir}"

"${vivado_bin}" -mode batch \
    -source "${script_dir}/run_m02_checks.tcl" \
    -nojournal \
    -log "${build_dir}/vivado.log"

if grep -Eq 'CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/cdc.rpt"; then
    echo "错误：M02 report_cdc 存在 Critical CDC" >&2
    exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' "${build_dir}/drc.rpt"; then
    echo "错误：M02 report_drc 存在 Critical Warning 或 Error" >&2
    exit 1
fi

grep -q '^M02_VIVADO_PASS$' "${build_dir}/summary.txt"
cat "${build_dir}/summary.txt"

