#!/usr/bin/env python3
"""Summarize the common PHY_FORENSICS records from XDMA and K15 runs."""
import argparse
import re
from collections import Counter

RE = re.compile(r"PHY_FORENSICS\s+(.*)$")


def read_records(path):
    records = []
    with open(path, encoding="utf-8", errors="replace") as stream:
        for line in stream:
            match = RE.search(line)
            if not match:
                continue
            item = {}
            for field in match.group(1).split():
                key, sep, value = field.partition("=")
                if not sep:
                    continue
                try:
                    item[key] = int(value, 0)
                except ValueError:
                    try:
                        # $display %h values in the simulator log have no
                        # 0x prefix (for example ``ltssm=0d``).
                        item[key] = int(value, 16)
                    except ValueError:
                        item[key] = value
            records.append(item)
    return records


def summarize(path):
    rows = read_records(path)
    stalls = []
    run = 0
    for row in rows:
        if row.get("rxdata_valid", 1) == 0:
            run += 1
        elif run:
            stalls.append(run)
            run = 0
    if run:
        stalls.append(run)
    sh11 = [n for n, row in enumerate(rows) if row.get("rxsync_header") == 3]
    token4a = [n for n, row in enumerate(rows)
               if (row.get("rxdata", -1) & 0xFF) == 0x4A]
    skp = [n for n, row in enumerate(rows) if row.get("rxstart_block") == 1]
    print(f"file={path} records={len(rows)}")
    print(f"rx_start_block_count={len(skp)} rxsync_header_11={len(sh11)} "
          f"token_4a={len(token4a)} rxstatus_nonzero="
          f"{sum(row.get('rxstatus', 0) != 0 for row in rows)}")
    print(f"rxdata_valid_stall_runs={len(stalls)} "
          f"stall_lengths={Counter(stalls)}")
    if len(skp) > 1:
        print("start_block_intervals=" + ",".join(
            str(b - a) for a, b in zip(skp, skp[1:])))
    print("first_sh11_record=" + (str(sh11[0]) if sh11 else "none"))
    print("first_token_4a_record=" + (str(token4a[0]) if token4a else "none"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log", nargs="+", help="simulate.log containing PHY_FORENSICS records")
    args = parser.parse_args()
    for path in args.log:
        summarize(path)


if __name__ == "__main__":
    main()
