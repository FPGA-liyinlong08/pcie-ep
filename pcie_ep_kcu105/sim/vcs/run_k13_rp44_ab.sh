#!/usr/bin/env bash
set -euo pipefail

# Run the existing self-developed EP against the official Ultrascale Gen3
# Integrated Block RP sources (Vivado 4.4 demo) without changing the default
# XDMA 4.1 baseline selected by run_k11b_serial.sh.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
demo_dir="${K13_RP44_DEMO:-/home/wx/Documents/PCIe/pcie3_ultrascale_0_ex}"
official_imports="${demo_dir}/imports"
baseline_imports="${K11B_RP_BASELINE_IMPORTS:-/home/wx/Documents/XDMA/xdma_dec_250922/imports}"

for required in \
    "${official_imports}/pcie3_uscale_rp_core_top.v" \
    "${official_imports}/pcie3_uscale_rp_top.v" \
    "${official_imports}/xilinx_pcie_uscale_rp.v" \
    "${baseline_imports}/pci_exp_usrapp_cfg.v" \
    "${baseline_imports}/pci_exp_usrapp_com.v" \
    "${baseline_imports}/pci_exp_usrapp_rx.v" \
    "${baseline_imports}/pci_exp_usrapp_tx.v"; do
    test -s "${required}" || {
        echo "missing RP44 A/B input: ${required}" >&2
        exit 64
    }
done

stage_dir="$(mktemp -d /tmp/pcie_k13_rp44_imports.XXXXXX)"
cleanup() { rm -rf "${stage_dir}"; }
trap cleanup EXIT

# Keep the current user-app/testbench contract, but replace all three RP
# wrapper files with the matching 4.4 set.  Mixing only one of these files
# creates false interface errors (cfg_ext_* and AXI ready width changes).
cp "${official_imports}/pcie3_uscale_rp_core_top.v" "${stage_dir}/"
cp "${official_imports}/pcie3_uscale_rp_top.v" "${stage_dir}/"
cp "${official_imports}/xilinx_pcie_uscale_rp.v" "${stage_dir}/"
for name in \
    board_common.vh pci_exp_expect_tasks.vh tests.vh sample_tests.vh \
    pci_exp_usrapp_cfg.v pci_exp_usrapp_com.v pci_exp_usrapp_rx.v pci_exp_usrapp_tx.v; do
    cp "${baseline_imports}/${name}" "${stage_dir}/"
done

echo "K13_RP44_AB_IMPORTS=${stage_dir}"
echo "K13_RP44_AB_DEMO=${demo_dir}"
echo "K13_RP44_AB_VERSION=$(sed -n 's#^// Version    : ##p' "${stage_dir}/pcie3_uscale_rp_core_top.v" | head -n1)"

export K11B_RP_IMPORTS="${stage_dir}"
export K13_ENABLE="${K13_ENABLE:-1}"
export K13_VCS_RETRAIN="${K13_VCS_RETRAIN:-1}"
export K13_RXEQ_BOOTSTRAP="${K13_RXEQ_BOOTSTRAP:-0}"
export K13_RXEQ_TWO_PASS="${K13_RXEQ_TWO_PASS:-1}"
export K11B2_MODE="${K11B2_MODE:-1}"
export K11B_SKIP_SELFTEST="${K11B_SKIP_SELFTEST:-1}"

exec "${script_dir}/run_k11b_serial.sh"
