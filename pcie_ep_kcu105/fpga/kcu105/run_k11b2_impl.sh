#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
ila_debug="${K11B2_ILA_DEBUG:-0}"
k13_enable="${K13_ENABLE:-0}"
k13_rxeq_bootstrap="${K13_RXEQ_BOOTSTRAP:-1}"
k13_gt_rate_done_tie_high="${K13_GT_RATE_DONE_TIE_HIGH:-0}"
k13_gt_rate_done_start_pulse="${K13_GT_RATE_DONE_START_PULSE:-0}"
k13_gt_rate_done_reset_release_pulse="${K13_GT_RATE_DONE_RESET_RELEASE_PULSE:-0}"
k13_cdr_hold_recovery="${K13_CDR_HOLD_RECOVERY:-0}"
k13_gt_rate_qpll_reset_forward="${K13_GT_RATE_QPLL_RESET_FORWARD:-0}"
k13_gt_primitive_debug="${K13_GT_PRIMITIVE_DEBUG:-0}"
k13_gt_qpll_prereq_debug="${K13_GT_QPLL_PREREQ_DEBUG:-0}"
k13_gt_rate_direct_source="0"
if [[ "${k13_gt_rate_done_tie_high}" == "1" ||
      "${k13_gt_rate_done_start_pulse}" == "1" ||
      "${k13_gt_rate_done_reset_release_pulse}" == "1" ||
      "${k13_gt_rate_qpll_reset_forward}" == "1" ||
      "${k13_gt_primitive_debug}" == "1" ||
      "${k13_gt_qpll_prereq_debug}" == "1" ]]; then
  k13_gt_rate_direct_source="1"
fi
build_variant="build_k11b2"
if [[ "${ila_debug}" == "1" ]]; then
  build_variant="build_k11b2_ila"
fi
if [[ "${G9_WAIT_REMOTE_DETECT:-0}" == "1" ]]; then
  if [[ "${ila_debug}" == "1" ]]; then
    build_variant="build_g9_wait_remote_detect_ila"
  else
    build_variant="build_g9_wait_remote_detect_release"
  fi
fi
if [[ "${G10_CFG_COMPLETE:-0}" == "1" ]]; then
  build_variant="build_g10_cfg_complete_ila"
fi
if [[ "${G11_RX_PARSER:-0}" == "1" ]]; then
  build_variant="build_g11_rx_parser_ila"
fi
if [[ "${G12_ORDERED_SET:-0}" == "1" ]]; then
  if [[ "${ila_debug}" == "1" ]]; then
    build_variant="build_g12_ordered_set_ila"
  else
    build_variant="build_g12_ordered_set_release"
  fi
fi
if [[ "${G8_FAST_DETECT:-0}" == "1" ]]; then
  build_variant="build_g8_fast_detect_ila"
fi
if [[ "${G7_RX_P0_QUIET:-0}" == "1" ]]; then
  build_variant="build_g7_rxp0_ila"
fi
if [[ "${G2_GEN1_ONLY:-0}" == "1" ]]; then
  build_variant="build_g2_gen1"
fi
if [[ "${k13_enable}" == "1" ]]; then
  if [[ "${ila_debug}" == "1" ]]; then
    build_variant="build_k13_gen3_ila"
  else
    build_variant="build_k13_gen3"
  fi
  if [[ "${k13_rxeq_bootstrap}" == "0" ]]; then
    build_variant+="_rxeq_off"
  fi
  if [[ "${k13_gt_rate_done_tie_high}" == "1" ]]; then
    build_variant+="_gt_rate_done1"
  fi
  if [[ "${k13_gt_rate_done_start_pulse}" == "1" ]]; then
    build_variant+="_gt_rate_done_start"
  fi
  if [[ "${k13_gt_rate_done_reset_release_pulse}" == "1" ]]; then
    build_variant+="_gt_rate_done_reset_release"
  fi
  if [[ "${k13_cdr_hold_recovery}" == "1" ]]; then
    build_variant+="_cdr_hold"
  fi
  if [[ "${k13_gt_rate_qpll_reset_forward}" == "1" ]]; then
    build_variant+="_gt_qpllreset"
  fi
  if [[ "${k13_gt_primitive_debug}" == "1" ]]; then
    build_variant+="_gt_primitive"
  fi
