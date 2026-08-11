import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def source_loss_event_reaches_core_once(dut):
    """PIPE域单次链路退出事件必须跨域到Core域且只出现一次。"""
    cocotb.start_soon(Clock(dut.pipe_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.core_clk, 4, units="ns").start())
    dut.pipe_rst_n.value = 0
    dut.core_rst_n.value = 0
    dut.link_up.value = 0
    dut.dll_active.value = 0
    await Timer(3, units="ns")
    dut.pipe_rst_n.value = 1
    dut.core_rst_n.value = 1
    await RisingEdge(dut.pipe_clk)

    dut.link_up.value = 1
    dut.dll_active.value = 1
    await RisingEdge(dut.pipe_clk)
    await Timer(1, units="ns")
    assert int(dut.operational_seen.value) == 1

    dut.dll_active.value = 0
    await RisingEdge(dut.pipe_clk)
    await Timer(1, units="ns")
    assert int(dut.link_loss_pulse.value) == 1

    observed = 0
    for _ in range(8):
        await RisingEdge(dut.core_clk)
        await Timer(1, units="ns")
        observed += int(dut.core_link_loss_pulse.value)
    assert observed == 1

