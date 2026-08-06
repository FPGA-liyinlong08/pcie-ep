import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer


RANDOM_VECTORS = int(os.getenv("K02_RANDOM_VECTORS", "10000"))
RANDOM_SEED = int(os.getenv("K02_RANDOM_SEED", "20260806"))


def drive_defaults(dut):
    dut.pcie_perst_n.value = 0
    dut.pcie_rxp.value = 0
    dut.pcie_rxn.value = 1
    dut.phy_txdata.value = 0
    dut.phy_txdatak.value = 0
    dut.phy_txdata_valid.value = 0
    dut.phy_txstart_block.value = 0
    dut.phy_txsync_header.value = 0
    dut.phy_txdetectrx.value = 0
    dut.phy_txelecidle.value = 1
    dut.phy_txcompliance.value = 0
    dut.phy_rxpolarity.value = 0
    dut.phy_powerdown.value = 2
    dut.phy_rate.value = 0
    dut.phy_txmargin.value = 0
    dut.phy_txswing.value = 0
    dut.phy_txdeemph.value = 0
    dut.phy_txeq_ctrl.value = 0
    dut.phy_txeq_preset.value = 0
    dut.phy_txeq_coeff.value = 0
    dut.phy_rxeq_ctrl.value = 0
    dut.phy_rxeq_txpreset.value = 0
    dut.as_mac_in_detect.value = 1
    dut.as_cdr_hold_req.value = 0


async def start_refclk(dut):
    cocotb.start_soon(Clock(dut.pcie_refclk_p, 10, units="ns").start())
    while True:
        dut.pcie_refclk_n.value = ~int(dut.pcie_refclk_p.value) & 1
        await RisingEdge(dut.pcie_refclk_p)
        dut.pcie_refclk_n.value = 0
        await Timer(5, units="ns")


async def expect_four_edge_release(clock, reset_n, name):
    for cycle in range(1, 4):
        await RisingEdge(clock)
        await ReadOnly()
        assert int(reset_n.value) == 0, f"{name} released early at cycle {cycle}"
    await RisingEdge(clock)
    await ReadOnly()
    assert int(reset_n.value) == 1, f"{name} did not release at cycle 4"
    # 离开 ReadOnly 阶段，允许调用者在下一时隙驱动控制信号。
    await Timer(1, units="ps")


async def initialize(dut):
    drive_defaults(dut)
    cocotb.start_soon(start_refclk(dut))
    await Timer(1, units="ns")
    assert int(dut.pipe_rst_n.value) == 0, "PIPE reset must assert with PERST#"
    assert int(dut.core_rst_n.value) == 0, "Core reset must assert with PERST#"
    dut.pcie_perst_n.value = 1
    await expect_four_edge_release(dut.phy_coreclk, dut.core_rst_n, "core_rst_n")
    assert int(dut.pipe_rst_n.value) == 1


@cocotb.test()
async def reset_detect_and_rate(dut):
    """复位、Receiver Detect 和 Rate Change 的冻结握手。"""
    await initialize(dut)

    dut.phy_powerdown.value = 2
    dut.phy_txelecidle.value = 1
    dut.phy_txdetectrx.value = 1
    await RisingEdge(dut.phy_pclk)
    await ReadOnly()
    assert int(dut.phy_phystatus.value) == 1
    assert int(dut.phy_rxstatus.value) == 0b011
    await Timer(1, units="ps")
    dut.phy_txdetectrx.value = 0

    for rate in (1, 2, 0):
        dut.phy_rate.value = rate
        await RisingEdge(dut.phy_pclk)
        await ReadOnly()
        assert int(dut.phy_phystatus.value) == 1, f"rate {rate} missing phystatus"
        assert int(dut.pipe_rst_n.value) == 0, f"rate {rate} did not reset PIPE"
        assert int(dut.core_rst_n.value) == 1, f"rate {rate} reset Core"
        await FallingEdge(dut.phy_phystatus_rst)
        await expect_four_edge_release(dut.phy_pclk, dut.pipe_rst_n, "pipe_rst_n")


@cocotb.test()
async def randomized_native_interface(dut):
    """10,000 组 PHY32/EQ 随机向量逐字段比对。"""
    await initialize(dut)
    rng = random.Random(RANDOM_SEED)

    for iteration in range(RANDOM_VECTORS):
        data = rng.getrandbits(32)
        datak = rng.getrandbits(2)
        data_valid = rng.getrandbits(1)
        start_block = rng.getrandbits(1)
        sync_header = rng.getrandbits(2)
        txeq_ctrl = rng.getrandbits(2)
        txeq_preset = rng.getrandbits(4)
        txeq_coeff = rng.getrandbits(6)
        rxeq_ctrl = rng.getrandbits(2)
        rxeq_preset = rng.getrandbits(4)

        dut.phy_txdata.value = data
        dut.phy_txdatak.value = datak
        dut.phy_txdata_valid.value = data_valid
        dut.phy_txstart_block.value = start_block
        dut.phy_txsync_header.value = sync_header
        dut.phy_txeq_ctrl.value = txeq_ctrl
        dut.phy_txeq_preset.value = txeq_preset
        dut.phy_txeq_coeff.value = txeq_coeff
        dut.phy_rxeq_ctrl.value = rxeq_ctrl
        dut.phy_rxeq_txpreset.value = rxeq_preset
        await Timer(1, units="ps")

        assert int(dut.phy_rxdata.value) == data, f"data iteration={iteration}"
        assert int(dut.phy_rxdatak.value) == datak, f"datak iteration={iteration}"
        assert int(dut.phy_rxdata_valid.value) == data_valid
        assert int(dut.phy_rxstart_block.value) == start_block
        assert int(dut.phy_rxsync_header.value) == sync_header
        assert int(dut.phy_txeq_fs.value) == txeq_ctrl
        assert int(dut.phy_txeq_lf.value) == txeq_preset
        assert int(dut.phy_txeq_new_coeff.value) == txeq_coeff
        assert int(dut.phy_rxeq_preset_sel.value) == (rxeq_ctrl & 1)
        assert int(dut.phy_rxeq_new_txcoeff.value) == rxeq_preset
        assert int(dut.phy_rxeq_adapt_done.value) == (rxeq_ctrl & 1)
        assert int(dut.phy_rxeq_done.value) == ((rxeq_ctrl >> 1) & 1)
