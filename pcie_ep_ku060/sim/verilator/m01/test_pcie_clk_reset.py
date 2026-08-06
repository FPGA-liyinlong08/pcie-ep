import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge, Timer


RESET_STAGES = 4
STATUS_STAGES = 2
PIPE_PERIOD_NS = float(os.getenv("PIPE_PERIOD_NS", "16"))
RANDOM_RESETS = int(os.getenv("M01_RANDOM_RESETS", "1000"))
RANDOM_STATUS_EVENTS = int(os.getenv("M01_RANDOM_STATUS_EVENTS", "100"))
RANDOM_SEED = int(os.getenv("M01_RANDOM_SEED", "20260806"))


async def start_clocks(dut):
    cocotb.start_soon(Clock(dut.core_clk, 4, units="ns").start())
    cocotb.start_soon(Clock(dut.pipe_clk, PIPE_PERIOD_NS, units="ns").start())
    await Timer(1, units="ns")


def drive_all_low(dut):
    dut.pcie_perst_n.value = 0
    dut.core_clock_locked.value = 0
    dut.gt_pll_lock.value = 0
    dut.gt_tx_reset_done.value = 0
    dut.gt_rx_reset_done.value = 0


async def sample(signal):
    await ReadOnly()
    return int(signal.value)


async def expect_sync_release(clock, reset_n, stages, name):
    for cycle in range(1, stages):
        await RisingEdge(clock)
        assert await sample(reset_n) == 0, f"{name} released at cycle {cycle}"

    await RisingEdge(clock)
    assert await sample(reset_n) == 1, f"{name} did not release at cycle {stages}"


async def wait_clock_ready(dut, max_core_cycles=STATUS_STAGES + 3):
    for _ in range(max_core_cycles):
        await RisingEdge(dut.core_clk)
        if await sample(dut.clock_ready):
            return
    raise AssertionError("clock_ready did not assert after both resets released")


async def wait_clock_not_ready(dut, max_core_cycles=STATUS_STAGES + 1):
    for _ in range(max_core_cycles):
        await RisingEdge(dut.core_clk)
        if not await sample(dut.clock_ready):
            return
    raise AssertionError("clock_ready did not deassert after PIPE/GT became unavailable")


@cocotb.test()
async def release_and_dependency(dut):
    """检查两个复位域的依赖关系、同步释放和异步置位。"""
    drive_all_low(dut)
    await start_clocks(dut)

    assert int(dut.core_rst_n.value) == 0
    assert int(dut.pipe_rst_n.value) == 0
    assert int(dut.clock_ready.value) == 0

    await FallingEdge(dut.core_clk)
    dut.pcie_perst_n.value = 1
    dut.core_clock_locked.value = 1
    await expect_sync_release(dut.core_clk, dut.core_rst_n, RESET_STAGES, "core_rst_n")

    assert int(dut.pipe_rst_n.value) == 0, "PIPE reset released before GT ready"
    assert int(dut.clock_ready.value) == 0

    await FallingEdge(dut.pipe_clk)
    dut.gt_pll_lock.value = 1
    dut.gt_tx_reset_done.value = 1
    dut.gt_rx_reset_done.value = 1
    await expect_sync_release(dut.pipe_clk, dut.pipe_rst_n, RESET_STAGES, "pipe_rst_n")
    await wait_clock_ready(dut)

    # 三个 GT 状态逐一撤销：都只复位 PIPE 域，不应复位 Core 域。
    for signal_name in ("gt_pll_lock", "gt_tx_reset_done", "gt_rx_reset_done"):
        await Timer(1300, units="ps")
        signal = getattr(dut, signal_name)
        signal.value = 0
        await Timer(1, units="ps")
        assert int(dut.pipe_rst_n.value) == 0, f"PIPE reset missed {signal_name} loss"
        assert int(dut.core_rst_n.value) == 1, f"Core reset followed {signal_name} loss"
        await wait_clock_not_ready(dut)

        await FallingEdge(dut.pipe_clk)
        signal.value = 1
        await expect_sync_release(dut.pipe_clk, dut.pipe_rst_n, RESET_STAGES, "pipe_rst_n")
        await wait_clock_ready(dut)

    # MMCM 失锁只直接复位 Core；PIPE 仍由 GT 状态控制。
    await Timer(1700, units="ps")
    dut.core_clock_locked.value = 0
    await Timer(1, units="ps")
    assert int(dut.core_rst_n.value) == 0
    assert int(dut.pipe_rst_n.value) == 1
    assert int(dut.clock_ready.value) == 0

    await FallingEdge(dut.core_clk)
    dut.core_clock_locked.value = 1
    await expect_sync_release(dut.core_clk, dut.core_rst_n, RESET_STAGES, "core_rst_n")
    await wait_clock_ready(dut)

    # PERST# 同时异步置位两个域。
    await Timer(900, units="ps")
    dut.pcie_perst_n.value = 0
    await Timer(1, units="ps")
    assert int(dut.core_rst_n.value) == 0
    assert int(dut.pipe_rst_n.value) == 0
    assert int(dut.clock_ready.value) == 0


