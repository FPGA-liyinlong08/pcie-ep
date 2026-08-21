import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


PHASE0 = 0
PHASE1 = 1
PHASE2 = 2
PHASE3 = 3
PHASE_DONE = 4
PHASE_FAIL = 5


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.eq_start.value = 0
    dut.target_speed.value = 2
    dut.tx_preset.value = 4
    dut.tx_coeff.value = 12
    dut.tx_coeff_valid.value = 1
    dut.rx_txpreset.value = 5
    dut.rx_preset_valid.value = 1
    dut.phy_txeq_done.value = 0
    dut.phy_rxeq_adapt_done.value = 0
    dut.phy_rxeq_done.value = 0
    await Timer(3, units="ns")
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")


async def start_eq(dut):
    dut.eq_start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.eq_start.value = 0


async def advance(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")


@cocotb.test()
async def normal_phase_0_to_3(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await start_eq(dut)
    assert int(dut.eq_start_accept.value) == 1
    assert int(dut.eq_active.value) == 1
    assert int(dut.phase.value) == PHASE0
    assert int(dut.phy_txeq_ctrl.value) == 1
    assert int(dut.phy_txeq_preset.value) == 4
    assert int(dut.phy_txeq_coeff.value) == 12
    dut.phy_txeq_done.value = 1
    await advance(dut)
    dut.phy_txeq_done.value = 0
    assert int(dut.phase.value) == PHASE1
    assert int(dut.phy_rxeq_ctrl.value) == 2
    assert int(dut.phy_rxeq_txpreset.value) == 5
    dut.phy_rxeq_adapt_done.value = 1
    dut.phy_rxeq_done.value = 1
    await advance(dut)
    dut.phy_rxeq_adapt_done.value = 0
    dut.phy_rxeq_done.value = 0
    assert int(dut.phase.value) == PHASE2
    assert int(dut.phy_txeq_ctrl.value) == 2
    dut.phy_txeq_done.value = 1
    await advance(dut)
    dut.phy_txeq_done.value = 0
    assert int(dut.phase.value) == PHASE3
    assert int(dut.phy_rxeq_ctrl.value) == 2
    dut.phy_rxeq_adapt_done.value = 1
    dut.phy_rxeq_done.value = 1
    await advance(dut)
    dut.phy_rxeq_done.value = 0
    dut.phy_rxeq_adapt_done.value = 0
    assert int(dut.eq_done.value) == 1
    assert int(dut.eq_active.value) == 0
    assert int(dut.phase.value) == PHASE_DONE
    assert int(dut.phy_txeq_ctrl.value) == 0
    assert int(dut.phy_rxeq_ctrl.value) == 0


@cocotb.test()
async def illegal_preset_or_coefficient_is_rejected(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.tx_preset.value = 10
    await start_eq(dut)
    assert int(dut.eq_start_accept.value) == 1
    assert int(dut.eq_failed.value) == 1
    assert int(dut.illegal_param_sticky.value) == 1
    assert int(dut.eq_active.value) == 0
    assert int(dut.phy_txeq_ctrl.value) == 0
    dut.tx_preset.value = 4
    # ST_FAIL先清回IDLE，再提交第二个非法参数用例。
    dut.eq_start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.eq_start.value = 0
    await advance(dut)
    dut.tx_coeff_valid.value = 0
    await start_eq(dut)
    assert int(dut.eq_failed.value) == 1
    assert int(dut.illegal_param_sticky.value) == 1


@cocotb.test()
async def tx_done_timeout_fails_and_clears_commands(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await start_eq(dut)
    await advance(dut, 5)
    assert int(dut.eq_failed.value) == 1
    assert int(dut.phase_timeout_sticky.value) == 1
    assert int(dut.eq_active.value) == 0
    assert int(dut.phy_txeq_ctrl.value) == 0


@cocotb.test()
async def rx_done_timeout_fails_and_clears_commands(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await start_eq(dut)
    dut.phy_txeq_done.value = 1
    await advance(dut)
    dut.phy_txeq_done.value = 0
    assert int(dut.phase.value) == PHASE1
    await advance(dut, 5)
    assert int(dut.eq_failed.value) == 1
    assert int(dut.phase_timeout_sticky.value) == 1
    assert int(dut.phy_rxeq_ctrl.value) == 0


@cocotb.test()
async def rx_done_without_adapt_fails(dut):
    """A PHY done pulse without adaptation must never complete RXEQ."""
    if os.environ.get("K12C_TWO_PASS") == "1":
        return
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await start_eq(dut)
    dut.phy_txeq_done.value = 1
    await advance(dut)
    dut.phy_txeq_done.value = 0
    assert int(dut.phase.value) == PHASE1
    dut.phy_rxeq_done.value = 1
    dut.phy_rxeq_adapt_done.value = 0
    await advance(dut)
    assert int(dut.eq_done.value) == 0
    assert int(dut.eq_failed.value) == 1
    assert int(dut.phy_rxeq_ctrl.value) == 0


@cocotb.test()
async def rx_done_without_adapt_retries_when_two_pass_enabled(dut):
    """Compatibility mode clears CTRL=2 and retries one coefficient pass."""
    if os.environ.get("K12C_TWO_PASS") != "1":
        return
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await start_eq(dut)
    dut.phy_txeq_done.value = 1
    await advance(dut)
    dut.phy_txeq_done.value = 0
    assert int(dut.phase.value) == PHASE1

    # First CTRL=2 pass: DONE without ADAPT_DONE is not final success.
    dut.phy_rxeq_done.value = 1
    dut.phy_rxeq_adapt_done.value = 0
    await advance(dut)
    assert int(dut.phase.value) == PHASE1
    assert int(dut.phy_rxeq_ctrl.value) == 0

    # The clear state holds CTRL=00 for two full clocks before CTRL=2 is retried.
    dut.phy_rxeq_done.value = 0
    await advance(dut, 3)
    assert int(dut.phase.value) == PHASE1
    assert int(dut.phy_rxeq_ctrl.value) == 2

    dut.phy_rxeq_adapt_done.value = 1
    dut.phy_rxeq_done.value = 1
    await advance(dut)
    assert int(dut.phase.value) == PHASE2


@cocotb.test()
async def checker_detects_phase_skip(dut):
    if os.environ.get("K12C_NEGATIVE_STUB") != "1":
        return
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await start_eq(dut)
    if int(dut.phase.value) != PHASE0:
        with open("k12c_negative_checker_observed.txt", "w", encoding="utf-8") as marker:
            marker.write("K12C_NEGATIVE_CHECKER_OBSERVED phase_order\n")
        assert False, "negative stub skipped Phase 0"
    await advance(dut)
    if int(dut.phase.value) == PHASE2:
        with open("k12c_negative_checker_observed.txt", "w", encoding="utf-8") as marker:
            marker.write("K12C_NEGATIVE_CHECKER_OBSERVED phase_order\n")
        assert False, "negative stub skipped Phase 1"
    assert False, "negative stub did not skip a phase"
