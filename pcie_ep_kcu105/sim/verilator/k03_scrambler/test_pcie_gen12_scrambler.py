import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer

K_COM = 0xBC
K_SKP = 0x1C


def advance_byte(s):
    b = [(s >> i) & 1 for i in range(16)]
    n = [0] * 16
    n[0], n[1], n[2] = b[8], b[9], b[10]
    n[3] = b[11] ^ b[8]
    n[4] = b[12] ^ b[9] ^ b[8]
    n[5] = b[13] ^ b[10] ^ b[9] ^ b[8]
    n[6] = b[14] ^ b[11] ^ b[10] ^ b[9]
    n[7] = b[15] ^ b[12] ^ b[11] ^ b[10]
    n[8] = b[0] ^ b[13] ^ b[12] ^ b[11]
    n[9] = b[1] ^ b[14] ^ b[13] ^ b[12]
    n[10] = b[2] ^ b[15] ^ b[14] ^ b[13]
    n[11] = b[3] ^ b[15] ^ b[14]
    n[12] = b[4] ^ b[15]
    n[13], n[14], n[15] = b[5], b[6], b[7]
    return sum(bit << i for i, bit in enumerate(n))


def mask(s):
    return sum(((s >> (15 - i)) & 1) << i for i in range(8))


def transform_word(s, data, datak, disabled=False):
    result = 0
    for lane in range(2):
        symbol = (data >> (lane * 8)) & 0xFF
        is_k = (datak >> lane) & 1
        value = symbol if (disabled or is_k) else symbol ^ mask(s)
        result |= value << (lane * 8)
        if is_k and symbol == K_COM:
            s = 0xFFFF
        elif not (is_k and symbol == K_SKP):
            s = advance_byte(s)
    return s, result


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())
    dut.rst_n.value = 0
    dut.in_valid.value = 0
    dut.scramble_disable.value = 0
    dut.in_data.value = 0
    dut.in_datak.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_check(dut, state, data, datak=0, disabled=False, valid=True):
    dut.in_valid.value = valid
    dut.scramble_disable.value = disabled
    dut.in_data.value = data
    dut.in_datak.value = datak
    expected_state, expected_data = transform_word(state, data, datak, disabled)
    if not valid:
        expected_state, expected_data = state, data
    await Timer(1, units="ns")
    assert int(dut.out_valid.value) == int(valid)
    if valid:
        assert int(dut.out_data.value) == expected_data
        assert int(dut.out_datak.value) == datak
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.lfsr_state.value) == expected_state
    await Timer(1, units="ns")
    dut.in_valid.value = 0
    return expected_state, expected_data


@cocotb.test()
async def known_vectors_com_skp_and_bypass(dut):
    await reset(dut)
    state = 0xFFFF
    state, _ = await drive_check(dut, state, 0x0000)
    state, _ = await drive_check(dut, state, (0x12 << 8) | K_COM, 0b01,
                                 disabled=True)
    assert state == advance_byte(0xFFFF)
    held = state
    state, _ = await drive_check(dut, state, (K_SKP << 8) | K_SKP, 0b11)
    assert state == held
    state, _ = await drive_check(dut, state, 0xA55A, disabled=True)


@cocotb.test()
async def randomized_round_trip_reference(dut):
    await reset(dut)
    rng = random.Random(20260810)
    tx_state = 0xFFFF
    rx_state = 0xFFFF
    for _ in range(20000):
        data = rng.getrandbits(16)
        datak = 0
        if rng.randrange(50) == 0:
            lane = rng.randrange(2)
            symbol = K_COM if rng.randrange(2) else K_SKP
            data = (data & ~(0xFF << (8 * lane))) | (symbol << (8 * lane))
            datak = 1 << lane
        disabled = rng.randrange(8) == 0
        valid = rng.randrange(10) != 0
        dut.in_valid.value = valid
        dut.scramble_disable.value = disabled
        dut.in_data.value = data
        dut.in_datak.value = datak
        tx_next, encoded = transform_word(tx_state, data, datak, disabled)
        rx_next, decoded = transform_word(rx_state, encoded, datak, disabled)
        if valid:
            assert decoded == data
            tx_state, rx_state = tx_next, rx_next
        await Timer(1, units="ns")
        if valid:
            assert int(dut.out_data.value) == encoded
        await RisingEdge(dut.clk)
        await ReadOnly()
        await Timer(1, units="ns")
    await RisingEdge(dut.clk)
    assert int(dut.lfsr_state.value) == tx_state
