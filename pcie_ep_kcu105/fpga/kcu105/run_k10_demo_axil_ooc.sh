#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k10"
allowlist="${script_dir}/k10_vivado_warning_allowlist.txt"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"
summary_file="${build_dir}/summary.txt"
candidate_file="${build_dir}/summary_candidate.txt"
reuse="${K10_REUSE_BUILD:-0}"
export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"
trap 'status=$?; if [[ ${status} -ne 0 ]]; then rm -f "${summary_file}" "${candidate_file}"; fi' EXIT

if [[ "${reuse}" != "1" ]]; then
    rm -f "${summary_file}" "${candidate_file}"
    "${vivado_bin}" -mode batch \
        -source "${script_dir}/run_k10_demo_axil_ooc.tcl" \
        -nojournal -log "${build_dir}/vivado.log"
    checked_summary="${candidate_file}"
else
    checked_summary="${summary_file}"
fi

for required in vivado.log timing_summary.rpt check_timing.rpt cdc.rpt \
    drc.rpt route_status.rpt utilization.rpt timing_interface_input.rpt \
    timing_interface_output.rpt timing_interface_input_hold.rpt \
    timing_interface_output_hold.rpt k10_synth.dcp k10_placed.dcp \
    k10_routed.dcp; do
    test -s "${build_dir}/${required}"
done
test -s "${checked_summary}"
! grep -q '^ERROR:' "${build_dir}/vivado.log"
! grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"

grep '^WARNING:' "${build_dir}/vivado.log" \
    | sed -n 's/^WARNING: \[\([^]]*\)\].*/\1/p' \
    | sort | uniq -c | awk '{$1=$1; print $2 " " $3 " " $1}' \
    > "${build_dir}/warnings_actual.txt"
diff -u "${allowlist}" "${build_dir}/warnings_actual.txt"

! grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
    "${build_dir}/drc.rpt"
grep -Eq '^\|[[:space:]]*CFGBVS-1[[:space:]]*\|[[:space:]]*Warning[[:space:]]*\|.*\|[[:space:]]*1[[:space:]]*\|' \
    "${build_dir}/drc.rpt"
! grep -Eq 'CDC-[0-9]+[[:space:]]+(Critical|Warning)' "${build_dir}/cdc.rpt"
grep -q '^All paths are Safely Timed\.$' "${build_dir}/cdc.rpt"
grep -q '^1\. checking no_clock (0)$' "${build_dir}/check_timing.rpt"
grep -q '^4\. checking unconstrained_internal_endpoints (0)$' "${build_dir}/check_timing.rpt"
grep -q '^5\. checking no_input_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^6\. checking no_output_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^10\. checking partial_input_delay (0)$' "${build_dir}/check_timing.rpt"
grep -q '^11\. checking partial_output_delay (0)$' "${build_dir}/check_timing.rpt"
grep -Eq '^ *# of nets with routing errors\.* *: *0 *:$' "${build_dir}/route_status.rpt"

grep -q '^K10_VIVADO_PASS$' "${checked_summary}"
grep -q '^IMPLEMENTATION=ROUTED$' "${checked_summary}"
grep -q '^TNS=0\.000$' "${checked_summary}"
grep -q '^THS=0\.000$' "${checked_summary}"
grep -Eq '^WNS=[0-9]' "${checked_summary}"
grep -Eq '^WHS=[0-9]' "${checked_summary}"
grep -Eq '^INTERFACE_INPUT_SETUP_SLACK=[0-9]' "${checked_summary}"
grep -Eq '^INTERFACE_OUTPUT_SETUP_SLACK=[0-9]' "${checked_summary}"
grep -Eq '^INTERFACE_INPUT_HOLD_SLACK=[0-9]' "${checked_summary}"
grep -Eq '^INTERFACE_OUTPUT_HOLD_SLACK=[0-9]' "${checked_summary}"
grep -q '^INTERFACE_INPUT_MIN_DELAY_NS=-1\.000$' "${checked_summary}"
grep -q '^INTERFACE_OUTPUT_MIN_DELAY_NS=0\.000$' "${checked_summary}"
grep -Eq '^BRAM=[1-9][0-9]*$' "${checked_summary}"
grep -Eq '^\|[[:space:]]+LUT as Memory[[:space:]]+\|[[:space:]]+0[[:space:]]+\|' \
    "${build_dir}/utilization.rpt"
grep -q '^DSP=0$' "${checked_summary}"
grep -q '^PCIE_HARD_BLOCK=0$' "${checked_summary}"

if [[ "${reuse}" != "1" ]]; then mv "${candidate_file}" "${summary_file}"; fi
trap - EXIT
cat "${summary_file}"
