#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
phy_build_dir="${script_dir}/build_g2_gen1_phy"
impl_build_dir="${script_dir}/build_g2_gen1/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${phy_build_dir}" "${impl_build_dir}"
cd "${project_dir}"

G2_GEN1_ONLY=1 "${vivado_bin}" -mode batch \
  -source "${script_dir}/generate_k02_pcie_phy.tcl" -nojournal \
  -log "${phy_build_dir}/ip_generation.log"
G2_GEN1_ONLY=1 "${vivado_bin}" -mode batch \
  -source "${script_dir}/run_k11b2_impl.tcl" -nojournal \
  -log "${impl_build_dir}/vivado.log"

grep -q '^G2_GEN1_PHY_GENERATION_PASS$' \
  "${phy_build_dir}/ip_generation_summary.txt"
grep -q '^G2_GEN1_CPLL_IMPL_PASS$' "${impl_build_dir}/summary.txt"
grep -q 'All user specified timing constraints are met.' \
  "${impl_build_dir}/timing_summary.rpt"
test -s "${impl_build_dir}/g2_gen1_cpll_endpoint.bit"
cat "${impl_build_dir}/summary.txt"
