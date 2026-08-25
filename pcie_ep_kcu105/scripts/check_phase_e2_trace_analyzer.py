#!/usr/bin/env python3
"""Positive and negative fixtures for the Phase E2 ILA CSV analyzer."""

from __future__ import annotations

import csv
import tempfile
from pathlib import Path

from analyze_phase_e2_rcvrlock_trace import analyze


def event_record() -> str:
    values = (0x39, 100, 10, 20, 0, 15, 5, 200)
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
        "u_endpoint/g/e2_gen3_block_locked_w",
        "u_endpoint/g/e2_rcvrlock_complete_w",
        "u_endpoint/g/e2_rcvrlock_failed_w",
        "u_endpoint/g/e2_rx_ts_count_w[4:0]",
        "u_endpoint/g/e2_speed_fallback_req_w",
        "u_endpoint/g/e2_speed_fallback_active_w",
        "u_endpoint/g/k14_ltssm_state_w[5:0]",
        "u_endpoint/g/e2_phy_rxdata_valid_w",
        "u_endpoint/g/e2_phy_rxstart_block_w",
        "u_endpoint/g/e2_phy_rxsync_header_w[1:0]",
        "u_endpoint/g/e2_phy_rxvalid_w",
        "u_endpoint/g/e2_phy_rxstatus_w[2:0]",
        "u_endpoint/g/e2_phy_rxelecidle_w",
    ]
    radix = ["UNSIGNED"] * len(header)
    record = event_record()
    rows = [
        [0, 0, 0, 1, 1, 1, 2, 0, record, 1, 0, 0, 7, 0, 0, "0b", 1, 1, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 2, 0, record, 1, int(complete), 0, 7, 0, 0, "0b", 1, 0, 0, 1, 0, 0],
        [2, 2, 0, 1, 1, 1, 2, 0, record, 1, 0, 0, 0, 0, 0, "0c", 1, 0, 0, 1, 0, 0],
    ]
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(header)
        writer.writerow(radix)
        writer.writerows(rows)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="phase_e2_trace_") as directory:
        positive = Path(directory) / "positive.csv"
        negative = Path(directory) / "negative.csv"
        write_fixture(positive, complete=True)
        write_fixture(negative, complete=False)
        if not analyze(positive)["pass"]:
            raise RuntimeError("positive Phase E2 trace fixture was rejected")
        if analyze(negative)["pass"]:
            raise RuntimeError("missing-complete negative fixture was accepted")
    print("PHASE_E2_TRACE_ANALYZER_SELFTEST_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
