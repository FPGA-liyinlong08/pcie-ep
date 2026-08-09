import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


async def reset(dut):
    dut.rst_n.value = 0
    dut.mem_req_valid.value = 0
    dut.mem_w_valid.value = 0
    dut.cpl_req_ready.value = 0
    dut.cpl_data_ready.value = 0
    dut.link_up.value = 1
    dut.link_speed.value = 2
    dut.ltssm_state.value = 0x20
    dut.dll_active.value = 1
    dut.dll_state.value = 3
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_request(dut, write, offset, data=0, be=0xF, tag=1):
    dut.mem_req_write.value = int(write)
    dut.mem_req_address.value = 0xC0000000 + offset
    dut.mem_req_length_dw.value = 1
    dut.mem_req_first_be.value = be
    dut.mem_req_last_be.value = 0
    dut.mem_req_requester_id.value = 0x0001
    dut.mem_req_tag.value = tag
    dut.mem_req_valid.value = 1
    while True:
        handshake = int(dut.mem_req_ready.value)
        await RisingEdge(dut.clk)
        if handshake:
            dut.mem_req_valid.value = 0
            break
    if write:
        dut.mem_w_data.value = data
        dut.mem_w_keep.value = 0x000F
        dut.mem_w_last.value = 1
        dut.mem_w_valid.value = 1
        while True:
            handshake = int(dut.mem_w_ready.value)
            await RisingEdge(dut.clk)
            if handshake:
                dut.mem_w_valid.value = 0
                break
        while int(dut.bar_busy.value):
            await RisingEdge(dut.clk)
        return None
    dut.cpl_req_ready.value = 1
    while True:
        if int(dut.cpl_req_valid.value):
            desc = (int(dut.cpl_req_status.value),
                    int(dut.cpl_req_byte_count.value),
                    int(dut.cpl_req_lower_address.value),
                    int(dut.cpl_req_length_dw.value))
            await RisingEdge(dut.clk)
            break
        await RisingEdge(dut.clk)
    dut.cpl_req_ready.value = 0
    dut.cpl_data_ready.value = 1
    while True:
        if int(dut.cpl_data_valid.value):
            payload = int(dut.cpl_data.value) & 0xFFFFFFFF
            keep = int(dut.cpl_data_keep.value)
            last = int(dut.cpl_data_last.value)
            await RisingEdge(dut.clk)
            break
        await RisingEdge(dut.clk)
    dut.cpl_data_ready.value = 0
    return desc, payload, keep, last


@cocotb.test()
async def bar_requests_reach_demo_slave(dut):
    """生产K09通过AXI访问生产K10签名、状态、Scratch和RAM。"""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset(dut)
    desc, payload, keep, last = await send_request(dut, False, 0x000, tag=1)
    assert desc == (0, 4, 0, 1)
    assert payload == 0x50434945 and keep == 0xF and last == 1
    desc, payload, _, _ = await send_request(dut, False, 0x008, tag=2)
    assert desc[0] == 0 and payload == ((0x20 << 8) | (2 << 1) | 1)
    await send_request(dut, True, 0x040, 0x11223344, 0xF, 3)
    await send_request(dut, True, 0x040, 0xAABBCCDD, 0x5, 4)
    desc, payload, _, _ = await send_request(dut, False, 0x040, tag=5)
    assert desc[0] == 0 and payload == 0x11BB33DD
    await send_request(dut, True, 0xFFC, 0x89ABCDEF, 0xF, 6)
    desc, payload, _, _ = await send_request(dut, False, 0xFFC, tag=7)
    assert desc[0] == 0 and payload == 0x89ABCDEF
    dut._log.info("K10_BAR_DEMO_INTEGRATION_PASS signature status scratch ram")
