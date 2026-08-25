#!/usr/bin/env python3
"""Validate the frozen K14 rate change and independent E1 PIPE milestones."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

from analyze_k02_golden_trace import analyze as analyze_golden


MILESTONES = (
    "rxelecidle_low",
    "rxvalid",
    "rxdata_valid",
    "rxstart_block",
    "ordered_header",
    "data_header",
    "eieos",
    "block_lock",
    "ts1",
    "ts2",
    "lock_lost",
    "malformed",
)


def find_column(header: list[str], suffix: str) -> int:
    matches = [index for index, name in enumerate(header) if name.endswith(suffix)]
    if len(matches) != 1:
        raise ValueError(f"column {suffix!r}: expected one match, got {len(matches)}")
    return matches[0]


def parse_hex(raw: str) -> int:
    return int(raw.strip().strip('"'), 16)


def column_width(name: str) -> int:
    match = re.search(r"\[(\d+):(\d+)\]$", name)
    return abs(int(match.group(1)) - int(match.group(2))) + 1 if match else 1


def primitive_status(
    header: list[str], row: list[str], start: int, end: int
) -> dict[str, int]:
    """Decode probe3 by connection order; optimized GT net names are unstable."""
    bits: list[int] = []
    for index in range(start, end):
        width = column_width(header[index])
        value = parse_hex(row[index])
        bits.extend((value >> bit) & 1 for bit in range(width))
    if len(bits) != 8:
        raise ValueError(f"E1 primitive probe width: expected 8 bits, got {len(bits)}")
    return {
        "rxcdrlock": bits[0],
        "rxresetdone": bits[1],
        "pcierateidle": bits[2],
        "rxdatavalid": bits[3] | (bits[4] << 1),
        "rxheadervalid": bits[5] | (bits[6] << 1),
        "rxvalid": bits[7],
    }


def analyze(path: Path) -> dict[str, object]:
    golden = analyze_golden(path)
    with path.open(newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) < 3:
        raise ValueError(f"{path}: incomplete ILA CSV")
    header = rows[0]
    data = rows[2:]
    record_index = find_column(header, "e1_event_record_w[31:0]")
    # The first board capture ended after the eight primitive-status bits.
    # Later malformed-trigger diagnostics append raw PIPE probes, so stop at
    # that optional bus instead of treating it as primitive status.
    raw_pipe_matches = [
        index for index, name in enumerate(header)
        if name.endswith("phy_rxdata[31:0]")
    ]
    primitive_end = min(raw_pipe_matches) if raw_pipe_matches else len(header)
    decoded = [parse_hex(row[record_index]) for row in data]
    elapsed_max = max(value & 0xFFFFF for value in decoded)
    seen_mask = 0
    for value in decoded:
        seen_mask |= (value >> 20) & 0xFFF
    seen = {
        name: bool(seen_mask & (1 << bit))
        for bit, name in enumerate(MILESTONES)
    }
    final_primitive = primitive_status(
        header, data[-1], record_index + 1, primitive_end
    )
    required = (
        seen["rxelecidle_low"]
        and seen["rxvalid"]
        and seen["rxdata_valid"]
        and seen["rxstart_block"]
        and seen["ordered_header"]
        and seen["eieos"]
        and seen["block_lock"]
        and (seen["ts1"] or seen["ts2"])
    )
    passed = (
        bool(golden["pass"])
        and required
        and not seen["lock_lost"]
        and not seen["malformed"]
        and final_primitive["rxcdrlock"] == 1
        and final_primitive["rxresetdone"] == 1
        and elapsed_max > 0
    )
    return {
        "file": str(path),
        "golden_pass": bool(golden["pass"]),
        "elapsed_max": elapsed_max,
        "seen_mask": seen_mask,
        "seen": seen,
        "primitive": final_primitive,
        "pass": passed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", nargs="+", type=Path)
    args = parser.parse_args()
    all_pass = True
    for path in args.csv:
        result = analyze(path)
        all_pass &= bool(result["pass"])
        seen = result["seen"]
        primitive = result["primitive"]
        print(
            "PHASE_E1_BOARD_TRACE"
            f" file={result['file']}"
            f" golden={int(result['golden_pass'])}"
            f" elapsed={result['elapsed_max']}"
            f" seen=0x{result['seen_mask']:03x}"
            f" pipe={int(seen['rxdata_valid'])}/{int(seen['rxstart_block'])}"
            f" headers={int(seen['ordered_header'])}/{int(seen['data_header'])}"
            f" eieos={int(seen['eieos'])} lock={int(seen['block_lock'])}"
            f" ts={int(seen['ts1'])}/{int(seen['ts2'])}"
            f" lost={int(seen['lock_lost'])} malformed={int(seen['malformed'])}"
            f" gt_cdr={primitive['rxcdrlock']}"
            f" gt_resetdone={primitive['rxresetdone']}"
            f" gt_rateidle={primitive['pcierateidle']}"
            f" gt_datavalid={primitive['rxdatavalid']}"
            f" gt_headervalid={primitive['rxheadervalid']}"
            f" gt_rxvalid={primitive['rxvalid']}"
            f" pass={int(result['pass'])}"
        )
    print(
        f"PHASE_E1_BOARD_TRACE_SET_{'PASS' if all_pass else 'FAIL'}"
        f" count={len(args.csv)}"
    )
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
