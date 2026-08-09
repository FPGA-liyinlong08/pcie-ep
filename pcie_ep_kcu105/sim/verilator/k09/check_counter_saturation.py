#!/usr/bin/env python3
"""静态审计K09全部32-bit诊断计数器只能复位置零或饱和加一。"""

from __future__ import annotations

import re
import sys
from pathlib import Path


COUNTERS = (
    "mem_request_count",
    "mem_read_count",
    "mem_write_count",
    "axi_read_count",
    "axi_write_count",
    "sc_completion_count",
    "ur_completion_count",
    "ca_completion_count",
    "posted_drop_count",
    "poisoned_write_count",
    "axi_read_error_count",
    "axi_write_error_count",
    "payload_protocol_error_count",
)


def strip_comments(source: str) -> str:
    source = re.sub(
        r"/\*.*?\*/",
        lambda match: "\n" * match.group(0).count("\n"),
        source,
        flags=re.DOTALL,
    )
    return re.sub(r"//[^\n]*", "", source)


def compact(value: str) -> str:
    return re.sub(r"\s+", "", value)


def audit(rtl_path: Path) -> int:
    source = strip_comments(rtl_path.read_text(encoding="utf-8"))
    errors = []
    function = re.search(
        r"function\s+automatic\s+\[31:0\]\s+sat_inc32\s*"
        r"\(\s*input\s+\[31:0\]\s+value\s*\)\s*;"
        r"(?P<body>.*?)endfunction",
        source,
        flags=re.DOTALL,
    )
    expected_body = "beginsat_inc32=(&value)?value:value+1'b1;end"
    if function is None or compact(function.group("body")) != expected_body:
        errors.append("sat_inc32不是冻结的32-bit饱和表达式")

    increment_paths = 0
    for counter in COUNTERS:
        if not re.search(
                rf"\boutput\s+reg\s+\[31:0\]\s+{counter}\b", source):
            errors.append(f"{counter}不是32-bit output reg")
        assignments = re.findall(
            rf"\b{counter}\s*<=\s*(?P<rhs>[^;]+);",
            source,
            flags=re.DOTALL,
        )
        reset_paths = sum(compact(rhs) in {"0", "'0", "32'd0"}
                          for rhs in assignments)
        sat_paths = sum(compact(rhs) == f"sat_inc32({counter})"
                        for rhs in assignments)
        illegal = [compact(rhs) for rhs in assignments
                   if compact(rhs) not in {"0", "'0", "32'd0",
                                           f"sat_inc32({counter})"}]
        if reset_paths != 1 or sat_paths < 1 or illegal:
            errors.append(
                f"{counter}: reset={reset_paths} sat={sat_paths} illegal={illegal}")
        increment_paths += sat_paths

    calls = re.findall(
        r"\bsat_inc32\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", source)
    if len(calls) != increment_paths or set(calls) - set(COUNTERS):
        errors.append(
            f"sat_inc32调用未完全归属：calls={len(calls)} "
            f"checked={increment_paths} unexpected={set(calls) - set(COUNTERS)}")

    if errors:
        for message in errors:
            print(f"错误：{message}", file=sys.stderr)
        print("K09_COUNTER_SATURATION_AUDIT_FAIL", file=sys.stderr)
        return 1

    print(
        "K09_COUNTER_SATURATION_AUDIT_PASS "
        f"counters={len(COUNTERS)} increment_paths={increment_paths}")
    return 0


if __name__ == "__main__":
    RTL = Path(__file__).resolve().parents[3] / "rtl/tl/pcie_bar_axil_master.sv"
    sys.exit(audit(RTL))
