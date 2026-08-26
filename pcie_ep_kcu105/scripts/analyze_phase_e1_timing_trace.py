#!/usr/bin/env python3
"""Decode the compact Phase E1 Recovery timing-recorder ILA stream."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

COUNTER_WIDTH = 20
EVENTS = (
    "T0_partner_retrain_valid", "T1_speed_retrain_accept",
    "T2_enter_rcvrlock", "T3_enter_rcvrcfg", "T4_ltssm_speed_ready",
    "T5_enter_rate_request", "T6_enter_rate_release", "T7_enter_golden_gap",
    "T8_phy_rate_gen3", "R0_last_gen1_ts1", "R1_last_gen1_ts2",
    "R2_rxelecidle_rise", "R3_rxvalid_fall", "G0_qpll_lock_fall",
    "G1_pcierateqpllreset_assert", "G2_pcierateqpllreset_deassert",
    "G3_qpll_lock_rise", "G4_pcierateidle_fall", "G5_pcierateidle_rise",
    "G6_phystatus_rise",
)


def find_column(header: list[str], suffix: str) -> int:
    matches = [i for i, name in enumerate(header) if name.endswith(suffix)]
    if len(matches) != 1:
        raise ValueError(f"{suffix}: expected one match, got {len(matches)}")
    return matches[0]


def decode(raw: str) -> tuple[int, int, int, int]:
    value = int(raw, 16)
    timestamp = value & ((1 << 20) - 1)
    index = (value >> 20) & 0x1F
    active = (value >> 25) & 1
    valid = (value >> 26) & ((1 << 20) - 1)
    return timestamp, index, active, valid


def analyze(path: Path) -> dict[str, object]:
    with path.open(newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) < 2:
        raise ValueError(f"{path}: incomplete ILA CSV")
    record_col = find_column(rows[0], "phase_e1_timing_record_w[63:0]")
    dump_col = find_column(rows[0], "phase_e1_timing_dump_active_w")
    decoded = [decode(row[record_col]) for row in rows[1:] if len(row) > record_col]
    stream_rows = [item for item in decoded if item[2]]
    if not stream_rows:
        raise ValueError(f"{path}: no timing dump rows found")
    valid = stream_rows[0][3]
    fields = {name: stream_rows[i][0] for i, name in enumerate(EVENTS)
              if i < len(stream_rows) and (valid & (1 << i))}
    rate_ts = fields.get("T8_phy_rate_gen3")
    normalized = {name: (stamp - rate_ts if rate_ts is not None else stamp)
                  for name, stamp in fields.items()}
    return {"path": str(path), "valid": valid, "fields": fields,
            "normalized": normalized, "dump_rows": len(stream_rows),
            "dump_probe_rows": sum(decode(row[dump_col])[2] for row in rows[1:]
                                    if len(row) > dump_col)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", nargs="+", type=Path)
    args = parser.parse_args()
    for path in args.csv:
        result = analyze(path)
        print(f"PHASE_E1_TIMING_TRACE file={result['path']} valid=0x{result['valid']:05x} "
              f"dump_rows={result['dump_rows']}")
        for name in EVENTS:
            raw = result["fields"].get(name)
            delta = result["normalized"].get(name)
            raw_us = "none" if raw is None else f"{raw * 0.004:.3f}us"
            delta_us = "none" if delta is None else f"{delta * 0.004:.3f}us"
            print(f"  {name}={raw_us} normalized_to_T8={delta_us}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
