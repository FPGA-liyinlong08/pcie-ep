import os
import random
import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.pcie.core.dllp import Dllp, DllpType, crc16 as model_crc16


CRC16_POLY = 0xD008
CRC32_POLY = 0xEDB88320
CRC16_RESIDUE = 0x556F
CRC32_RESIDUE = 0xDEBB20E3


def crc_raw(data, width, poly):
    mask = (1 << width) - 1
    crc = mask
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = ((crc >> 1) ^ poly) if (crc & 1) else (crc >> 1)
    return crc & mask


def crc16_result(data):
    return (~crc_raw(data, 16, CRC16_POLY)) & 0xFFFF


def crc32_result(data):
    return (~crc_raw(data, 32, CRC32_POLY)) & 0xFFFFFFFF


async def start_clock_and_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.data.value = 0
    dut.keep.value = 0
    dut.last.value = 0
    dut.valid.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    assert int(dut.ready16.value) == 0
    assert int(dut.ready32.value) == 0
    assert int(dut.busy16.value) == 0
    assert int(dut.busy32.value) == 0
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    assert int(dut.ready16.value) == 1
    assert int(dut.ready32.value) == 1


def contiguous_beats(payload):
    beats = []
    offset = 0
    while offset < len(payload):
        chunk = payload[offset:offset + 4]
        word = sum(value << (8 * lane) for lane, value in enumerate(chunk))
        keep = (1 << len(chunk)) - 1
        beats.append((word, keep))
        offset += len(chunk)
    return beats


async def drive_beats(dut, beats, rng=None, gap_max=0):
    for index, (word, keep) in enumerate(beats):
        if rng is not None:
            for _ in range(rng.randint(0, gap_max)):
                dut.valid.value = 0
                await RisingEdge(dut.clk)
        dut.start.value = int(index == 0)
        dut.data.value = word
        dut.keep.value = keep
        dut.last.value = int(index == len(beats) - 1)
        dut.valid.value = 1
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, units="ps")
            if int(dut.ready16.value) and int(dut.ready32.value):
                break
    dut.valid.value = 0
    dut.start.value = 0
    dut.last.value = 0
    dut.keep.value = 0
    await Timer(1, units="ps")


async def drive_packet(dut, payload, rng=None, gap_max=0):
    assert payload
    await drive_beats(dut, contiguous_beats(payload), rng, gap_max)
    assert int(dut.crc_valid16.value) == 1
    assert int(dut.crc_valid32.value) == 1
    got16 = int(dut.crc_result16.value)
    got32 = int(dut.crc_result32.value)
    assert got16 == crc16_result(payload), (
        f"CRC16 mismatch data={payload.hex()} got={got16:04x} "
        f"expected={crc16_result(payload):04x}"
    )
    assert got32 == crc32_result(payload), (
        f"CRC32 mismatch data={payload.hex()} got={got32:08x} "
        f"expected={crc32_result(payload):08x}"
    )
    return got16, got32


@cocotb.test()
async def known_vectors(dut):
    await start_clock_and_reset(dut)
    payload = b"123456789"
    got16, got32 = await drive_packet(dut, payload)
    assert got16 == 0x0A3D
    assert got16 == ((~model_crc16(payload)) & 0xFFFF)
    assert got32 == 0xCBF43926
    assert got32 == zlib.crc32(payload)

    for length in (1, 2, 3, 4, 16, 128, 4096):
        for value in (0x00, 0xFF):
            await drive_packet(dut, bytes([value]) * length)


@cocotb.test()
async def all_last_keep_and_dllp_crosscheck(dut):
    await start_clock_and_reset(dut)
    for keep in range(1, 16):
        word = 0xD3A25C71
        payload = bytes((word >> (8 * lane)) & 0xFF for lane in range(4) if keep & (1 << lane))
        await drive_beats(dut, [(word, keep)])
        assert int(dut.crc_valid16.value) == 1
        assert int(dut.crc_result16.value) == crc16_result(payload)
        assert int(dut.crc_result32.value) == crc32_result(payload)

    dllps = []
    for dllp_type in (DllpType.ACK, DllpType.NAK):
        obj = Dllp()
        obj.type = dllp_type
        obj.seq = 0xA53
        dllps.append(obj)
    for dllp_type in (DllpType.INIT_FC1_P, DllpType.INIT_FC1_NP,
                      DllpType.INIT_FC2_CPL, DllpType.UPDATE_FC_P):
        obj = Dllp()
        obj.type = dllp_type
        obj.vc = 0
        obj.hdr_fc = 0x55
        obj.data_fc = 0xA5A
        dllps.append(obj)

    for dllp in dllps:
        data = dllp.pack()
        result16, _ = await drive_packet(dut, data)
        packed = dllp.pack_crc()
        assert result16.to_bytes(2, "little") == packed[-2:]
        assert model_crc16(packed) == CRC16_RESIDUE


