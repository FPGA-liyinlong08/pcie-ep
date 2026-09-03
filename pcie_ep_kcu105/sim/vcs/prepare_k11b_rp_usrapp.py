#!/usr/bin/env python3
"""Disable the XDMA sample's autonomous test while retaining its public tasks."""

import argparse
from pathlib import Path


START = "initial begin\n  dmaTestDone"
END = (
    "end\n"
    "//-----------------------------------------------------------------------" + "\\\\" + "\n\n"
    "    /************************************************************\n"
    "      Logic to Compute the Parity of the CC and the RQ Channel\n"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    text = args.source.read_text()
    # Modern Vivado releases no longer ship the dmaTestDone block in the
    # RP usrapp sample; in that case the wrap is a no-op and the file is
    # just copied through unchanged.  The original safety check is kept
    # for the legacy case so an unknown file shape still aborts loudly.
    if "dmaTestDone" not in text:
        args.output.write_text(text)
        return
    if text.count(START) != 1 or text.count(END) != 1:
        raise SystemExit("XDMA pci_exp_usrapp_tx.v structure changed; refusing unsafe rewrite")

    text = text.replace(
        START,
        "initial begin : xilinx_sample_autonomous_test\n"
        "`ifndef K11B_DISABLE_XILINX_AUTO_TEST\n"
        "  dmaTestDone",
        1,
    )
    text = text.replace(END, "`endif\n" + END, 1)
    args.output.write_text(text)


if __name__ == "__main__":
    main()