@cocotb.test()
async def randomized_perst_stress(dut):
    """在随机相位执行 1000 次 PERST#，检查无提前释放或丢失复位。"""
    rng = random.Random(RANDOM_SEED + int(PIPE_PERIOD_NS * 10))
    drive_all_low(dut)
    await start_clocks(dut)

    dut.core_clock_locked.value = 1
    dut.gt_pll_lock.value = 1
    dut.gt_tx_reset_done.value = 1
    dut.gt_rx_reset_done.value = 1
    dut.pcie_perst_n.value = 1

    await ClockCycles(dut.core_clk, RESET_STAGES + STATUS_STAGES + 2)
    await ClockCycles(dut.pipe_clk, RESET_STAGES + 1)
    await wait_clock_ready(dut)

    for iteration in range(RANDOM_RESETS):
        await Timer(rng.randint(1, 3900), units="ps")
        dut.pcie_perst_n.value = 0
        await Timer(1, units="ps")

        assert int(dut.core_rst_n.value) == 0, f"core reset missed at {iteration}"
        assert int(dut.pipe_rst_n.value) == 0, f"pipe reset missed at {iteration}"
        assert int(dut.clock_ready.value) == 0, f"ready stayed high at {iteration}"

        await Timer(rng.randint(100, 3000), units="ps")
        dut.pcie_perst_n.value = 1

        await ClockCycles(dut.core_clk, RESET_STAGES - 1)
        assert int(dut.core_rst_n.value) == 0, f"core reset released early at {iteration}"
        await RisingEdge(dut.core_clk)
        await ReadOnly()
        assert int(dut.core_rst_n.value) == 1, f"core reset did not release at {iteration}"

        await ClockCycles(dut.pipe_clk, RESET_STAGES)
        await ReadOnly()
        assert int(dut.pipe_rst_n.value) == 1, f"pipe reset did not release at {iteration}"
        await wait_clock_ready(dut)


@cocotb.test()
async def randomized_status_phase(dut):
    """随机相位撤销 MMCM/GT 状态，检查复位范围和重新释放。"""
    rng = random.Random(RANDOM_SEED + 1000 + int(PIPE_PERIOD_NS * 10))
    drive_all_low(dut)
    await start_clocks(dut)

    dut.core_clock_locked.value = 1
    dut.gt_pll_lock.value = 1
    dut.gt_tx_reset_done.value = 1
    dut.gt_rx_reset_done.value = 1
    dut.pcie_perst_n.value = 1

    await ClockCycles(dut.core_clk, RESET_STAGES + STATUS_STAGES + 2)
    await ClockCycles(dut.pipe_clk, RESET_STAGES + 1)
    await wait_clock_ready(dut)

    status_names = (
        "core_clock_locked",
        "gt_pll_lock",
        "gt_tx_reset_done",
        "gt_rx_reset_done",
    )
    for iteration in range(RANDOM_STATUS_EVENTS):
        status_name = status_names[iteration % len(status_names)]
        signal = getattr(dut, status_name)
        await Timer(rng.randint(1, max(2, int(PIPE_PERIOD_NS * 1000) - 1)), units="ps")
        signal.value = 0
        await Timer(1, units="ps")

        if status_name == "core_clock_locked":
            assert int(dut.core_rst_n.value) == 0, f"Core reset missed lock loss at {iteration}"
            assert int(dut.pipe_rst_n.value) == 1, f"PIPE reset followed Core lock at {iteration}"
        else:
            assert int(dut.pipe_rst_n.value) == 0, f"PIPE reset missed {status_name} at {iteration}"
            assert int(dut.core_rst_n.value) == 1, f"Core reset followed {status_name} at {iteration}"

        await Timer(rng.randint(100, 3000), units="ps")
        signal.value = 1
        if status_name == "core_clock_locked":
            await expect_sync_release(dut.core_clk, dut.core_rst_n, RESET_STAGES, "core_rst_n")
        else:
            await expect_sync_release(dut.pipe_clk, dut.pipe_rst_n, RESET_STAGES, "pipe_rst_n")
        await wait_clock_ready(dut)
