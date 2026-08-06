#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

legal_random="${K07_RANDOM_PACKETS:-10000}"
raw_random="${K07_RAW_PACKETS:-10000}"
memory_random="${K07_MEMORY_RANDOM_PACKETS:-2000}"
test_seed="${K07_RANDOM_SEED:-20260806}"
cocotb_seed="${RANDOM_SEED:-20260806}"

for value in "${legal_random}" "${raw_random}" "${memory_random}" \
             "${test_seed}" "${cocotb_seed}"; do
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        echo "错误：K07随机规模和种子必须是非负十进制整数" >&2
        exit 1
    fi
done
if (( legal_random < 10000 || raw_random < 10000 || memory_random < 2000 )); then
    echo "错误：K07冻结回归不得低于10000/10000/2000个随机Packet" >&2
    exit 1
fi
if [[ "${test_seed}" != "20260806" || "${cocotb_seed}" != "20260806" ]]; then
    echo "错误：K07冻结回归固定K07_RANDOM_SEED和RANDOM_SEED为20260806" >&2
    exit 1
fi

export K07_RANDOM_PACKETS="${legal_random}"
export K07_RAW_PACKETS="${raw_random}"
export K07_MEMORY_RANDOM_PACKETS="${memory_random}"
export K07_RANDOM_SEED="${test_seed}"
export RANDOM_SEED="${cocotb_seed}"
rm -f results.xml
make -f Makefile results.xml

if grep -Eq '<failure|<error|<skipped' results.xml; then
    echo "错误：K07 Verilator回归存在失败" >&2
    exit 1
fi

test_count="$(grep -o '<testcase ' results.xml | wc -l)"
if [[ "${test_count}" != "12" ]]; then
    echo "错误：K07回归应运行12项测试，实际${test_count}项" >&2
    exit 1
fi

echo "K07_VERILATOR_PASS tests=${test_count} legal_random=${legal_random} raw_random=${raw_random} memory_random=${memory_random} seed=${test_seed}"
