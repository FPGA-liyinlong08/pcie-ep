#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_root="${K14_BUILD_DIR:-${script_dir}/build_k14_recovery_speed_reboot}"
build_dir="${build_root}/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
export K14_RECOVERY_SPEED=1
export K14_IMPL_BUILD_DIR="${build_dir}"
export K15_GEN3_SPEED_TIMEOUT_CYCLES="${K15_GEN3_SPEED_TIMEOUT_CYCLES:-1000000}"
export K15_GEN3_EQ_TIMEOUT_CYCLES="${K15_GEN3_EQ_TIMEOUT_CYCLES:-1000000}"
if [[ -e "${build_dir}/k14_recovery_speed_ila.bit" ||
      -e "${build_dir}/k14_recovery_speed_ila.ltx" ]]; then
  echo "错误：K14输出目录已有bit/ltx，为避免覆盖请设置新的K14_BUILD_DIR：${build_dir}" >&2
  exit 73
fi
mkdir -p "${build_dir}"
cd "${project_dir}"

"${script_dir}/run_k02_ip_generation.sh"
"${vivado_bin}" -mode batch -source "${script_dir}/run_k11_gen1_release.tcl" \
  -nojournal -log "${build_dir}/vivado.log"

grep -q '^K14_RECOVERY_SPEED_IMPL_PASS$' "${build_dir}/summary.txt"
if [[ "${K14_ALLOW_TIMING_VIOLATION:-0}" == "1" ]]; then
  grep -q '^K14_ALLOW_TIMING_VIOLATION=1$' "${build_dir}/summary.txt"
else
  grep -q 'All user specified timing constraints are met\.' \
    "${build_dir}/timing_summary.rpt"
fi
if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：K14 Recovery.Speed Vivado日志存在Error" >&2
  exit 1
fi
sha256sum "${build_dir}/k14_recovery_speed_ila.bit" \
  > "${build_dir}/bitstream.sha256"
sha256sum "${build_dir}/k14_recovery_speed_ila.ltx" \
  > "${build_dir}/debug_probes.sha256"
source_commit="$(git -C "${project_dir}" rev-parse HEAD)"
bit_sha256="$(awk '{print $1}' "${build_dir}/bitstream.sha256")"
ltx_sha256="$(awk '{print $1}' "${build_dir}/debug_probes.sha256")"
{
  echo "SOURCE_COMMIT=${source_commit}"
  echo "GEN3_SPEED_TIMEOUT_CYCLES=${K15_GEN3_SPEED_TIMEOUT_CYCLES}"
  echo "GEN3_EQ_TIMEOUT_CYCLES=${K15_GEN3_EQ_TIMEOUT_CYCLES}"
  echo "PHY_PCLK_HZ=250000000"
  echo "PHY_PCLK_PERIOD_NS=4.000"
  echo "BIT_SHA256=${bit_sha256}"
  echo "LTX_SHA256=${ltx_sha256}"
  echo "BOARD_RESULT=PENDING_HARDWARE_CAPTURE"
  cat "${build_dir}/summary.txt"
} > "${build_dir}/build_evidence.txt"
cat "${build_dir}/summary.txt"
cat "${build_dir}/bitstream.sha256"
cat "${build_dir}/debug_probes.sha256"
cat "${build_dir}/build_evidence.txt"
