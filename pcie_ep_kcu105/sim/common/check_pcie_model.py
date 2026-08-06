#!/usr/bin/env python3

"""M00 scheduler-independent self-check for cocotbext-pcie TLP APIs."""

from importlib.metadata import version

from cocotbext.pcie.core.tlp import Tlp, TlpType
from cocotbext.pcie.core.utils import PcieId


def main():
    tlp = Tlp()
    tlp.fmt_type = TlpType.MEM_WRITE
    tlp.requester_id = PcieId(1, 2, 0)
    tlp.tag = 0x5A
    tlp.set_addr_be_data(0x1004, bytes(range(1, 18)))

    assert tlp.check()
    packed = tlp.pack()
    unpacked = Tlp.unpack(packed)
    assert unpacked == tlp

    corrupted = bytearray(packed)
    corrupted[-1] ^= 0x01
    assert Tlp.unpack(corrupted) != tlp

    print(
        "M00_PCIE_TLP_PASS "
        f"version={version('cocotbext-pcie')} "
        f"tlp_bytes={len(packed)}"
    )


if __name__ == "__main__":
    main()
