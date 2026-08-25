#!/usr/bin/env python3
"""Positive and negative fixtures for the Phase E1 board trace analyzer."""

from __future__ import annotations

import csv
import tempfile
from pathlib import Path

from analyze_phase_e1_board_trace import analyze


def golden_record() -> str:
    values = (0x3B, 100, 10, 20, 0, 15, 5, 200)
    widths = (6, 16, 16, 16, 16, 16, 16, 16)
    encoded = 0
    shift = 0
    for value, width in zip(values, widths):
        encoded |= value << shift
        shift += width
    return f"{encoded:030x}"


def write_fixture(path: Path, complete: bool) -> None:
    header = [
        "Sample in Buffer", "Sample in Window", "TRIGGER",
        "u/common/pcsrsvdin_in[0:0]",
        "u/channel/pcierategen3_out[0:0]",
        "u/channel/usergen3rdy_generated_name",
        "u_endpoint/g/k14_phy_rate_w[1:0]",
        "u_endpoint/phy_phystatus",
        "u_endpoint/g/k14_event_record_w[117:0]",
        "u_endpoint/g/e1_event_record_w[31:0]",
        "u/channel/rxcdrlock_out[0:0]",
        "u/channel/rxresetdone_out[0:0]",
        "u/channel/pcierateidle_out[0:0]",
        "u/channel/rxdatavalid_out[0:0]",
        "u/channel/generated_rxdatavalid_1",
        "u/channel/rxheadervalid_out[1:0]",
        "u/channel/rxvalid_out[0:0]",
        "u_endpoint/phy_rxdata[31:0]",
        "u_endpoint/os_malformed",
    ]
    radix = ["UNSIGNED"] * len(header)
    required_seen = 0x3DF if complete else 0x001
    e1_record = (required_seen << 20) | 4096
    row = [
        0, 0, 1, 1, 1, 1, 2, 0, golden_record(), f"{e1_record:08x}",
        1, 1, 0, 1, 0, 1, 1, 0x12345678, 0,
    ]
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(header)
        writer.writerow(radix)
        writer.writerow(row)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="phase_e1_trace_") as directory:
        positive = Path(directory) / "positive.csv"
        negative = Path(directory) / "negative.csv"
        write_fixture(positive, complete=True)
        write_fixture(negative, complete=False)
        if not analyze(positive)["pass"]:
            raise RuntimeError("positive Phase E1 trace fixture was rejected")
        if analyze(negative)["pass"]:
            raise RuntimeError("missing-PIPE negative fixture was accepted")
    print("PHASE_E1_TRACE_ANALYZER_SELFTEST_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
