import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def tick(dut):
    await RisingEdge(dut.clk)
    await ReadOnly()
    await Timer(1, units="ps")


async def drive_word(dut, data, start=False, header=0b00):
    dut.in_valid.value = 1
    dut.start_block.value = int(start)
    dut.sync_header.value = header
    dut.in_data.value = data
    await tick(dut)


async def drive_block(dut, words):
    await drive_word(dut, words[0], start=True, header=0b01)
    for word in words[1:]:
        await drive_word(dut, word)
    block_malformed = int(dut.malformed.value)
    dut.in_valid.value = 0
    dut.start_block.value = 0
    dut.sync_header.value = 0
    dut.in_data.value = 0
    await tick(dut)
    return block_malformed


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.in_valid.value = 0
    dut.start_block.value = 0
    dut.sync_header.value = 0
    dut.in_data.value = 0
    for _ in range(3):
        await tick(dut)
    dut.rst_n.value = 1
    dut.enable.value = 1
    await tick(dut)


async def arm_sds(dut, final_word):
    # EIEOS establishes the receiver's Gen3 scrambler context.
    await drive_block(dut, [0xFF00_FF00] * 4)
    assert int(dut.u_rx.lfsr_ready.value) == 1
    # The first three SDS words are fixed; the fourth is the captured
    # lane-dependent word under investigation.
    return await drive_block(dut, [0xAAAA_AAAA, 0xAAAA_AAAA,
                                   0xAAAA_AAAA, final_word])


@cocotb.test()
async def fixed_sds_control_word_is_accepted(dut):
    await reset(dut)
    block_malformed = await arm_sds(dut, 0xBCBF_9DE1)
    assert block_malformed == 0
    assert int(dut.u_rx.lfsr_ready.value) == 1


@cocotb.test()
async def captured_sds_variation_reproduces_failure(dut):
    await reset(dut)
    block_malformed = await arm_sds(dut, 0xE646_70E1)
    assert block_malformed == 1
    assert int(dut.u_rx.lfsr_ready.value) == 0
