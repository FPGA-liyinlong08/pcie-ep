import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.link_up.value = 0
    dut.dll_active.value = 0
    await Timer(2, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def cycle(dut, link_up, dll_active):
    dut.link_up.value = link_up
    dut.dll_active.value = dll_active
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


@cocotb.test()
async def trigger_ignores_training_flaps_and_fires_once(dut):
    """Detect/Polling阶段的变化不能触发，L0/DLL Active退出只能触发一次。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    for values in ((1, 0), (0, 0), (1, 0), (0, 1), (0, 0)):
        await cycle(dut, *values)
        assert int(dut.link_loss_pulse.value) == 0
    assert int(dut.operational_seen.value) == 0

    await cycle(dut, 1, 1)
    assert int(dut.operational_seen.value) == 1
    assert int(dut.link_loss_pulse.value) == 0

    await cycle(dut, 1, 0)
    assert int(dut.link_loss_pulse.value) == 1
    assert int(dut.link_loss_seen.value) == 1

    for values in ((1, 1), (0, 0), (1, 0), (0, 0)):
        await cycle(dut, *values)
        assert int(dut.link_loss_pulse.value) == 0


@cocotb.test()
async def reset_allows_a_new_capture(dut):
    """PERST#复位后下一次真实工作状态退出可以重新触发。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await cycle(dut, 1, 1)
    await cycle(dut, 0, 1)
    assert int(dut.link_loss_pulse.value) == 1

    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(1, units="ns")
    await cycle(dut, 1, 1)
    await cycle(dut, 1, 0)
    assert int(dut.link_loss_pulse.value) == 1
