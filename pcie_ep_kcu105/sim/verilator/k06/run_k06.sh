#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

rm -f results.xml
make -f Makefile results.xml

if grep -q '<failure' results.xml; then
    echo "错误：K06 Verilator回归存在失败" >&2
    exit 1
fi

echo "K06_VERILATOR_PASS packets=${K06_RANDOM_PACKETS:-10000} seed=${K06_RANDOM_SEED:-20260806}"
