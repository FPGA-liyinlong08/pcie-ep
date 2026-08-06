import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())
    for name in ("enable", "raw_ack_valid", "raw_ack_data", "raw_fc_valid",
                 "raw_fc_data", "dllp_valid", "dllp_data", "dllp_keep",
                 "dllp_sop", "dllp_eop", "dllp_bad", "tlp_valid",
                 "tlp_data", "tlp_keep", "tlp_sop", "tlp_eop", "tlp_bad"):
        getattr(dut, name).value = 0
    dut.raw_out_ready.value = 0
    dut.out_ready.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.enable.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def raw_ack_priority_and_backpressure(dut):
    await reset(dut)
    dut.raw_ack_valid.value = 1
    dut.raw_ack_data.value = 0x11223344
    dut.raw_fc_valid.value = 1
    dut.raw_fc_data.value = 0xAABBCCDD
    await Timer(1, units="ps")
    assert int(dut.raw_out_valid.value) == 1
    assert int(dut.raw_out_data.value) == 0x11223344
    assert int(dut.raw_ack_ready.value) == 0
    assert int(dut.raw_fc_ready.value) == 0

    dut.raw_out_ready.value = 1
    await Timer(1, units="ps")
    assert int(dut.raw_ack_ready.value) == 1
    assert int(dut.raw_fc_ready.value) == 0
    await RisingEdge(dut.clk)
    dut.raw_ack_valid.value = 0
    await Timer(1, units="ps")
    assert int(dut.raw_out_data.value) == 0xAABBCCDD
    assert int(dut.raw_fc_ready.value) == 1


@cocotb.test()
async def packet_boundary_lock(dut):
    await reset(dut)
    dut.out_ready.value = 1

    # TLP已经开始后，即使DLLP到达，也必须完成TLP。
    dut.tlp_valid.value = 1
    dut.tlp_data.value = 0x1001
    dut.tlp_keep.value = 3
    dut.tlp_sop.value = 1
    await Timer(1, units="ps")
    assert int(dut.out_is_dllp.value) == 0
    assert int(dut.tlp_ready.value) == 1
    await RisingEdge(dut.clk)

    dut.tlp_sop.value = 0
    dut.tlp_data.value = 0x1002
    dut.dllp_valid.value = 1
    dut.dllp_data.value = 0xD001
    dut.dllp_keep.value = 3
    dut.dllp_sop.value = 1
    await Timer(1, units="ps")
    assert int(dut.out_is_dllp.value) == 0
    assert int(dut.out_data.value) == 0x1002
    assert int(dut.dllp_ready.value) == 0
    await RisingEdge(dut.clk)

    dut.tlp_data.value = 0x1003
    dut.tlp_eop.value = 1
    await RisingEdge(dut.clk)
    dut.tlp_valid.value = 0
    dut.tlp_eop.value = 0
    await Timer(1, units="ps")
    assert int(dut.out_is_dllp.value) == 1
    assert int(dut.out_data.value) == 0xD001

    # DLLP也锁到EOP；空闲边界同时到达时DLLP优先。
    await RisingEdge(dut.clk)
    dut.dllp_sop.value = 0
    dut.dllp_data.value = 0xD002
    dut.dllp_eop.value = 1
    dut.tlp_valid.value = 1
    dut.tlp_data.value = 0x2001
    dut.tlp_keep.value = 3
    dut.tlp_sop.value = 1
    await Timer(1, units="ps")
    assert int(dut.out_is_dllp.value) == 1
    assert int(dut.out_data.value) == 0xD002
    await RisingEdge(dut.clk)
    dut.dllp_valid.value = 0
    dut.dllp_eop.value = 0
    await Timer(1, units="ps")
    assert int(dut.out_is_dllp.value) == 0
    assert int(dut.out_data.value) == 0x2001
