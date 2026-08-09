import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    for name in (
        "link_up", "link_speed", "ltssm_state", "dll_active", "dll_state",
        "rx_bad_symbol_count", "ltssm_retrain_count", "dll_lcrc_error_count",
        "dll_nak_count", "dll_replay_count", "dll_replay_timeout_count",
        "tl_malformed_count", "tl_unsupported_count", "bar_ur_count",
        "bar_ca_count", "bar_axi_error_count", "bar_payload_error_count",
    ):
        getattr(dut, name).value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def axil_write(dut, address, data, strobe=0xF, aw_delay=0, w_delay=0,
                     bready_delay=0):
    dut.s_axil_awaddr.value = address
    dut.s_axil_wdata.value = data
    dut.s_axil_wstrb.value = strobe
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    aw_done = w_done = False
    cycles = 0
    while not (aw_done and w_done):
        if not aw_done and cycles >= aw_delay:
            dut.s_axil_awvalid.value = 1
        if not w_done and cycles >= w_delay:
            dut.s_axil_wvalid.value = 1
        aw_handshake = (not aw_done and int(dut.s_axil_awvalid.value) and
                        int(dut.s_axil_awready.value))
        w_handshake = (not w_done and int(dut.s_axil_wvalid.value) and
                       int(dut.s_axil_wready.value))
        await RisingEdge(dut.clk)
        if aw_handshake:
            aw_done = True
            dut.s_axil_awvalid.value = 0
        if w_handshake:
            w_done = True
            dut.s_axil_wvalid.value = 0
        cycles += 1
    for _ in range(bready_delay):
        await RisingEdge(dut.clk)
    dut.s_axil_bready.value = 1
    while True:
        if int(dut.s_axil_bvalid.value):
            response = int(dut.s_axil_bresp.value)
            await RisingEdge(dut.clk)
            break
        await RisingEdge(dut.clk)
    dut.s_axil_bready.value = 0
    await RisingEdge(dut.clk)
    return response


async def axil_read(dut, address, rready_delay=0):
    dut.s_axil_araddr.value = address
    dut.s_axil_arvalid.value = 1
    while True:
        handshake = int(dut.s_axil_arready.value)
        await RisingEdge(dut.clk)
        if handshake:
            dut.s_axil_arvalid.value = 0
            break
    for _ in range(rready_delay):
        await RisingEdge(dut.clk)
    dut.s_axil_rready.value = 1
    while True:
        if int(dut.s_axil_rvalid.value):
            data = int(dut.s_axil_rdata.value)
            response = int(dut.s_axil_rresp.value)
            await RisingEdge(dut.clk)
            break
        await RisingEdge(dut.clk)
    dut.s_axil_rready.value = 0
    await RisingEdge(dut.clk)
    return data, response


def apply_strobe(old, new, strobe):
    result = old
    for byte in range(4):
        if strobe & (1 << byte):
            result &= ~(0xFF << (byte * 8))
            result |= new & (0xFF << (byte * 8))
    return result


async def start_test(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)


@cocotb.test()
async def checker_guard(dut):
    """错误Stub必须触发signature、strobe和decerr三个独立守卫。"""
    await start_test(dut)
    errors = []
    data, response = await axil_read(dut, 0x000)
    if data != 0x50434945 or response != 0:
        errors.append("signature")
    await axil_write(dut, 0x040, 0x11223344, 0xF)
    await axil_write(dut, 0x040, 0xAABBCCDD, 0x5)
    data, response = await axil_read(dut, 0x040)
    if data != 0x11BB33DD or response != 0:
        errors.append("strobe")
    data, response = await axil_read(dut, 0x1000)
    if data != 0 or response != 3:
        errors.append("decerr")
    if os.getenv("K10_NEGATIVE_STUB") == "1":
        marker = Path(os.environ["K10_NEGATIVE_MARKER"])
        marker.write_text("K10_NEGATIVE_CHECKER_OBSERVED " + " ".join(errors) + "\n")
    assert not errors, ",".join(errors)


