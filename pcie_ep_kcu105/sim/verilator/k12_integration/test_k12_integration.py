import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


SPEED_L0 = 0
SPEED_RECOVERY_IDLE = 3
PHASE_DONE = 4


async def reset_dut(dut):
    dut.core_rst_n.value = 0
    dut.phy_rst_n.value = 0
    dut.link_up.value = 0
    dut.core_retrain_pulse.value = 0
    dut.core_target_speed.value = 0
    dut.eq_start.value = 0
    dut.force_peer_reject.value = 0
    dut.force_eq_timeout.value = 0
    dut.force_early_done.value = 0
    await Timer(3, units="ns")
    dut.core_rst_n.value = 1
    dut.phy_rst_n.value = 1
    dut.link_up.value = 1
    for _ in range(3):
        await RisingEdge(dut.phy_clk)
        await Timer(1, units="ns")


async def issue_retrain(dut, speed=2):
    dut.core_target_speed.value = speed
    dut.core_retrain_pulse.value = 1
    await RisingEdge(dut.core_clk)
    await Timer(1, units="ns")
    dut.core_retrain_pulse.value = 0


async def advance_phy(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.phy_clk)
        await Timer(1, units="ns")


async def reach_gen3_l0(dut):
    await issue_retrain(dut, 2)
    for _ in range(30):
        await advance_phy(dut)
        if int(dut.negotiated_speed.value) == 2 and int(dut.speed_state.value) == SPEED_L0:
            return
    assert False, "integrated partner did not reach Gen3 L0"


@cocotb.test()
async def integrated_rate_and_eq_handshake_respects_boundaries(dut):
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    await reach_gen3_l0(dut)
    assert int(dut.mailbox_valid.value) in (0, 1)
    assert int(dut.phy_rate.value) == 2
    assert int(dut.boundary_violation.value) == 0

    dut.eq_start.value = 1
    await advance_phy(dut)
    dut.eq_start.value = 0
    seen_phases = []
    for _ in range(50):
        await advance_phy(dut)
        phase = int(dut.eq_phase.value)
        if phase not in seen_phases and phase in (0, 1, 2, 3, PHASE_DONE):
            seen_phases.append(phase)
        if int(dut.eq_done.value):
            break
    assert seen_phases == [0, 1, 2, 3, PHASE_DONE]
    assert int(dut.eq_failed.value) == 0
    assert int(dut.boundary_violation.value) == 0


@cocotb.test()
async def peer_reject_falls_back_in_integrated_partner(dut):
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    dut.force_peer_reject.value = 1
    await issue_retrain(dut, 2)
    for _ in range(40):
        await advance_phy(dut)
        if int(dut.speed_fallback_taken.value):
            break
    assert int(dut.speed_fallback_taken.value) == 1
    assert int(dut.negotiated_speed.value) == 0


@cocotb.test()
async def eq_timeout_is_reported_by_integrated_partner(dut):
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    await reach_gen3_l0(dut)
    dut.force_eq_timeout.value = 1
    dut.eq_start.value = 1
    await advance_phy(dut)
    dut.eq_start.value = 0
    for _ in range(20):
        await advance_phy(dut)
        if int(dut.eq_failed.value):
            break
    assert int(dut.eq_failed.value) == 1
    assert int(dut.eq_active.value) == 0


@cocotb.test()
async def checker_detects_early_partner_done(dut):
    if os.environ.get("K12_INTEGRATION_NEGATIVE") != "1":
        return
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.phy_clk, 14, units="ns").start())
    await reset_dut(dut)
    dut.force_early_done.value = 1
    await issue_retrain(dut, 2)
    for _ in range(30):
        await advance_phy(dut)
        if int(dut.boundary_violation.value):
            with open("k12_integration_negative_observed.txt", "w", encoding="utf-8") as marker:
                marker.write("K12_INTEGRATION_NEGATIVE_OBSERVED ordered_set_boundary\n")
            assert False, "early Partner completion crossed Ordered Set boundary"
    assert False, "early Partner completion was not detected"
