#!/usr/bin/env python3
"""静态审计 K07 诊断计数器是否始终使用 32-bit 饱和加一。"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


COUNTERS = (
    "rx_packet_count",
    "cfg_request_count",
    "mem_request_count",
    "rx_completion_count",
    "tx_completion_count",
    "ur_completion_count",
    "malformed_count",
    "unsupported_count",
    "poisoned_count",
    "unexpected_completion_count",
    "tx_protocol_error_count",
)

RESET_VALUES = {"0", "'0", "32'd0", "32'h00000000"}


def strip_comments(source: str) -> str:
    """去掉注释，同时保留换行，避免注释文本形成伪匹配。"""

    def replace_block(match: re.Match[str]) -> str:
        text = match.group(0)
        return "\n" * text.count("\n")

    source = re.sub(r"/\*.*?\*/", replace_block, source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", source)


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


def line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def fail(messages: list[str]) -> int:
    for message in messages:
        print(f"错误：{message}", file=sys.stderr)
    print("K07_COUNTER_SATURATION_AUDIT_FAIL", file=sys.stderr)
    return 1


def audit(rtl_path: Path) -> int:
    if not rtl_path.is_file():
        return fail([f"找不到RTL文件：{rtl_path}"])

    original = rtl_path.read_text(encoding="utf-8")
    source = strip_comments(original)
    errors: list[str] = []

    function_match = re.search(
        r"function\s+automatic\s+\[31:0\]\s+sat_inc32\s*"
        r"\(\s*input\s+\[31:0\]\s+value\s*\)\s*;"
        r"(?P<body>.*?)endfunction",
        source,
        flags=re.DOTALL,
    )
    expected_body = "sat_inc32=(&value)?value:value+1'b1;"
    if function_match is None:
        errors.append("缺少固定签名 function automatic [31:0] sat_inc32(input [31:0] value)")
    elif compact(function_match.group("body")) != expected_body:
        errors.append(
            "sat_inc32实现不是预期饱和表达式 "
            "(&value) ? value : value + 1'b1"
        )

    increment_total = 0
    counter_results: list[tuple[str, int, int]] = []

    for counter in COUNTERS:
        declaration = re.search(
            rf"\boutput\s+reg\s+\[31:0\]\s+{re.escape(counter)}\b",
            source,
        )
        if declaration is None:
            errors.append(f"{counter}不是已声明的32-bit output reg")

        assignments = list(
            re.finditer(
                rf"\b{re.escape(counter)}\s*<=\s*(?P<rhs>[^;]+);",
                source,
                flags=re.DOTALL,
            )
        )
        if not assignments:
            errors.append(f"{counter}没有任何时序赋值路径")
            continue

        reset_count = 0
        increment_count = 0
        expected_increment = f"sat_inc32({counter})"
        for assignment in assignments:
            rhs = compact(assignment.group("rhs"))
            if rhs in RESET_VALUES:
                reset_count += 1
            elif rhs == expected_increment:
                increment_count += 1
            else:
                errors.append(
                    f"{counter}第{line_number(source, assignment.start())}行存在"
                    f"非复位、非自身sat_inc32赋值：{rhs}"
                )

        if reset_count != 1:
            errors.append(f"{counter}复位置零路径数量为{reset_count}，期望1")
        if increment_count == 0:
            errors.append(f"{counter}没有sat_inc32({counter})增量路径")

        increment_total += increment_count
        counter_results.append((counter, reset_count, increment_count))

    # 所有函数调用都必须直接服务于上述计数器的自身增量，防止遗漏隐藏调用。
    all_calls = re.findall(r"\bsat_inc32\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", source)
    if len(all_calls) != increment_total:
        errors.append(
            f"sat_inc32调用总数为{len(all_calls)}，已核对计数器增量路径为"
            f"{increment_total}，存在未归属调用"
        )
    unexpected_args = sorted(set(all_calls) - set(COUNTERS))
    if unexpected_args:
        errors.append("sat_inc32存在非K07计数器参数：" + ", ".join(unexpected_args))

    if errors:
        return fail(errors)

    for counter, reset_count, increment_count in counter_results:
        print(
            f"PASS {counter}: reset_paths={reset_count} "
            f"sat_increment_paths={increment_count}"
        )
    print(
        "K07_COUNTER_SATURATION_AUDIT_PASS "
        f"counters={len(COUNTERS)} increment_paths={increment_total} "
        "function=sat_inc32"
    )
    return 0


def main() -> int:
    default_rtl = (
        Path(__file__).resolve().parents[3] / "rtl" / "tl" / "pcie_tlp_codec.sv"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rtl",
        type=Path,
        default=default_rtl,
        help=f"待审计RTL路径（默认：{default_rtl}）",
    )
    args = parser.parse_args()
    return audit(args.rtl.resolve())


if __name__ == "__main__":
    sys.exit(main())
