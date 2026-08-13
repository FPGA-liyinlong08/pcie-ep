#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
vivado_bin="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}/bin"
ip_dir="${project_dir}/fpga/kcu105/ip/pcie_phy_x1_gen3"
build_dir="${project_dir}/sim/xsim/build/k13_phy_loopback"

mkdir -p "${build_dir}"
cd "${build_dir}"
rm -rf xsim.dir .Xil webtalk* xvlog.log xelab.log xsim.log

"${vivado_bin}/xvlog" --work xil_defaultlib --relax \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gthe3_channel_wrapper.v" \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gthe3_common_wrapper.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gtwizard_gthe3.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gtwizard_top.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_sync_cell.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_sync.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_phy_ff_chain.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_phy_pipeline.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_wrapper.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_clk.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_rst.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_txeq.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_rxeq.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_gtwizard_top.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_core_top.v" \
    "${ip_dir}/sim/pcie_phy_x1_gen3.v"

"${vivado_bin}/xvlog" --sv --work xil_defaultlib --relax \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/phy/kcu105_reset_ctrl.sv" \
    "${project_dir}/rtl/phy/kcu105_refclk_reset.sv" \
    "${project_dir}/rtl/phy/kcu105_pcie_phy_wrapper.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_scrambler32.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_os_tx.sv" \
    "${project_dir}/sim/xsim/k13_phy_loopback_tb.sv" \
    "${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}/data/verilog/src/glbl.v"

"${vivado_bin}/xelab" --relax --debug typical --timescale 1ps/1ps \
    -L unisims_ver -L secureip -L xpm \
    xil_defaultlib.k13_phy_loopback_tb xil_defaultlib.glbl \
    -s k13_phy_loopback_snapshot

"${vivado_bin}/xsim" k13_phy_loopback_snapshot --runall \
    --log "${build_dir}/k13_phy_loopback.log"
