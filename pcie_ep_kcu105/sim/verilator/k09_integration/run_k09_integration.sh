#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT="${SCRIPT_DIR}/results_k09_integration.xml"
rm -f "${RESULT}"
make -C "${SCRIPT_DIR}" \
    SIM_BUILD=sim_build \
    COCOTB_RESULTS_FILE=results_k09_integration.xml

if [[ ! -s "${RESULT}" ]] || grep -Eq '<failure|<error' "${RESULT}"; then
    echo "错误：K09 TLP集成JUnit缺失或包含失败" >&2
    exit 1
fi
if [[ "$(grep -c '<testcase ' "${RESULT}")" != "1" ]] ||
   ! grep -q 'name="enumerate_and_mmio_through_k07_k08_k09"' "${RESULT}"; then
    echo "错误：K09 TLP集成JUnit测试集合不完整" >&2
    exit 1
fi
echo "K09_TLP_INTEGRATION_PASS tests=1"
