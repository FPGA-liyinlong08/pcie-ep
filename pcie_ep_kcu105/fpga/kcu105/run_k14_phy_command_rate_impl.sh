#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k14_phy_command_rate"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
export K14_COMMAND_RATE=1
export K02_PHY_CTRL_WAIT_AFTER_READY_NS="${K02_PHY_CTRL_WAIT_AFTER_READY_NS:-2000000000}"
mkdir -p "${build_dir}"
cd "${project_dir}"

"${script_dir}/run_k02_ip_generation.sh"
"${vivado_bin}" -mode batch -source "${script_dir}/run_k02_impl.tcl" \
    -nojournal -log "${build_dir}/impl.log"

if grep -Eq '^ERROR:|^CRITICAL WARNING:' "${build_dir}/impl.log"; then
    echo "错误：K14 PHY command rate实现日志存在Error/Critical Warning" >&2
    exit 1
fi
if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
    "${build_dir}/drc.rpt"; then
    echo "错误：K14 PHY command rate DRC失败" >&2
    exit 1
fi
grep -q '^K14_PHY_COMMAND_RATE_IMPL_PASS$' "${build_dir}/impl_summary.txt"
cat "${build_dir}/impl_summary.txt"
