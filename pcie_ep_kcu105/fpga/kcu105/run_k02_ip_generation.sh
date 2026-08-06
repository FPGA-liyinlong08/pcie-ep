#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k02"
xci_path="${script_dir}/ip/pcie_phy_x1_gen3/pcie_phy_x1_gen3.xci"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

run_generation() {
    "${vivado_bin}" -mode batch \
        -source "${script_dir}/generate_k02_pcie_phy.tcl" \
        -nojournal \
        -log "${build_dir}/ip_generation.log"
}

# 连续生成两次并比较原始 XCI；路径、属性顺序或隐式默认值漂移都会失败。
run_generation
first_sha="$(sha256sum "${xci_path}" | awk '{print $1}')"
run_generation
second_sha="$(sha256sum "${xci_path}" | awk '{print $1}')"

if [[ "${first_sha}" != "${second_sha}" ]]; then
    echo "错误：K02 XCI 连续生成指纹不一致" >&2
    echo "第一次：${first_sha}" >&2
    echo "第二次：${second_sha}" >&2
    exit 1
fi

# 固定会影响 VCS 行为的生成模型参数。Receiver Detect 在数字模型中被强制
# 判定为存在接收端，因此该用例验证控制/状态时序，不代表模拟电气终端检测。
sim_top="${script_dir}/ip/pcie_phy_x1_gen3/sim/pcie_phy_x1_gen3.v"
gt_channel="${script_dir}/ip/pcie_phy_x1_gen3/ip_0/sim/pcie_phy_x1_gen3_gt_gthe3_channel_wrapper.v"
grep -Fq '.PHY_ASYNC_EN("FALSE")' "${sim_top}"
grep -Fq '.GTHE3_CHANNEL_SIM_RECEIVER_DETECT_PASS       ("TRUE")' "${gt_channel}"
grep -Fq '.GTHE3_CHANNEL_SIM_RESET_SPEEDUP              ("TRUE")' "${gt_channel}"

grep -q '^K02_IP_GENERATION_PASS$' "${build_dir}/ip_generation_summary.txt"
printf 'xci_sha256=%s\n' "${second_sha}" >> "${build_dir}/ip_generation_summary.txt"
printf '%s\n' \
    'MODEL.PHY_ASYNC_EN=FALSE' \
    'MODEL.SIM_RECEIVER_DETECT_PASS=TRUE' \
    'MODEL.SIM_RESET_SPEEDUP=TRUE' \
    >> "${build_dir}/ip_generation_summary.txt"
cat "${build_dir}/ip_generation_summary.txt"
