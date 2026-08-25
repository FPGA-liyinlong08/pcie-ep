#!/usr/bin/env python3
"""Validate the K14 raw-rate and E2 RcvrLock evidence in one ILA CSV."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from analyze_k02_golden_trace import analyze as analyze_golden


def find_column(header: list[str], suffix: str) -> int:
    matches = [index for index, name in enumerate(header) if name.endswith(suffix)]
    if len(matches) != 1:
        raise ValueError(f"column {suffix!r}: expected one match, got {len(matches)}")
    return matches[0]


def parse_hex(raw: str) -> int:
    return int(raw.strip().strip('"'), 16)


def analyze(path: Path) -> dict[str, object]:
    golden = analyze_golden(path)
    with path.open(newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) < 3:
        raise ValueError(f"{path}: incomplete ILA CSV")
    header = rows[0]
    data = rows[2:]
    indices = {
        "locked": find_column(header, "e2_gen3_block_locked_w"),
        "complete": find_column(header, "e2_rcvrlock_complete_w"),
        "failed": find_column(header, "e2_rcvrlock_failed_w"),
        "count": find_column(header, "e2_rx_ts_count_w[4:0]"),
        "fallback_req": find_column(header, "e2_speed_fallback_req_w"),
        "fallback_active": find_column(header, "e2_speed_fallback_active_w"),
        "rate": find_column(header, "k14_phy_rate_w[1:0]"),
        "ltssm": find_column(header, "k14_ltssm_state_w[5:0]"),
        "rxdata_valid": find_column(header, "e2_phy_rxdata_valid_w"),
        "rxstart_block": find_column(header, "e2_phy_rxstart_block_w"),
        "rxsync_header": find_column(header, "e2_phy_rxsync_header_w[1:0]"),
        "rxvalid": find_column(header, "e2_phy_rxvalid_w"),
        "rxstatus": find_column(header, "e2_phy_rxstatus_w[2:0]"),
        "rxelecidle": find_column(header, "e2_phy_rxelecidle_w"),
    }
    samples = [
        {name: parse_hex(row[index]) for name, index in indices.items()}
        for row in data
    ]
    complete_samples = [sample for sample in samples if sample["complete"] == 1]
    max_count = max(sample["count"] for sample in samples)
    states = {sample["ltssm"] for sample in samples}
    passed = (
        bool(golden["pass"])
        and bool(complete_samples)
        and all(sample["locked"] == 1 for sample in complete_samples)
        and all(sample["rate"] == 2 for sample in complete_samples)
        and not any(sample["failed"] for sample in samples)
        and not any(sample["fallback_req"] for sample in samples)
        and not any(sample["fallback_active"] for sample in samples)
        and max_count >= 7
        and 0x0B in states
        and 0x0C in states
    )
    return {
        "file": str(path),
        "complete_samples": len(complete_samples),
        "max_ts1_count": max_count,
        "rcvrlock_seen": 0x0B in states,
        "rcvrcfg_seen": 0x0C in states,
        "failed_seen": any(sample["failed"] for sample in samples),
        "fallback_seen": any(
            sample["fallback_req"] or sample["fallback_active"]
            for sample in samples
        ),
        "rxdata_valid_samples": sum(
            sample["rxdata_valid"] != 0 for sample in samples
        ),
        "rxstart_block_samples": sum(
            sample["rxstart_block"] != 0 for sample in samples
        ),
        "rxvalid_samples": sum(sample["rxvalid"] != 0 for sample in samples),
        "rxsync_header_values": sorted(
            {sample["rxsync_header"] for sample in samples}
        ),
        "rxstatus_values": sorted({sample["rxstatus"] for sample in samples}),
        "rxelecidle_samples": sum(
            sample["rxelecidle"] != 0 for sample in samples
        ),
        "golden_pass": bool(golden["pass"]),
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
        print(
            "PHASE_E2_RCVRLOCK_TRACE"
            f" file={result['file']}"
            f" golden={int(result['golden_pass'])}"
            f" complete_samples={result['complete_samples']}"
            f" max_ts1_count={result['max_ts1_count']}"
            f" rcvrlock={int(result['rcvrlock_seen'])}"
            f" rcvrcfg={int(result['rcvrcfg_seen'])}"
            f" failed={int(result['failed_seen'])}"
            f" fallback={int(result['fallback_seen'])}"
            f" rxdata_valid={result['rxdata_valid_samples']}"
            f" rxstart={result['rxstart_block_samples']}"
            f" rxvalid={result['rxvalid_samples']}"
            f" rxsync={result['rxsync_header_values']}"
            f" rxstatus={result['rxstatus_values']}"
            f" rxelecidle={result['rxelecidle_samples']}"
            f" pass={int(result['pass'])}"
        )
    print(
        f"PHASE_E2_RCVRLOCK_TRACE_SET_{'PASS' if all_pass else 'FAIL'}"
        f" count={len(args.csv)}"
    )
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
