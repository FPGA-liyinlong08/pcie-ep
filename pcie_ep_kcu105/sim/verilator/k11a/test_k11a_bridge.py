import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset(dut):
    cocotb.start_soon(Clock(dut.pipe_clk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.core_clk, 4, units="ns").start())
    for name in ("dll_rx_valid", "core_tx_valid", "core_release_valid"):
        getattr(dut, name).value = 0
    dut.core_rx_ready.value = 0
    dut.dll_tx_ready.value = 0
    dut.dll_release_ready.value = 0
    dut.pipe_rst_n.value = 0
    dut.core_rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.core_clk)
    dut.pipe_rst_n.value = 1
    dut.core_rst_n.value = 1
    for _ in range(6):
        await RisingEdge(dut.pipe_clk)


async def send_tx(dut, beats, meta):
    for index, (data, keep, error) in enumerate(beats):
        dut.core_tx_valid.value = 1
        dut.core_tx_data.value = data
        dut.core_tx_keep.value = keep
        dut.core_tx_sop.value = int(index == 0)
        dut.core_tx_eop.value = int(index == len(beats) - 1)
        dut.core_tx_error.value = error
        dut.core_tx_type.value = meta[0]
        dut.core_tx_data_credits.value = meta[1]
        while True:
            await RisingEdge(dut.core_clk)
            if int(dut.core_tx_ready.value):
                # 让并行monitor在本次握手沿后先完成采样，再更新下一拍字段。
                await Timer(2, units="ps")
                break
    dut.core_tx_valid.value = 0
    dut.core_tx_sop.value = 0
    dut.core_tx_eop.value = 0


async def recv_tx(dut, expected_len, rng=None):
    result = []
    metadata = None
    for _ in range(2000):
        dut.dll_tx_ready.value = 1 if rng is None else rng.randint(0, 1)
        await Timer(1, units="ps")
        take = int(dut.dll_tx_valid.value) and int(dut.dll_tx_ready.value)
        if take:
            snapshot = (int(dut.dll_tx_data.value),
                        int(dut.dll_tx_keep.value),
                        int(dut.dll_tx_error.value),
                        int(dut.dll_tx_sop.value),
                        int(dut.dll_tx_eop.value),
                        int(dut.dll_tx_type.value),
                        int(dut.dll_tx_data_credits.value))
        await RisingEdge(dut.pipe_clk)
        if take:
            current = snapshot[5:7]
            metadata = current if metadata is None else metadata
            assert current == metadata
            result.append(snapshot[0:5])
            if snapshot[4]:
                assert len(result) == expected_len
                dut.dll_tx_ready.value = 0
                return result, metadata
    debug = []
    for name in ("tx_pkt_m_valid", "metadata_m_valid", "tx_pkt_s_ready",
                 "metadata_s_ready"):
        try:
            debug.append(f"{name}={int(getattr(dut.u_dut, name).value)}")
        except AttributeError:
            pass
    raise AssertionError("等待TX跨域Packet超时 " + " ".join(debug) +
                         f" sticky=0x{int(dut.sticky_errors.value):02x}")


@cocotb.test()
async def tx_metadata_checker(dut):
    await reset(dut)
    marker = os.getenv("K11A_NEGATIVE_MARKER")
    if marker:
        dut.dll_tx_ready.value = 1
        dut.core_tx_valid.value = 1
        dut.core_tx_sop.value = 1
        dut.core_tx_eop.value = 1
        dut.core_tx_data.value = 0x11223344
        dut.core_tx_keep.value = 0x00FF
        dut.core_tx_error.value = 0
        dut.core_tx_type.value = 2
        dut.core_tx_data_credits.value = 7
        await Timer(1, units="ns")
        try:
            assert (int(dut.dll_tx_type.value),
                    int(dut.dll_tx_data_credits.value)) == (2, 7)
        except AssertionError:
            with open(marker, "w", encoding="utf-8") as handle:
                handle.write("K11A_NEGATIVE_CHECKER_OBSERVED metadata\n")
            raise
        raise AssertionError("错误Stub未破坏TX元数据")

    # 错误替身没有内部缓冲，先允许TX握手；生产桥同样允许该设置。
    beats = [(0x11223344, 0x00FF, 3)]
    collector = cocotb.start_soon(recv_tx(dut, len(beats)))
    await send_tx(dut, beats, (2, 7))
    got, metadata = await collector
    try:
        assert metadata == (2, 7)
    except AssertionError:
        raise
    assert [(x[0], x[1], x[2]) for x in got] == beats


@cocotb.test()
async def bidirectional_random_and_release(dut):
    await reset(dut)
    rng = random.Random(20260811)

    for packet_index in range(100):
        length = rng.randint(1, 8)
        beats = [(rng.getrandbits(128),
                  0xFFFF if k != length - 1 else (1 << rng.randint(1, 16)) - 1,
                  rng.randrange(4) if k == length - 1 else 0)
                 for k in range(length)]
        meta = (rng.randrange(3), rng.randrange(33))
        await send_tx(dut, beats, meta)
        got, got_meta = await recv_tx(dut, length, rng)
        assert got_meta == meta
        assert [(x[0], x[1], x[2]) for x in got] == beats

    # RX方向多拍Packet：EOP提交后才可见。
    dut.core_rx_ready.value = 0
    rx_beats = [(0xA5, 0xFFFF, 0), (0x5A, 0x000F, 1)]
    for index, (data, keep, error) in enumerate(rx_beats):
        dut.dll_rx_valid.value = 1
        dut.dll_rx_data.value = data
        dut.dll_rx_keep.value = keep
        dut.dll_rx_sop.value = int(index == 0)
        dut.dll_rx_eop.value = int(index == len(rx_beats) - 1)
        dut.dll_rx_error.value = error
        while True:
            await RisingEdge(dut.pipe_clk)
            if int(dut.dll_rx_ready.value):
                break
        if index == 0:
            dut.dll_rx_valid.value = 0
            for _ in range(4):
                await RisingEdge(dut.core_clk)
                assert int(dut.core_rx_valid.value) == 0
    dut.dll_rx_valid.value = 0
    dut.core_rx_ready.value = 1
    observed = []
    while len(observed) < 2:
        await Timer(1, units="ps")
        take = int(dut.core_rx_valid.value) and int(dut.core_rx_ready.value)
        if take:
            snapshot = (int(dut.core_rx_data.value),
                        int(dut.core_rx_keep.value),
                        int(dut.core_rx_error.value))
        await RisingEdge(dut.core_clk)
        if take:
            observed.append(snapshot)
    assert observed == rx_beats

    # 信用事件保持顺序。
    dut.dll_release_ready.value = 0
    for event in ((0, 3), (1, 0), (2, 9)):
        dut.core_release_valid.value = 1
        dut.core_release_type.value = event[0]
        dut.core_release_data_credits.value = event[1]
        while True:
            await RisingEdge(dut.core_clk)
            if int(dut.core_release_ready.value):
                break
    dut.core_release_valid.value = 0
    events = []
    dut.dll_release_ready.value = 1
    while len(events) < 3:
        await Timer(1, units="ps")
        take = (int(dut.dll_release_valid.value) and
                int(dut.dll_release_ready.value))
        if take:
            snapshot = (int(dut.dll_release_type.value),
                        int(dut.dll_release_data_credits.value))
        await RisingEdge(dut.pipe_clk)
        if take:
            events.append(snapshot)
    assert events == [(0, 3), (1, 0), (2, 9)]
    assert int(dut.sticky_errors.value) == 0
