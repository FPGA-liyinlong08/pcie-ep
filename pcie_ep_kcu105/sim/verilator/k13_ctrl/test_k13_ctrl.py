import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset_dut(dut):
    dut.core_rst_n.value = 0
    dut.phy_rst_n.value = 0
    dut.retrain_pulse.value = 0
    dut.target_speed.value = 2
    dut.force_cdr_lost.value = 0
    dut.force_ts_bad.value = 0
    await Timer(3, units="ns")
    dut.core_rst_n.value = 1
    dut.phy_rst_n.value = 1


async def advance(dut, n=1):
    for _ in range(n):
        await RisingEdge(dut.phy_clk)
        await Timer(1, units="ns")


async def retrain(dut):
    dut.retrain_pulse.value = 1
    await RisingEdge(dut.core_clk)
    await Timer(1, units="ns")
    dut.retrain_pulse.value = 0


@cocotb.test()
async def production_gen3_speed_eq_path(dut):
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    await retrain(dut)
    phases = []
    for _ in range(80):
        await advance(dut)
        phase = int(dut.eq_phase.value)
        if phase in (0, 1, 2, 3, 4) and phase not in phases:
            phases.append(phase)
        if int(dut.eq_done.value):
            break
    assert int(dut.negotiated_speed.value) == 2
    assert phases == [0, 1, 2, 3, 4]
    assert int(dut.eq_failed.value) == 0
    assert int(dut.txeq_ctrl.value) == 0
    assert int(dut.rxeq_ctrl.value) == 0


@cocotb.test()
async def production_cdr_loss_fallback(dut):
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    dut.force_cdr_lost.value = 1
    await retrain(dut)
    for _ in range(30):
        await advance(dut)
        if int(dut.cdr_loss_sticky.value):
            break
    assert int(dut.cdr_loss_sticky.value) == 1
    assert int(dut.fallback_sticky.value) == 1
    assert int(dut.negotiated_speed.value) == 0


@cocotb.test()
async def production_bad_ts_rejects(dut):
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    dut.force_ts_bad.value = 1
    await retrain(dut)
    for _ in range(40):
        await advance(dut)
        if int(dut.ts_reject.value):
            break
    assert int(dut.ts_reject.value) == 1
    for _ in range(8):
        await advance(dut)
        if int(dut.fallback_sticky.value):
            break
    assert int(dut.fallback_sticky.value) == 1
    assert int(dut.negotiated_speed.value) == 0