@cocotb.test()
async def register_map_and_read_only(dut):
    """签名、版本、链路状态和12个计数器逐项映射。"""
    await start_test(dut)
    dut.link_up.value = 1
    dut.link_speed.value = 2
    dut.ltssm_state.value = 0x2D
    dut.dll_active.value = 1
    dut.dll_state.value = 0xA
    counter_names = (
        "rx_bad_symbol_count", "ltssm_retrain_count", "dll_lcrc_error_count",
        "dll_nak_count", "dll_replay_count", "dll_replay_timeout_count",
        "tl_malformed_count", "tl_unsupported_count", "bar_ur_count",
        "bar_ca_count", "bar_axi_error_count", "bar_payload_error_count",
    )
    for index, name in enumerate(counter_names):
        getattr(dut, name).value = 0x10203040 + index
    expected = {
        0x000: 0x50434945,
        0x004: 0x00010000,
        0x008: (0x2D << 8) | (2 << 1) | 1,
        0x00C: (0xA << 4) | 1,
    }
    expected.update({0x010 + 4*i: 0x10203040 + i for i in range(12)})
    for address, value in expected.items():
        data, response = await axil_read(dut, address, rready_delay=address & 3)
        assert response == 0 and data == value, (hex(address), hex(data), hex(value))
        assert await axil_write(dut, address, value ^ 0xFFFFFFFF, 0xF) == 0
        data_after, response = await axil_read(dut, address)
        assert response == 0 and data_after == value


@cocotb.test()
async def scratch_all_addresses_and_strobes(dut):
    """48个Scratch及全部16种WSTRB。"""
    await start_test(dut)
    for index in range(48):
        address = 0x040 + index * 4
        value = (0x9E3779B9 * (index + 1)) & 0xFFFFFFFF
        assert await axil_write(dut, address, value, 0xF,
                                aw_delay=index % 3, w_delay=(index + 1) % 3) == 0
        data, response = await axil_read(dut, address)
        assert response == 0 and data == value
    address = 0x080
    for strobe in range(16):
        base = 0x11223344
        update = 0xA0B0C000 | strobe
        await axil_write(dut, address, base, 0xF)
        await axil_write(dut, address, update, strobe,
                         aw_delay=strobe % 4, w_delay=(15-strobe) % 4,
                         bready_delay=strobe % 2)
        data, response = await axil_read(dut, address, rready_delay=strobe % 3)
        assert response == 0 and data == apply_strobe(base, update, strobe)


@cocotb.test()
async def ram_full_address_walking_and_random(dut):
    """960个RAM DWORD全地址、walking-one及Byte Strobe。"""
    await start_test(dut)
    model = [0] * 960
    for index in range(960):
        value = ((index << 20) ^ (index * 0x45D9F3B)) & 0xFFFFFFFF
        model[index] = value
        response = await axil_write(dut, 0x100 + 4*index, value, 0xF,
                                    aw_delay=index & 1, w_delay=(index >> 1) & 1)
        assert response == 0
    for index, value in enumerate(model):
        data, response = await axil_read(dut, 0x100 + 4*index,
                                         rready_delay=index & 1)
        assert response == 0 and data == value
    for bit in range(32):
        index = (bit * 29) % 960
        strobe = 1 << ((bit // 8) & 3)
        value = 1 << bit
        model[index] = apply_strobe(model[index], value, strobe)
        await axil_write(dut, 0x100 + 4*index, value, strobe)
        data, response = await axil_read(dut, 0x100 + 4*index)
        assert response == 0 and data == model[index]


@cocotb.test()
async def backpressure_and_error_paths(dut):
    """响应稳定、保留/未对齐/越界行为。"""
    await start_test(dut)
    assert await axil_write(dut, 0x040, 0xCAFEBABE, 0xF,
                            aw_delay=4, w_delay=0, bready_delay=5) == 0
    data, response = await axil_read(dut, 0x040, rready_delay=6)
    assert response == 0 and data == 0xCAFEBABE
    for address in (0x001, 0x042, 0xFFE, 0x1000, 0xFFFF1000):
        assert await axil_write(dut, address, 0xDEADBEEF, 0xF) == 3
        data, response = await axil_read(dut, address)
        assert response == 3 and data == 0


@cocotb.test()
async def reset_cancels_inflight_and_clears_scratch(dut):
    """AW、W、B、R中途PERST取消；Scratch清零。"""
    await start_test(dut)
    await axil_write(dut, 0x040, 0x12345678)
    dut.s_axil_awaddr.value = 0x044
    dut.s_axil_awvalid.value = 1
    while True:
        handshake = int(dut.s_axil_awready.value)
        await RisingEdge(dut.clk)
        if handshake:
            dut.s_axil_awvalid.value = 0
            break
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.s_axil_bvalid.value) == 0
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    dut.s_axil_wdata.value = 0xDEADBEEF
    dut.s_axil_wstrb.value = 0xF
    dut.s_axil_wvalid.value = 1
    while True:
        handshake = int(dut.s_axil_wready.value)
        await RisingEdge(dut.clk)
        if handshake:
            dut.s_axil_wvalid.value = 0
            break
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.s_axil_bvalid.value) == 0
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    for address in (0x040, 0x044, 0x0FC):
        data, response = await axil_read(dut, address)
        assert response == 0 and data == 0
    # BVALID和RVALID在反压期间被复位立即撤销。
    dut.s_axil_awaddr.value = 0x048
    dut.s_axil_wdata.value = 0xA5A5A5A5
    dut.s_axil_wstrb.value = 0xF
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wvalid.value = 1
    while not int(dut.s_axil_bvalid.value):
        aw_handshake = (int(dut.s_axil_awvalid.value) and
                        int(dut.s_axil_awready.value))
        w_handshake = (int(dut.s_axil_wvalid.value) and
                       int(dut.s_axil_wready.value))
        await RisingEdge(dut.clk)
        if aw_handshake:
            dut.s_axil_awvalid.value = 0
        if w_handshake:
            dut.s_axil_wvalid.value = 0
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.s_axil_bvalid.value) == 0
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    dut.s_axil_araddr.value = 0x000
    dut.s_axil_arvalid.value = 1
    while not int(dut.s_axil_rvalid.value):
        handshake = (int(dut.s_axil_arvalid.value) and
                     int(dut.s_axil_arready.value))
        await RisingEdge(dut.clk)
        if handshake:
            dut.s_axil_arvalid.value = 0
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.s_axil_rvalid.value) == 0


