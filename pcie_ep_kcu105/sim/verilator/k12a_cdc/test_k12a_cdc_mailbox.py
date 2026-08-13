import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset_dut(dut):
    dut.s_rst_n.value = 0
    dut.d_rst_n.value = 0
    dut.s_retrain_pulse.value = 0
    dut.s_target_speed.value = 0
    dut.d_retrain_accept.value = 0
    await Timer(3, units="ns")
    dut.s_rst_n.value = 1
    dut.d_rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.d_clk)


async def send_command(dut, speed):
    dut.s_target_speed.value = speed
    dut.s_retrain_pulse.value = 1
    await RisingEdge(dut.s_clk)
    dut.s_retrain_pulse.value = 0


@cocotb.test()
async def valid_must_hold_until_accept(dut):
    """valid和payload必须在目标域保持到accept，不能只传一拍脉冲。"""
    cocotb.start_soon(Clock(dut.s_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.d_clk, 14, units="ns").start())
    await reset_dut(dut)

    await send_command(dut, 2)
    for _ in range(10):
        await RisingEdge(dut.d_clk)
        if int(dut.d_retrain_valid.value):
            break
    assert int(dut.d_retrain_valid.value) == 1
    assert int(dut.d_target_speed.value) == 2
    assert int(dut.s_busy.value) == 1

    for _ in range(4):
        await RisingEdge(dut.d_clk)
        assert int(dut.d_retrain_valid.value) == 1
        assert int(dut.d_target_speed.value) == 2

    dut.d_retrain_accept.value = 1
    await RisingEdge(dut.d_clk)
    dut.d_retrain_accept.value = 0
    await Timer(1, units="ns")
    assert int(dut.d_retrain_valid.value) == 0

    for _ in range(6):
        await RisingEdge(dut.s_clk)
        if not int(dut.s_busy.value):
            break
    assert int(dut.s_busy.value) == 0
    assert int(dut.s_overflow_sticky.value) == 0


@cocotb.test()
async def payload_is_atomic_and_busy_command_is_reported(dut):
    """源域改变payload或忙时重复请求都不能撕裂/覆盖当前命令。"""
    cocotb.start_soon(Clock(dut.s_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.d_clk, 14, units="ns").start())
    await reset_dut(dut)

    await send_command(dut, 1)
    dut.s_target_speed.value = 3
    for _ in range(10):
        await RisingEdge(dut.d_clk)
        if int(dut.d_retrain_valid.value):
            break
    assert int(dut.d_retrain_valid.value) == 1
    assert int(dut.d_target_speed.value) == 1

    await send_command(dut, 2)
    await Timer(1, units="ns")
    assert int(dut.s_overflow_sticky.value) == 1
    await RisingEdge(dut.d_clk)
    assert int(dut.d_target_speed.value) == 1

    dut.d_retrain_accept.value = 1
    await RisingEdge(dut.d_clk)
    dut.d_retrain_accept.value = 0
    for _ in range(8):
        await RisingEdge(dut.s_clk)
        if not int(dut.s_busy.value):
            break
    assert int(dut.s_busy.value) == 0


@cocotb.test()
async def illegal_speed_is_transferred_for_controller_rejection(dut):
    """mailbox只负责原子传输；非法速率由Recovery控制器拒绝且不驱动PHY。"""
    cocotb.start_soon(Clock(dut.s_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.d_clk, 14, units="ns").start())
    await reset_dut(dut)
    await send_command(dut, 3)
    for _ in range(10):
        await RisingEdge(dut.d_clk)
        if int(dut.d_retrain_valid.value):
            break
    assert int(dut.d_retrain_valid.value) == 1
    assert int(dut.d_target_speed.value) == 3
    dut.d_retrain_accept.value = 1
    await RisingEdge(dut.d_clk)
    dut.d_retrain_accept.value = 0


@cocotb.test()
async def checker_marker_for_negative_stub(dut):
    if os.environ.get("K12A_NEGATIVE_STUB") != "1":
        return
    cocotb.start_soon(Clock(dut.s_clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.d_clk, 14, units="ns").start())
    await reset_dut(dut)
    await send_command(dut, 2)
    saw_valid = False
    for _ in range(8):
        await RisingEdge(dut.d_clk)
        if int(dut.d_retrain_valid.value):
            saw_valid = True
            continue
        if saw_valid:
            with open("k12a_negative_checker_observed.txt", "w", encoding="utf-8") as marker:
                marker.write("K12A_NEGATIVE_CHECKER_OBSERVED valid_hold\n")
            assert False, "negative stub dropped valid before accept"
    assert False, "negative stub did not produce a valid command"
