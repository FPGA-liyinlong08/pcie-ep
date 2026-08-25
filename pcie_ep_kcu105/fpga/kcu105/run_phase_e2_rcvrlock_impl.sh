#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_phase_e2_rcvrlock/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
export K14_RECOVERY_SPEED=1
export K14_PLACE_DIRECTIVE=ExtraTimingOpt
export PHASE_E2_RCVRLOCK_DEBUG=1
mkdir -p "${build_dir}"
cd "${project_dir}"

"${script_dir}/run_k02_ip_generation.sh"
"${vivado_bin}" -mode batch -source "${script_dir}/run_k11_gen1_release.tcl" \
  -nojournal -log "${build_dir}/vivado.log"

grep -q '^PHASE_E2_RCVRLOCK_IMPL_PASS$' "${build_dir}/summary.txt"
awk -F= '/^WNS=/{found=1; if ($2 < -0.060) exit 1} END{if (!found) exit 1}' \
  "${build_dir}/summary.txt"
if [[ -n "${K14_RESUME_ROUTED_DCP:-}" ]]; then
  grep -q '^K14_RESUME_ROUTED_PASS ' "${build_dir}/vivado.log"
else
  grep -q 'PHASE_E2_RCVRLOCK_ILA_INSERT_PASS probe0_width=31 probe1_width=118 probe2_width=14 probe3_width=8 depth=8192' \
    "${build_dir}/vivado.log"
fi
if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：Phase E2 RcvrLock Vivado日志存在Error" >&2
  exit 1
fi
sha256sum "${build_dir}/phase_e2_rcvrlock_ila.bit" \
  > "${build_dir}/bitstream.sha256"
cat "${build_dir}/summary.txt"
cat "${build_dir}/bitstream.sha256"