fi
build_dir="${script_dir}/${build_variant}/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

if [[ "${K11B2_REUSE_BUILD:-0}" != "1" ]]; then
  "${script_dir}/run_k02_ip_generation.sh"
  "${vivado_bin}" -mode batch -source "${script_dir}/run_k11b2_impl.tcl" \
    -nojournal -log "${build_dir}/vivado.log"
fi

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：K11-B2 Vivado日志存在Error" >&2
  exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
  if [[ "${k13_gt_rate_direct_source}" != "1" ]] || \
     grep '^CRITICAL WARNING:' "${build_dir}/vivado.log" \
       | grep -Ev '\[(Common 17-741|filemgmt 20-1440)\]' \
       | grep -q .; then
    echo "错误：K11-B2 Vivado日志存在未允许的Critical Warning" >&2
    exit 1
  fi
fi

warning_ids="$(grep '^WARNING: \[' "${build_dir}/vivado.log" \
  | sed -E 's/^WARNING: \[([^]]+)\].*/\1/' | sort -u)"
expected_warning_ids="$(cat <<EOF
$(if [[ "${ila_debug}" == "1" ]]; then
  printf '%s\n' 'DRC PDCN-1569' 'DRC RTSTAT-10'
fi)
$(if [[ "${ila_debug}" == "1" || "${k13_enable}" == "1" ]]; then
  printf '%s\n' 'Route 35-328'
fi)
$(if [[ "${K11B2_ILA_RESUME:-0}" != "1" ]]; then
  printf '%s\n' \
    'Synth 8-3848' 'Synth 8-3917' 'Synth 8-6014' 'Synth 8-6779' \
    'Synth 8-7023' 'Synth 8-7071' 'Synth 8-7129'
  if [[ "${k13_gt_rate_direct_source}" != "1" ]]; then
    printf '%s\n' 'Synth 8-7080'
  fi
fi)
$(if [[ "${ila_debug}" == "1" ]]; then
  printf '%s\n' 'Timing 38-164'
  printf '%s\n' 'Timing 38-436'
fi)
Vivado 12-975
EOF
)"
expected_warning_ids="$(printf '%s\n' "${expected_warning_ids}" | sed '/^$/d' | sort -u)"
if [[ "${warning_ids}" != "${expected_warning_ids}" ]]; then
  echo "错误：K11-B2 Warning ID集合与固定allowlist不一致" >&2
  printf '实际：\n%s\n期望：\n%s\n' "${warning_ids}" "${expected_warning_ids}" >&2
  exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
  "${build_dir}/drc.rpt"; then
  echo "错误：K11-B2 DRC报告存在Critical Warning或Error" >&2
  exit 1
fi
if grep -Eq '^CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/cdc_routed.rpt"; then
  echo "错误：K11-B2 CDC报告存在Critical路径" >&2
  exit 1
fi
if [[ "${ila_debug}" != "1" && "${k13_enable}" != "1" ]]; then
  grep -q 'All user specified timing constraints are met.' \
    "${build_dir}/timing_summary.rpt"
  grep -q '^K11B2_IMPL_PASS$' "${build_dir}/summary.txt"
elif [[ "${ila_debug}" == "1" && "${k13_enable}" == "1" ]]; then
  grep -q '^K13_ILA_IMPL_PASS$' "${build_dir}/summary.txt"
elif [[ "${ila_debug}" == "1" ]]; then
  grep -q '^K11B3_ILA_IMPL_PASS$' "${build_dir}/summary.txt"
else
  grep -q '^K13_IMPL_PASS$' "${build_dir}/summary.txt"
fi
cat "${build_dir}/summary.txt"