@cocotb.test()
async def residue_and_single_bit_errors(dut):
    await start_clock_and_reset(dut)
    vectors = [b"123456789", bytes(range(64)), bytes([0xA5]) * 127]
    for payload in vectors:
        crc16 = crc16_result(payload).to_bytes(2, "little")
        await drive_packet(dut, payload + crc16)
        assert int(dut.crc_match16.value) == 1
        assert crc_raw(payload + crc16, 16, CRC16_POLY) == CRC16_RESIDUE

        crc32 = crc32_result(payload).to_bytes(4, "little")
        await drive_packet(dut, payload + crc32)
        assert int(dut.crc_match32.value) == 1
        assert crc_raw(payload + crc32, 32, CRC32_POLY) == CRC32_RESIDUE

        for protected, match_name in ((payload + crc16, "crc_match16"),
                                      (payload + crc32, "crc_match32")):
            positions = {0, len(protected) * 8 - 1, (len(protected) * 8) // 2}
            for bit_position in positions:
                corrupt = bytearray(protected)
                corrupt[bit_position // 8] ^= 1 << (bit_position % 8)
                await drive_packet(dut, bytes(corrupt))
                assert int(getattr(dut, match_name).value) == 0


async def expect_protocol_error(dut, beats):
    await drive_beats(dut, beats)
    assert int(dut.protocol_error16.value) == 1
    assert int(dut.protocol_error32.value) == 1
    assert int(dut.crc_valid16.value) == 0
    assert int(dut.crc_valid32.value) == 0
    assert int(dut.busy16.value) == 0
    assert int(dut.busy32.value) == 0


async def drive_raw_beat(dut, start, word, keep, last):
    dut.start.value = start
    dut.data.value = word
    dut.keep.value = keep
    dut.last.value = last
    dut.valid.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.valid.value = 0
    dut.start.value = 0
    dut.last.value = 0
    dut.keep.value = 0


@cocotb.test()
async def protocol_errors_reset_and_recovery(dut):
    await start_clock_and_reset(dut)

    # 无 start、keep=0、非末拍 partial keep。
    await drive_raw_beat(dut, 0, 0x12345678, 0xF, 1)
    assert int(dut.protocol_error16.value) == 1
    assert int(dut.protocol_error32.value) == 1
    await expect_protocol_error(dut, [(0x12345678, 0x0)])
    await expect_protocol_error(dut, [(0x12345678, 0x3), (0x99, 0x1)])

    # 嵌套 start。
    dut.start.value = 1
    dut.data.value = 0x03020100
    dut.keep.value = 0xF
    dut.last.value = 0
    dut.valid.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 1
    dut.last.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    assert int(dut.protocol_error16.value) == 1
    assert int(dut.protocol_error32.value) == 1
    dut.valid.value = 0

    # 错误后恢复。
    await drive_packet(dut, b"recovered")

    # Packet 中途复位，不产生结果；释放后可立即恢复。
    dut.start.value = 1
    dut.data.value = 0x44332211
    dut.keep.value = 0xF
    dut.last.value = 0
    dut.valid.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 0
    await Timer(1, units="ps")
    assert int(dut.ready16.value) == 0
    assert int(dut.busy16.value) == 0
    assert int(dut.crc_valid16.value) == 0
    dut.valid.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await drive_packet(dut, b"after reset")


@cocotb.test()
async def randomized_packets(dut):
    await start_clock_and_reset(dut)
    seed = int(os.getenv("K04_RANDOM_SEED", "20260806"))
    count = int(os.getenv("K04_RANDOM_PACKETS", "10000"))
    rng = random.Random(seed)
    boundary_lengths = [1, 2, 3, 4, 5, 15, 16, 17, 127, 128, 129,
                        255, 256, 511, 512, 1024, 2048, 4096]

    for index in range(count):
        if index < len(boundary_lengths) or index % 997 == 0:
            length = boundary_lengths[index % len(boundary_lengths)]
        else:
            length = rng.randint(1, 96)
        payload = bytes(rng.getrandbits(8) for _ in range(length))
        result16, result32 = await drive_packet(dut, payload, rng, gap_max=2)
        assert result16 == ((~model_crc16(payload)) & 0xFFFF)
        assert result32 == zlib.crc32(payload)

    dut._log.info("K04 cocotb随机回归完成 packets=%d seed=%d", count, seed)