@cocotb.test()
async def randomized_100k_reference(dut):
    """固定种子混合读写、随机AW/W顺序及响应反压。"""
    await start_test(dut)
    seed = 20260810
    rng = random.Random(seed)
    request_count = int(os.getenv("K10_RANDOM_REQUESTS", "100000"))
    model = [0] * 1008
    # 初始化并覆盖全部可写DWORD，RAM随后只读取已知值。
    for index in range(1008):
        value = rng.getrandbits(32)
        model[index] = value
        await axil_write(dut, 0x040 + index*4, value, 0xF)
    writes = reads = decerr = 0
    strobe_seen = set()
    for request in range(request_count):
        is_write = rng.random() < 0.55
        error_access = rng.random() < 0.05
        if error_access:
            address = rng.choice((0x001, 0x042, 0xFFE, 0x1000, 0x2000))
            expected_response = 3
        else:
            index = rng.randrange(1008)
            address = 0x040 + index*4
            expected_response = 0
        if is_write:
            data = rng.getrandbits(32)
            strobe = rng.randrange(16)
            strobe_seen.add(strobe)
            response = await axil_write(
                dut, address, data, strobe,
                aw_delay=rng.randrange(6), w_delay=rng.randrange(6),
                bready_delay=rng.randrange(4))
            assert response == expected_response
            if not error_access:
                model[index] = apply_strobe(model[index], data, strobe)
            writes += 1
        else:
            data, response = await axil_read(dut, address, rng.randrange(4))
            assert response == expected_response
            assert data == (0 if error_access else model[index])
            reads += 1
        if error_access:
            decerr += 1
        if request_count >= 100000 and request % 1000 == 999:
            # 严格按冻结计划每1000事务全量比较1008个可写DWORD。
            for check_index in range(1008):
                value, response = await axil_read(dut, 0x040 + 4*check_index)
                assert response == 0 and value == model[check_index]
    assert strobe_seen == set(range(16))
    for index, expected in enumerate(model):
        data, response = await axil_read(dut, 0x040 + index*4)
        assert response == 0 and data == expected
    evidence = os.getenv("K10_RANDOM_EVIDENCE")
    if evidence:
        Path(evidence).write_text(
            f"K10_RANDOM_SIGNOFF seed={seed} requests={request_count} "
            f"writes={writes} reads={reads} decerr={decerr} strobes=16 "
            "max_aw_w_delay=5 max_response_delay=3 writable_dwords=1008\n"
        )
