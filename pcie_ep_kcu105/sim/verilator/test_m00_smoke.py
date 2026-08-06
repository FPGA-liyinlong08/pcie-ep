import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge, Timer

from cocotbext.pcie.core import Device, Function, RootComplex
from cocotbext.pcie.core.tlp import Tlp, TlpType
from cocotbext.pcie.core.utils import PcieId


@cocotb.test()
async def reset_and_count(dut):
    """Prove that the baseline DUT, clock, reset, and checker are connected."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    await ReadOnly()
    assert int(dut.count.value) == 0

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    for expected in range(1, 33):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert int(dut.count.value) == expected, (
            f"counter mismatch: expected {expected}, got {dut.count.value}"
        )

    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.count.value) == 0


@cocotb.test()
async def pcie_model_objects(dut):
    """Construct and connect the cocotbext-pcie topology under a scheduler."""
    rc = RootComplex()
    dev = Device()
    fn = dev.make_function()
    standalone_fn = Function()

    dev.connect(rc.make_port())

    assert dev.upstream_port is not None
    assert len(dev.functions) == 1
    assert fn.function_num == 0
    assert isinstance(standalone_fn, Function)

    tlp = Tlp()
    tlp.fmt_type = TlpType.MEM_WRITE
    tlp.requester_id = PcieId(1, 2, 0)
    tlp.tag = 0x5A
    tlp.set_addr_be_data(0x1004, bytes(range(1, 18)))

    assert tlp.check()
    packed = tlp.pack()
    assert Tlp.unpack(packed) == tlp

    await Timer(1, units="ns")
