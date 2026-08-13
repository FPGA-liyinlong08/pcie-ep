import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


ST_L0 = 0
ST_QUIESCE = 1
ST_SPEED_WAIT = 2
ST_RECOVERY_IDLE = 3
ST_FALLBACK_WAIT = 4
ST_FALLBACK_IDLE = 5


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.link_up.value = 0
    dut.retrain_valid.value = 0
    dut.retrain_target_speed.value = 0
    dut.phy_phystatus.value = 0
    dut.phy_cdr_lost.value = 0
    dut.peer_speed_ok.value = 0
    dut.peer_speed_reject.value = 0
    await Timer(3, units="ns")
    dut.rst_n.value = 1
    dut.link_up.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def issue_retrain(dut, speed):
    dut.retrain_target_speed.value = speed
    dut.retrain_valid.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.retrain_valid.value = 0


async def advance(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")


@cocotb.test()
async def normal_gen1_to_gen3_speed_handshake(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    assert int(dut.retrain_accept.value) == 1
    assert int(dut.state.value) == ST_QUIESCE
    assert int(dut.traffic_quiesce.value) == 1
    await advance(dut)
    assert int(dut.state.value) == ST_SPEED_WAIT
    assert int(dut.phy_rate.value) == 2
    assert int(dut.phy_txelecidle.value) == 1
    dut.phy_phystatus.value = 1
    await advance(dut)
    dut.phy_phystatus.value = 0
    assert int(dut.state.value) == ST_RECOVERY_IDLE
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 2
    assert int(dut.phy_rate.value) == 2
    assert int(dut.traffic_quiesce.value) == 0


@cocotb.test()
async def phy_done_timeout_falls_back_to_gen1(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    await advance(dut, 2)
    assert int(dut.state.value) == ST_SPEED_WAIT
    await advance(dut, 6)
    assert int(dut.state.value) == ST_FALLBACK_WAIT
    assert int(dut.speed_timeout_sticky.value) == 1
    assert int(dut.fallback_taken_sticky.value) == 1
    assert int(dut.phy_rate.value) == 0
    dut.phy_phystatus.value = 1
    await advance(dut)
    dut.phy_phystatus.value = 0
    assert int(dut.state.value) == ST_FALLBACK_IDLE
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 0


@cocotb.test()
async def peer_reject_falls_back_to_gen1(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    await advance(dut)
    dut.phy_phystatus.value = 1
    await advance(dut)
    dut.phy_phystatus.value = 0
    assert int(dut.state.value) == ST_RECOVERY_IDLE
    dut.peer_speed_reject.value = 1
    await advance(dut)
    dut.peer_speed_reject.value = 0
    assert int(dut.state.value) == ST_FALLBACK_WAIT
    assert int(dut.peer_reject_sticky.value) == 1
    dut.phy_phystatus.value = 1
    await advance(dut)
    dut.phy_phystatus.value = 0
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 0


@cocotb.test()
async def illegal_target_is_accepted_without_phy_action(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 3)
    assert int(dut.retrain_accept.value) == 1
    assert int(dut.state.value) == ST_L0
    assert int(dut.illegal_speed_sticky.value) == 1
    assert int(dut.phy_rate.value) == 0
    assert int(dut.traffic_quiesce.value) == 0


@cocotb.test()
async def checker_detects_early_phy_done(dut):
    if os.environ.get("K12B_NEGATIVE_STUB") != "1":
        return
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    if int(dut.state.value) == ST_RECOVERY_IDLE:
        with open("k12b_negative_checker_observed.txt", "w", encoding="utf-8") as marker:
            marker.write("K12B_NEGATIVE_CHECKER_OBSERVED phy_done_order\n")
        assert False, "negative stub left L0 without a Speed wait state"
    assert False, "negative stub was not exercised"
