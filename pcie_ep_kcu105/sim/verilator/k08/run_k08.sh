#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

random_transactions="${K08_RANDOM_TRANSACTIONS:-100000}"
test_seed="${K08_RANDOM_SEED:-20260807}"
cocotb_seed="${RANDOM_SEED:-20260807}"

for value in "${random_transactions}" "${test_seed}" "${cocotb_seed}"; do
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        echo "错误：K08随机规模和种子必须是非负十进制整数" >&2
        exit 1
    fi
done
if (( random_transactions < 100000 )); then
    echo "错误：K08冻结回归不得低于100000个随机配置事务" >&2
    exit 1
fi
if [[ "${test_seed}" != "20260807" || "${cocotb_seed}" != "20260807" ]]; then
    echo "错误：K08冻结回归固定K08_RANDOM_SEED和RANDOM_SEED为20260807" >&2
    exit 1
fi
if [[ ! -f ../../../rtl/tl/pcie_cfg_space.sv ]]; then
    echo "错误：生产RTL尚未建立；当前只能运行k08-checker-selftest负向门禁" >&2
    exit 1
fi

export K08_RANDOM_TRANSACTIONS="${random_transactions}"
export K08_RANDOM_SEED="${test_seed}"
export RANDOM_SEED="${cocotb_seed}"
export K08_BIT_DWORDS=1024
export K08_ALLOW_SHORT_DIRECTED=0
export K08_ALLOW_SHORT_RANDOM=0
# 正向回归显式清除负向环境和marker，避免前一阶段子make的状态污染签核。
export K08_NEGATIVE_STUB=0
rm -f results.xml negative_checker_observed.txt
make -f Makefile results.xml

if grep -Eq '<failure|<error|<skipped' results.xml; then
    echo "错误：K08 Verilator回归存在失败、错误或跳过" >&2
    exit 1
fi

unit_test_count="$(grep -o '<testcase ' results.xml | wc -l)"
if [[ "${unit_test_count}" != "6" ]]; then
    echo "错误：K08单模块回归应运行6项测试，实际${unit_test_count}项" >&2
    exit 1
fi
if [[ -e negative_checker_observed.txt ]]; then
    echo "错误：生产RTL回归错误地产生了负向Checker marker" >&2
    exit 1
fi

rm -f results_integration.xml
make -f Makefile INTEGRATION=1 SIM_BUILD=sim_build_integration \
    COCOTB_RESULTS_FILE=results_integration.xml results_integration.xml

if grep -Eq '<failure|<error|<skipped' results_integration.xml; then
    echo "错误：K08 K07+K08 TLP级集成回归存在失败、错误或跳过" >&2
    exit 1
fi

integration_test_count="$(grep -o '<testcase ' results_integration.xml | wc -l)"
if [[ "${integration_test_count}" != "2" ]]; then
    echo "错误：K08 TLP级集成回归应运行2项测试，实际${integration_test_count}项" >&2
    exit 1
fi

echo "K08_VERILATOR_PASS unit_tests=${unit_test_count} integration_tests=${integration_test_count} random=${random_transactions} seed=${test_seed}"
