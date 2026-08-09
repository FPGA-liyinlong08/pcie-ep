#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
marker="${script_dir}/k09_negative_marker.txt"
random_evidence="${script_dir}/k09_random_evidence.txt"

rm -f "${marker}" "${script_dir}/results_negative.xml"
K09_NEGATIVE_STUB=1 \
K09_NEGATIVE_MARKER="${marker}" \
COCOTB_RESULTS_FILE=results_negative.xml \
TESTCASE=checker_guard \
make -C "${script_dir}" K09_NEGATIVE_STUB=1
grep -qx 'K09_NEGATIVE_CHECKER_OBSERVED address be posted' "${marker}"
grep -q '<failure' "${script_dir}/results_negative.xml"
echo "K09_CHECKER_SELFTEST_PASS address=1 be=1 posted=1"

rm -f "${marker}" "${random_evidence}" "${script_dir}/results.xml"
export K09_NEGATIVE_STUB=0
export COCOTB_RESULTS_FILE=results.xml
export K09_RANDOM_EVIDENCE="${random_evidence}"
unset TESTCASE
make -C "${script_dir}"

if [[ -e "${marker}" ]]; then
    echo "错误：K09生产回归遗留negative marker" >&2
    exit 1
fi
if [[ ! -s "${script_dir}/results.xml" ]] ||
   grep -Eq '<failure|<error' "${script_dir}/results.xml"; then
    echo "错误：K09生产JUnit缺失或包含失败" >&2
    exit 1
fi
test_count="$(grep -c '<testcase ' "${script_dir}/results.xml")"
if [[ "${test_count}" != "9" ]] ||
   ! grep -q 'name="randomized_100k_reference"' \
       "${script_dir}/results.xml" ||
   ! grep -q 'name="perst_cancels_all_inflight_states"' \
       "${script_dir}/results.xml"; then
    echo "错误：K09生产JUnit测试集合不完整（实际${test_count}项）" >&2
    exit 1
fi
request_count="${K09_RANDOM_REQUESTS:-100000}"
if [[ ! -s "${random_evidence}" ]] ||
   ! grep -q "^K09_RANDOM_SIGNOFF seed=20260807 requests=${request_count} random_ready=1 max_delay=3 " \
       "${random_evidence}"; then
    echo "错误：K09随机请求数量/反压证据缺失或不匹配" >&2
    exit 1
fi
echo "K09_VERILATOR_PASS requests=${request_count}"
