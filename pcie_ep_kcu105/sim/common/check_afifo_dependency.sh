#!/usr/bin/env bash
set -euo pipefail

afifo_rtl="${AFIFO_RTL:-/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v}"
expected_sha256="e6c8d4731857caf504277dca72967c89dba6e3c83aee95953a0a279ff958cc4c"

if [[ ! -f "${afifo_rtl}" ]]; then
    echo "错误：找不到冻结的 afifo.v：${afifo_rtl}" >&2
    exit 1
fi

actual_sha256="$(sha256sum "${afifo_rtl}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "错误：afifo.v 指纹改变，必须重新评审 M02 CDC 核心" >&2
    echo "期望：${expected_sha256}" >&2
    echo "实际：${actual_sha256}" >&2
    exit 1
fi

echo "M02_AFIFO_DEPENDENCY_PASS sha256=${actual_sha256}"

