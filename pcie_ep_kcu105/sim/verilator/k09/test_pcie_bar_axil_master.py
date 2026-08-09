import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout

from k09_model import (
    ExpectedCompletion,
    byte_mask_for_dw,
    make_error_completion,
    make_sc_completions,
)


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    dut.rst_n.value = 0
    dut.hot_reset.value = 0
    dut.bar0_base.value = 0x80000000
    dut.bar0_probe_active.value = 0
    dut.memory_space_enable.value = 1
    dut.local_completer_id.value = 0x0100
    dut.mem_req_valid.value = 0
    dut.mem_req_write.value = 0
    dut.mem_req_64bit.value = 0
    dut.mem_req_poisoned.value = 0
    dut.mem_req_address.value = 0
    dut.mem_req_length_dw.value = 1
    dut.mem_req_first_be.value = 0xF
    dut.mem_req_last_be.value = 0
    dut.mem_req_requester_id.value = 0x0001
    dut.mem_req_tag.value = 0x5A
    dut.mem_req_tc.value = 0
    dut.mem_req_attr.value = 0
    dut.mem_w_valid.value = 0
    dut.mem_w_data.value = 0
    dut.mem_w_keep.value = 0
    dut.mem_w_last.value = 0
    dut.cpl_req_ready.value = 1
    dut.cpl_data_ready.value = 1
    dut.m_axil_awready.value = 0
    dut.m_axil_wready.value = 0
    dut.m_axil_bresp.value = 0
    dut.m_axil_bvalid.value = 0
    dut.m_axil_arready.value = 0
    dut.m_axil_rdata.value = 0
    dut.m_axil_rresp.value = 0
    dut.m_axil_rvalid.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)


async def wait_ready(dut, valid_name, ready_name, limit=100):
    for _ in range(limit):
        await FallingEdge(dut.clk)
        await Timer(2, units="ps")
        if int(getattr(dut, valid_name).value) and int(
                getattr(dut, ready_name).value):
            await RisingEdge(dut.clk)
            return
    raise AssertionError(f"{valid_name}/{ready_name}握手超时")


async def wait_idle(dut, limit=20000):
    for _ in range(limit):
        await FallingEdge(dut.clk)
        if not int(dut.busy.value):
            return
    raise AssertionError("等待K09 IDLE超时")


async def wait_high(dut, signal_name, limit=200):
    """在上升沿采样前观察一个输出，供手工协议/复位用例使用。"""
    for _ in range(limit):
        await FallingEdge(dut.clk)
        await Timer(2, units="ps")
        if int(getattr(dut, signal_name).value):
            return
    raise AssertionError(f"等待{signal_name}=1超时")


async def send_descriptor_only(dut, *, write, address, length_dw,
                               first_be=0xF, last_be=None, tag=0x70):
    """只发送K07结构化描述符，Payload由调用者另行控制。"""
    if last_be is None:
        last_be = 0 if length_dw == 1 else 0xF
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_req_write.value = int(write)
    dut.mem_req_64bit.value = 0
    dut.mem_req_poisoned.value = 0
    dut.mem_req_address.value = address
    dut.mem_req_length_dw.value = length_dw
    dut.mem_req_first_be.value = first_be
    dut.mem_req_last_be.value = last_be
    dut.mem_req_requester_id.value = 0x0001
    dut.mem_req_tag.value = tag
    dut.mem_req_tc.value = 0
    dut.mem_req_attr.value = 0
    dut.mem_req_valid.value = 1
    await wait_ready(dut, "mem_req_valid", "mem_req_ready", 2000)
    await Timer(1, units="ps")
    dut.mem_req_valid.value = 0


async def assert_async_reset_cancels(dut):
    """在任意状态异步置位PERST等效复位，并检查所有可见事务被取消。"""
    dut.rst_n.value = 0
    await Timer(10, units="ps")
    assert int(dut.busy.value) == 0
    assert int(dut.mem_req_ready.value) == 0
    for signal_name in (
            "m_axil_awvalid", "m_axil_wvalid", "m_axil_arvalid",
            "m_axil_bready", "m_axil_rready", "cpl_req_valid",
            "cpl_data_valid"):
        assert int(getattr(dut, signal_name).value) == 0, (
            f"异步复位未清除{signal_name}")
    for counter_name in (
            "mem_request_count", "mem_read_count", "mem_write_count",
            "axi_read_count", "axi_write_count", "sc_completion_count",
            "ur_completion_count", "ca_completion_count",
            "posted_drop_count", "poisoned_write_count",
            "axi_read_error_count", "axi_write_error_count",
            "payload_protocol_error_count"):
        assert int(getattr(dut, counter_name).value) == 0

    # 清理所有由测试平台驱动的事务输入；复位期间不会形成握手。
    dut.mem_req_valid.value = 0
    dut.mem_w_valid.value = 0
    dut.m_axil_awready.value = 0
    dut.m_axil_wready.value = 0
    dut.m_axil_bvalid.value = 0
    dut.m_axil_arready.value = 0
    dut.m_axil_rvalid.value = 0
    dut.cpl_req_ready.value = 1
    dut.cpl_data_ready.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    assert int(dut.mem_req_ready.value) == 1


class AxiLiteSlaveBfm:
    def __init__(self, dut, seed=1, random_ready=True, max_delay=3):
        self.dut = dut
        self.rng = random.Random(seed)
        self.random_ready = random_ready
        self.max_delay = max_delay
        self.memory = bytearray((index * 37 + 11) & 0xFF for index in range(4096))
        self.aw_queue = []
        self.w_queue = []
        self.pending_b = None
        self.pending_r = None
        self.write_errors = {}
        self.read_errors = {}
        self.writes = []
        self.reads = []
        self.running = True

    def inject_write_error(self, address, response=2):
        self.write_errors[address & 0xFFF] = response

    def inject_read_error(self, address, response=2):
        self.read_errors[address & 0xFFF] = response

    def _ready(self):
        return 1 if not self.random_ready else int(self.rng.random() < 0.72)

    async def run(self):
        dut = self.dut
        dut.m_axil_awready.value = 0
        dut.m_axil_wready.value = 0
        dut.m_axil_bvalid.value = 0
        dut.m_axil_bresp.value = 0
        dut.m_axil_arready.value = 0
        dut.m_axil_rvalid.value = 0
        dut.m_axil_rdata.value = 0
        dut.m_axil_rresp.value = 0

        b_delay = 0
        r_delay = 0
        while self.running:
            await FallingEdge(dut.clk)
            dut.m_axil_awready.value = self._ready()
            dut.m_axil_wready.value = self._ready()
            dut.m_axil_arready.value = self._ready() if self.pending_r is None else 0
            await Timer(1, units="ps")
            aw_fire = int(dut.m_axil_awvalid.value) and int(dut.m_axil_awready.value)
            w_fire = int(dut.m_axil_wvalid.value) and int(dut.m_axil_wready.value)
            b_fire = int(dut.m_axil_bvalid.value) and int(dut.m_axil_bready.value)
            ar_fire = int(dut.m_axil_arvalid.value) and int(dut.m_axil_arready.value)
            r_fire = int(dut.m_axil_rvalid.value) and int(dut.m_axil_rready.value)
            aw_value = int(dut.m_axil_awaddr.value) if aw_fire else None
            w_value = (int(dut.m_axil_wdata.value), int(dut.m_axil_wstrb.value)) \
                if w_fire else None
            ar_value = int(dut.m_axil_araddr.value) if ar_fire else None

            await RisingEdge(dut.clk)
            await Timer(1, units="ps")
            if aw_fire:
                assert aw_value & 3 == 0 and aw_value < 4096
                self.aw_queue.append(aw_value)
            if w_fire:
                assert w_value[1] != 0
                self.w_queue.append(w_value)
            if b_fire:
                dut.m_axil_bvalid.value = 0
                self.pending_b = None
            if ar_fire:
                assert ar_value & 3 == 0 and ar_value < 4096
                response = self.read_errors.pop(ar_value, 0)
                data = int.from_bytes(self.memory[ar_value:ar_value + 4], "little")
                self.pending_r = (ar_value, data, response)
                r_delay = self.rng.randrange(self.max_delay + 1)
            if r_fire:
                dut.m_axil_rvalid.value = 0
                self.pending_r = None

            if self.pending_b is None and self.aw_queue and self.w_queue:
                address = self.aw_queue.pop(0)
                data, strobe = self.w_queue.pop(0)
                response = self.write_errors.pop(address, 0)
                if response < 2:
                    for lane in range(4):
                        if strobe & (1 << lane):
                            self.memory[address + lane] = (data >> (8 * lane)) & 0xFF
                self.writes.append((address, data, strobe, response))
                self.pending_b = response
                b_delay = self.rng.randrange(self.max_delay + 1)

            if self.pending_b is not None and not int(dut.m_axil_bvalid.value):
                if b_delay == 0:
                    dut.m_axil_bresp.value = self.pending_b
                    dut.m_axil_bvalid.value = 1
                else:
                    b_delay -= 1
            if self.pending_r is not None and not int(dut.m_axil_rvalid.value):
                if r_delay == 0:
                    address, data, response = self.pending_r
                    dut.m_axil_rdata.value = data
                    dut.m_axil_rresp.value = response
                    dut.m_axil_rvalid.value = 1
                    self.reads.append((address, data, response))
                else:
                    r_delay -= 1


class CompletionSink:
    def __init__(self, dut, seed=2, random_ready=True):
        self.dut = dut
        self.rng = random.Random(seed)
        self.random_ready = random_ready
        self.queue = Queue()
        self.active = None
        self.payload = bytearray()
        self.running = True

    def _ready(self):
        return 1 if not self.random_ready else int(self.rng.random() < 0.74)

    async def run(self):
        dut = self.dut
        dut.cpl_req_ready.value = 0
        dut.cpl_data_ready.value = 0
        while self.running:
            await FallingEdge(dut.clk)
            dut.cpl_req_ready.value = self._ready()
            dut.cpl_data_ready.value = self._ready()
            await Timer(1, units="ps")
            desc_fire = int(dut.cpl_req_valid.value) and int(dut.cpl_req_ready.value)
            data_fire = int(dut.cpl_data_valid.value) and int(dut.cpl_data_ready.value)
            if desc_fire:
                desc = {
                    "has_data": int(dut.cpl_req_has_data.value),
                    "poisoned": int(dut.cpl_req_poisoned.value),
                    "status": int(dut.cpl_req_status.value),
                    "bcm": int(dut.cpl_req_bcm.value),
                    "byte_count": int(dut.cpl_req_byte_count.value),
                    "completer_id": int(dut.cpl_req_completer_id.value),
                    "requester_id": int(dut.cpl_req_requester_id.value),
                    "tag": int(dut.cpl_req_tag.value),
                    "lower_address": int(dut.cpl_req_lower_address.value),
                    "length_dw": int(dut.cpl_req_length_dw.value),
                    "tc": int(dut.cpl_req_tc.value),
                    "attr": int(dut.cpl_req_attr.value),
                }
            else:
                desc = None
            if data_fire:
                data = int(dut.cpl_data.value).to_bytes(16, "little")
                keep = int(dut.cpl_data_keep.value)
                last = int(dut.cpl_data_last.value)
            else:
                data = b""
                keep = 0
                last = 0

            await RisingEdge(dut.clk)
            await Timer(1, units="ps")
            if desc is not None:
                assert self.active is None, "前一个Completion Payload尚未结束"
                assert desc["poisoned"] == 0 and desc["bcm"] == 0
                if desc["has_data"]:
                    assert desc["status"] == 0
                    assert 1 <= desc["length_dw"] <= 32
                    assert 1 <= desc["byte_count"] <= 4096
                    self.active = desc
                    self.payload = bytearray()
                else:
                    assert desc["status"] in (1, 4)
                    assert desc["length_dw"] == 0 and desc["byte_count"] == 0
                    desc["payload"] = b""
                    await self.queue.put(desc)
            if data_fire:
                assert self.active is not None, "无描述符的Completion Payload"
                assert keep != 0 and (keep & (keep + 1)) == 0, "keep必须从bit0连续"
                count = bin(keep).count("1")
                self.payload.extend(data[:count])
                if last:
                    assert len(self.payload) == self.active["length_dw"] * 4
                    self.active["payload"] = bytes(self.payload)
                    await self.queue.put(self.active)
                    self.active = None
                    self.payload = bytearray()
    async def get(self, timeout_us=20):
        return await with_timeout(self.queue.get(), timeout_us, "us")


class ProtocolMonitor:
    CHANNELS = (
        ("m_axil_awvalid", "m_axil_awready", ("m_axil_awaddr",)),
        ("m_axil_wvalid", "m_axil_wready", ("m_axil_wdata", "m_axil_wstrb")),
        ("m_axil_arvalid", "m_axil_arready", ("m_axil_araddr",)),
        ("cpl_req_valid", "cpl_req_ready", (
            "cpl_req_has_data", "cpl_req_status", "cpl_req_byte_count",
            "cpl_req_completer_id", "cpl_req_requester_id", "cpl_req_tag",
            "cpl_req_lower_address", "cpl_req_length_dw", "cpl_req_tc",
            "cpl_req_attr")),
        ("cpl_data_valid", "cpl_data_ready", (
            "cpl_data", "cpl_data_keep", "cpl_data_last")),
    )

    def __init__(self, dut):
        self.dut = dut
        self.stalled = {}
        self.aw = self.w = self.b = self.ar = self.r = 0
        self.running = True

    async def run(self):
        dut = self.dut
        while self.running:
            await FallingEdge(dut.clk)
            await Timer(2, units="ps")
            if not int(dut.rst_n.value):
                self.stalled.clear()
                self.aw = self.w = self.b = self.ar = self.r = 0
                continue
            for valid_name, ready_name, fields in self.CHANNELS:
                valid = int(getattr(dut, valid_name).value)
                ready = int(getattr(dut, ready_name).value)
                key = valid_name
                values = tuple(int(getattr(dut, field).value) for field in fields)
                if key in self.stalled:
                    assert valid, f"{valid_name}在反压期间撤销"
                    assert values == self.stalled[key], f"{valid_name}反压字段变化"
                if valid and not ready:
                    self.stalled[key] = values
                else:
                    self.stalled.pop(key, None)

            self.aw += int(dut.m_axil_awvalid.value) and int(dut.m_axil_awready.value)
            self.w += int(dut.m_axil_wvalid.value) and int(dut.m_axil_wready.value)
            if int(dut.m_axil_bvalid.value) and int(dut.m_axil_bready.value):
                self.b += 1
                assert self.b <= self.aw and self.b <= self.w, "凭空AXI B响应"
            self.ar += int(dut.m_axil_arvalid.value) and int(dut.m_axil_arready.value)
            if int(dut.m_axil_rvalid.value) and int(dut.m_axil_rready.value):
                self.r += 1
                assert self.r <= self.ar, "凭空AXI R响应"


async def start_env(dut, seed=10, random_ready=True, max_delay=3):
    bfm = AxiLiteSlaveBfm(dut, seed, random_ready, max_delay)
    sink = CompletionSink(dut, seed + 1, random_ready)
    monitor = ProtocolMonitor(dut)
    cocotb.start_soon(bfm.run())
    cocotb.start_soon(sink.run())
    cocotb.start_soon(monitor.run())
    for _ in range(2):
        await RisingEdge(dut.clk)
    return bfm, sink, monitor


async def send_request(dut, *, write, address, length_dw, first_be=0xF,
                       last_be=None, requester_id=0x0001, tag=0x5A,
                       tc=0, attr=0, poisoned=False, is_64=False,
                       payload=None, gap_rng=None):
    if last_be is None:
        last_be = 0 if length_dw == 1 else 0xF
    # 统一在上升沿之后驱动valid，保证下一个FallingEdge能先观察到握手条件，
    # 避免调用方恰在FallingEdge后启动时请求被重复接受。
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_req_write.value = int(write)
    dut.mem_req_64bit.value = int(is_64)
    dut.mem_req_poisoned.value = int(poisoned)
    dut.mem_req_address.value = address
    dut.mem_req_length_dw.value = length_dw
    dut.mem_req_first_be.value = first_be
    dut.mem_req_last_be.value = last_be
    dut.mem_req_requester_id.value = requester_id
    dut.mem_req_tag.value = tag
    dut.mem_req_tc.value = tc
    dut.mem_req_attr.value = attr
    dut.mem_req_valid.value = 1
    await wait_ready(dut, "mem_req_valid", "mem_req_ready", 20000)
    await Timer(1, units="ps")
    dut.mem_req_valid.value = 0

    if not write:
        return
    if payload is None:
        payload = bytes((index * 29 + tag) & 0xFF for index in range(length_dw * 4))
    assert len(payload) == length_dw * 4
    for offset in range(0, len(payload), 16):
        if gap_rng is not None:
            for _ in range(gap_rng.randrange(3)):
                await RisingEdge(dut.clk)
        beat = payload[offset:offset + 16]
        dut.mem_w_data.value = int.from_bytes(beat.ljust(16, b"\x00"), "little")
        dut.mem_w_keep.value = (1 << len(beat)) - 1
        dut.mem_w_last.value = int(offset + len(beat) == len(payload))
        dut.mem_w_valid.value = 1
        await wait_ready(dut, "mem_w_valid", "mem_w_ready", 20000)
        await Timer(1, units="ps")
        dut.mem_w_valid.value = 0


def assert_completion(actual, expected: ExpectedCompletion):
    for name in ("status", "has_data", "byte_count", "lower_address",
                 "length_dw", "requester_id", "completer_id", "tag",
                 "tc", "attr"):
        assert actual[name] == getattr(expected, name), (
            f"Completion {name}: 期望{getattr(expected, name)!r}，"
            f"实际{actual[name]!r}")
    assert actual["payload"] == expected.payload


def apply_expected_write(memory, offset, payload, length_dw, first_be, last_be):
    for index in range(length_dw):
        be = byte_mask_for_dw(index, length_dw, first_be, last_be)
        for lane in range(4):
            if be & (1 << lane):
                memory[offset + index * 4 + lane] = payload[index * 4 + lane]


@cocotb.test()
async def checker_guard(dut):
    """错误Stub必须显式触发address、be、posted三个独立守卫。"""
    await reset_dut(dut)
    await Timer(1, units="ps")

    dut.mem_req_write.value = 1
    dut.mem_req_address.value = 0x80000040
    dut.mem_req_length_dw.value = 1
    dut.mem_req_first_be.value = 0x5
    dut.mem_req_last_be.value = 0
    dut.mem_req_valid.value = 1
    await wait_ready(dut, "mem_req_valid", "mem_req_ready")
    await Timer(1, units="ps")
    dut.mem_req_valid.value = 0

    dut.mem_w_data.value = 0x44332211
    dut.mem_w_keep.value = 0x000F
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready")
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0

    dut.m_axil_awready.value = 1
    dut.m_axil_wready.value = 1
    awaddr = None
    wstrb = None
    for _ in range(30):
        await FallingEdge(dut.clk)
        await Timer(2, units="ps")
        if int(dut.m_axil_awvalid.value) and int(dut.m_axil_awready.value):
            awaddr = int(dut.m_axil_awaddr.value)
        if int(dut.m_axil_wvalid.value) and int(dut.m_axil_wready.value):
            wstrb = int(dut.m_axil_wstrb.value)
        if awaddr is not None and wstrb is not None:
            # 当前FallingEdge只观察到了即将在下一个上升沿发生的握手；
            # 先让DUT真正采样ready，再撤销BFM驱动。
            await RisingEdge(dut.clk)
            break
    assert awaddr is not None and wstrb is not None, "AXI AW/W未完成"
    dut.m_axil_awready.value = 0
    dut.m_axil_wready.value = 0
    dut.m_axil_bvalid.value = 1
    for _ in range(30):
        await FallingEdge(dut.clk)
        if int(dut.m_axil_bvalid.value) and int(dut.m_axil_bready.value):
            await RisingEdge(dut.clk)
            break
    else:
        raise AssertionError("AXI B未握手")
    dut.m_axil_bvalid.value = 0

    posted_completion = False
    for _ in range(12):
        await FallingEdge(dut.clk)
        if int(dut.cpl_req_valid.value):
            posted_completion = True

    errors = []
    if awaddr != 0x40:
        errors.append(f"address错误: 期望00000040，实际{awaddr:08x}")
    if wstrb != 0x5:
        errors.append(f"be错误: 期望5，实际{wstrb:x}")
    if posted_completion:
        errors.append("posted错误: Memory Write产生了Completion")

    if os.getenv("K09_NEGATIVE_STUB", "0") == "1":
        marker = os.getenv("K09_NEGATIVE_MARKER")
        if marker:
            with open(marker, "w", encoding="utf-8") as stream:
                names = []
                if any("address错误" in item for item in errors):
                    names.append("address")
                if any("be错误" in item for item in errors):
                    names.append("be")
                if any("posted错误" in item for item in errors):
                    names.append("posted")
                stream.write("K09_NEGATIVE_CHECKER_OBSERVED " + " ".join(names))

    assert not errors, "；".join(errors)

    await Timer(1, units="ns")


@cocotb.test()
async def reference_model_exhaustive(dut):
    """独立穷举一/二DWORD BE跨度，防止黄金模型退化成popcount。"""
    await reset_dut(dut)
    from k09_model import plan_chunks, request_byte_count

    for first_be in range(16):
        if first_be == 0:
            brute = 1
        else:
            lanes = [lane for lane in range(4) if first_be & (1 << lane)]
            brute = max(lanes) - min(lanes) + 1
        assert request_byte_count(1, first_be, 0) == brute

    for first_be in range(1, 16):
        for last_be in range(1, 16):
            positions = [lane for lane in range(4)
                         if first_be & (1 << lane)]
            positions += [4 + lane for lane in range(4)
                          if last_be & (1 << lane)]
            brute = max(positions) - min(positions) + 1
            assert request_byte_count(2, first_be, last_be) == brute

    directed = {
        (0x000, 33): [32, 1],
        (0x040, 33): [16, 17],
        (0x070, 40): [4, 32, 4],
        (0xF80, 32): [32],
        (0x000, 1024): [32] * 32,
    }
    for key, expected in directed.items():
        assert plan_chunks(*key) == expected


@cocotb.test()
async def zero_length_and_bar_error_paths(dut):
    await reset_dut(dut)
    bfm, sink, _ = await start_env(dut, seed=20, random_ready=True)
    base = 0x80000000

    writes_before = len(bfm.writes)
    await send_request(
        dut, write=True, address=base + 0x80, length_dw=1,
        first_be=0, payload=b"\xde\xad\xbe\xef", tag=1)
    await wait_idle(dut)
    assert len(bfm.writes) == writes_before
    assert sink.queue.empty()

    reads_before = len(bfm.reads)
    await send_request(
        dut, write=False, address=base + 0x84, length_dw=1,
        first_be=0, tag=2)
    zero_cpl = await sink.get()
    expected_zero = make_sc_completions(
        bfm.memory, base, base + 0x84, 1, 0, 0,
        0x0001, 0x0100, 2, 0, 0)[0]
    assert_completion(zero_cpl, expected_zero)
    assert len(bfm.reads) == reads_before
    await wait_idle(dut)
    dut._log.info("K09_ZERO_COUNTS req=%d sc=%d queue_empty=%d",
                  int(dut.mem_request_count.value),
                  int(dut.sc_completion_count.value), int(sink.queue.empty()))
    assert sink.queue.empty(), "零长度Read产生了重复Completion"

    error_cases = [
        (base + 0x1000, 0, 1, 1),
        (base + 0x100, 1, 1, 1),
        (base + 0x100, 0, 0, 1),
        (0x1_0000_0100, 0, 1, 1),
        (base + 0xFFC, 0, 1, 2),  # 首DW命中、末DW越过BAR。
        (base + 0x100, 0, 1, 0),  # 防御性非法Length。
        (base + 0x000, 0, 1, 1025),
    ]
    for index, (address, probe, mse, length_dw) in enumerate(error_cases):
        dut._log.info(
            "K09_BAR_ERROR_CASE index=%d address=%x probe=%d mse=%d length=%d",
            index, address, probe, mse, length_dw)
        dut.bar0_probe_active.value = probe
        dut.memory_space_enable.value = mse
        before = len(bfm.reads)
        await send_request(
            dut, write=False, address=address, length_dw=length_dw,
            first_be=0xF, is_64=address > 0xFFFF_FFFF,
            tag=0x10 + index)
        try:
            actual = await sink.get()
        except Exception:
            dut._log.error(
                "K09_ERROR_TIMEOUT busy=%d mem_ready=%d cpl_valid=%d status=%d "
                "req_count=%d ur_count=%d ca_count=%d",
                int(dut.busy.value), int(dut.mem_req_ready.value),
                int(dut.cpl_req_valid.value), int(dut.cpl_req_status.value),
                int(dut.mem_request_count.value),
                int(dut.ur_completion_count.value),
                int(dut.ca_completion_count.value))
            raise
        expected = make_error_completion(
            1, 0x0001, 0x0100, 0x10 + index, 0, 0)
        assert_completion(actual, expected)
        assert len(bfm.reads) == before
        await wait_idle(dut)
    dut.bar0_probe_active.value = 0
    dut.memory_space_enable.value = 1

    # BAR位于32-bit地址空间两端时仍输出相同的BAR相对AXI地址。
    for tag, new_base in ((0x20, 0x00000000), (0x21, 0xFFFFF000)):
        dut.bar0_base.value = new_base
        read_log_start = len(bfm.reads)
        await send_request(
            dut, write=False, address=new_base, length_dw=1,
            first_be=0xF, tag=tag)
        assert_completion(
            await sink.get(), make_sc_completions(
                bfm.memory, new_base, new_base, 1, 0xF, 0,
                0x0001, 0x0100, tag, 0, 0)[0])
        await wait_idle(dut)
        assert len(bfm.reads) == read_log_start + 1
        assert bfm.reads[-1][0] == 0
    dut.bar0_base.value = base


@cocotb.test()
async def directed_memory_writes(dut):
    await reset_dut(dut)
    bfm, sink, _ = await start_env(dut, seed=30, random_ready=True, max_delay=5)
    base = 0x80000000
    model_memory = bytearray(bfm.memory)
    rng = random.Random(3030)
    cases = [
        (0x040, 1, 0x5, 0),
        (0x080, 2, 0x8, 0x1),
        (0x100, 5, 0xE, 0x7),
        (0x200, 32, 0xF, 0xF),
    ]
    for tag, (offset, length_dw, first_be, last_be) in enumerate(cases, 0x20):
        payload = bytes(rng.randrange(256) for _ in range(length_dw * 4))
        if offset == 0x040:
            bfm.inject_write_error(offset, 1)  # EXOKAY也属于成功响应。
        log_start = len(bfm.writes)
        await send_request(
            dut, write=True, address=base + offset, length_dw=length_dw,
            first_be=first_be, last_be=last_be, tag=tag,
            payload=payload, gap_rng=rng)
        await wait_idle(dut)
        apply_expected_write(
            model_memory, offset, payload, length_dw, first_be, last_be)
        accesses = bfm.writes[log_start:]
        assert len(accesses) == length_dw
        for index, (address, data, strobe, response) in enumerate(accesses):
            assert address == offset + index * 4 and response < 2
            assert data == int.from_bytes(payload[index * 4:index * 4 + 4], "little")
            assert strobe == byte_mask_for_dw(
                index, length_dw, first_be, last_be)
        assert bfm.memory == model_memory
        assert sink.queue.empty(), "Posted Write不得产生Completion"

    payload = bytes(range(16))
    bfm.inject_write_error(0x304, 2)
    log_start = len(bfm.writes)
    await send_request(
        dut, write=True, address=base + 0x300, length_dw=4,
        first_be=0xF, last_be=0xF, tag=0x30, payload=payload)
    await wait_idle(dut)
    accesses = bfm.writes[log_start:]
    assert len(accesses) == 2 and accesses[-1][3] == 2
    model_memory[0x300:0x304] = payload[:4]
    assert bfm.memory == model_memory
    assert sink.queue.empty()

    for tag, kwargs in (
        (0x31, {"address": base + 0x380, "poisoned": True}),
        (0x32, {"address": base + 0x1000}),
    ):
        log_start = len(bfm.writes)
        await send_request(
            dut, write=True, length_dw=2, first_be=0xF, last_be=0xF,
            tag=tag, payload=bytes(8), **kwargs)
        await wait_idle(dut)
        assert len(bfm.writes) == log_start
        assert sink.queue.empty()


@cocotb.test()
async def directed_memory_reads_and_splits(dut):
    await reset_dut(dut)
    bfm, sink, _ = await start_env(dut, seed=40, random_ready=True, max_delay=4)
    base = 0x80000000
    cases = [
        (0x000, 1, 0x5, 0),
        (0x004, 1, 0xA, 0),
        (0x008, 2, 0x8, 0x1),
        (0x040, 33, 0xE, 0x7),
        (0x070, 40, 0xF, 0xF),
        (0xF80, 32, 0xF, 0xF),
        (0x000, 1024, 0xF, 0xF),
    ]
    for tag, (offset, length_dw, first_be, last_be) in enumerate(cases, 0x40):
        if offset == 0x000 and length_dw == 1:
            bfm.inject_read_error(offset, 1)  # EXOKAY也必须形成SC。
        read_log_start = len(bfm.reads)
        expected = make_sc_completions(
            bfm.memory, base, base + offset, length_dw,
            first_be, last_be, 0x0001, 0x0100, tag, 3, 5)
        await send_request(
            dut, write=False, address=base + offset, length_dw=length_dw,
            first_be=first_be, last_be=last_be, tag=tag, tc=3, attr=5)
        for item in expected:
            assert_completion(await sink.get(), item)
        await wait_idle(dut, 100000)
        accesses = bfm.reads[read_log_start:]
        assert len(accesses) == length_dw
        for index, (address, data, response) in enumerate(accesses):
            assert address == offset + index * 4
            assert response < 2
            assert data == int.from_bytes(
                bfm.memory[address:address + 4], "little")


@cocotb.test()
async def axi_read_errors_hot_reset_and_snapshot(dut):
    await reset_dut(dut)
    bfm, sink, _ = await start_env(dut, seed=50, random_ready=True, max_delay=5)
    base = 0x80000000

    bfm.inject_read_error(0x200, 2)
    read_log_start = len(bfm.reads)
    await send_request(
        dut, write=False, address=base + 0x200, length_dw=4,
        first_be=0xF, last_be=0xF, tag=0x60)
    assert_completion(
        await sink.get(), make_error_completion(4, 0x0001, 0x0100, 0x60, 0, 0))
    await wait_idle(dut)
    assert [item[0] for item in bfm.reads[read_log_start:]] == [0x200]

    # 同一Chunk的中间和末DWORD错误：不得先提交半个SC，AR只执行到错误位置。
    for tag, offset, error_offset, expected_addresses in (
            (0x65, 0x240, 0x244, [0x240, 0x244]),
            (0x66, 0x260, 0x26C, [0x260, 0x264, 0x268, 0x26C])):
        bfm.inject_read_error(error_offset, 2 + (tag & 1))
        read_log_start = len(bfm.reads)
        await send_request(
            dut, write=False, address=base + offset, length_dw=4,
            first_be=0xF, last_be=0xF, tag=tag)
        assert_completion(
            await sink.get(), make_error_completion(
                4, 0x0001, 0x0100, tag, 0, 0))
        await wait_idle(dut)
        assert [item[0] for item in bfm.reads[read_log_start:]] == \
            expected_addresses
        assert sink.queue.empty()

    expected = make_sc_completions(
        bfm.memory, base, base, 33, 0xF, 0xF,
        0x0001, 0x0100, 0x61, 0, 0)
    bfm.inject_read_error(0x080, 3)
    read_log_start = len(bfm.reads)
    await send_request(
        dut, write=False, address=base, length_dw=33,
        first_be=0xF, last_be=0xF, tag=0x61)
    assert_completion(await sink.get(), expected[0])
    assert_completion(
        await sink.get(), make_error_completion(4, 0x0001, 0x0100, 0x61, 0, 0))
    await wait_idle(dut)
    assert [item[0] for item in bfm.reads[read_log_start:]] == \
        [index * 4 for index in range(33)]

    dut.hot_reset.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)
        assert int(dut.mem_req_ready.value) == 0
    dut.hot_reset.value = 0

    # 已握手Read必须使用BAR/BDF快照，随后配置变化不能追溯修改Completion。
    bfm.max_delay = 8
    expected = make_sc_completions(
        bfm.memory, base, base + 0x300, 8, 0xF, 0xF,
        0x0001, 0x0100, 0x62, 2, 1)
    send_task = cocotb.start_soon(send_request(
        dut, write=False, address=base + 0x300, length_dw=8,
        first_be=0xF, last_be=0xF, tag=0x62, tc=2, attr=1))
    await send_task
    assert int(dut.busy.value) == 1
    dut.hot_reset.value = 1
    dut.bar0_base.value = 0x90000000
    dut.bar0_probe_active.value = 1
    dut.memory_space_enable.value = 0
    dut.local_completer_id.value = 0x0200
    assert_completion(await sink.get(), expected[0])
    await wait_idle(dut)
    assert int(dut.mem_req_ready.value) == 0

    # Hot Reset撤销后，下一请求必须采用新的BAR/MSE/BDF，而非上一事务快照。
    dut.bar0_probe_active.value = 0
    dut.memory_space_enable.value = 1
    dut.hot_reset.value = 0
    await send_request(
        dut, write=False, address=base + 0x300, length_dw=1,
        first_be=0xF, tag=0x63)
    assert_completion(
        await sink.get(), make_error_completion(
            1, 0x0001, 0x0200, 0x63, 0, 0))
    await wait_idle(dut)

    new_base = 0x90000000
    expected = make_sc_completions(
        bfm.memory, new_base, new_base + 0x300, 1, 0xF, 0,
        0x0001, 0x0200, 0x64, 0, 0)
    await send_request(
        dut, write=False, address=new_base + 0x300, length_dw=1,
        first_be=0xF, tag=0x64)
    assert_completion(await sink.get(), expected[0])
    await wait_idle(dut)


@cocotb.test()
async def payload_protocol_error_is_contained(dut):
    """错误keep/last必须终止/Drain；保留错误前副作用，禁止后续副作用。"""
    await reset_dut(dut)
    bfm, sink, _ = await start_env(
        dut, seed=68, random_ready=False, max_delay=0)
    base = 0x80000000
    await send_descriptor_only(
        dut, write=True, address=base + 0x180, length_dw=4,
        first_be=0xF, last_be=0xF, tag=0x68)

    # Length=4应要求keep=ffff；故意只声明两个DWORD并提前last。
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = int.from_bytes(bytes(range(16)), "little")
    dut.mem_w_keep.value = 0x00FF
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 2000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0
    await wait_idle(dut)

    assert int(dut.payload_protocol_error_count.value) == 1
    assert int(dut.posted_drop_count.value) == 1
    assert int(dut.axi_write_count.value) == 0
    assert int(dut.cpl_req_valid.value) == 0
    assert not bfm.writes and sink.queue.empty()

    # 第二个请求先正确提交一个完整Beat，再在末Beat注入keep错误；既有AXI
    # 副作用必须保留，但错误Beat及其后不得产生访问或Completion。
    before_memory = bytearray(bfm.memory)
    await send_descriptor_only(
        dut, write=True, address=base + 0x1C0, length_dw=5,
        first_be=0xF, last_be=0xF, tag=0x69)
    first_payload = bytes(range(16))
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = int.from_bytes(first_payload, "little")
    dut.mem_w_keep.value = 0xFFFF
    dut.mem_w_last.value = 0
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 10000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0

    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = 0xAABBCCDD
    dut.mem_w_keep.value = 0x0003
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 10000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0
    await wait_idle(dut)

    assert len(bfm.writes) == 4
    assert [item[0] for item in bfm.writes] == [0x1C0, 0x1C4, 0x1C8, 0x1CC]
    expected_memory = bytearray(before_memory)
    expected_memory[0x1C0:0x1D0] = first_payload
    assert bfm.memory == expected_memory
    assert int(dut.payload_protocol_error_count.value) == 2
    assert int(dut.posted_drop_count.value) == 2
    assert sink.queue.empty()


@cocotb.test()
async def perst_cancels_all_inflight_states(dut):
    """在Write、Read和Completion关键状态异步复位，禁止残留valid或旧包。"""
    await reset_dut(dut)
    base = 0x80000000

    # IDLE。
    await assert_async_reset_cancels(dut)

    # W_FETCH：描述符已接受，尚未收到Payload。
    await send_descriptor_only(
        dut, write=True, address=base + 0x100, length_dw=4, tag=0x71)
    await wait_high(dut, "mem_w_ready")
    await assert_async_reset_cancels(dut)

    # W_AXI：Payload已接受，但AW/W均被反压。
    await send_descriptor_only(
        dut, write=True, address=base + 0x100, length_dw=1, tag=0x72)
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = 0x44332211
    dut.mem_w_keep.value = 0x000F
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 2000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0
    await wait_high(dut, "m_axil_awvalid")
    assert int(dut.m_axil_wvalid.value) == 1
    await assert_async_reset_cancels(dut)

    # W_AXI：只完成AW，W仍被反压。
    await send_descriptor_only(
        dut, write=True, address=base + 0x104, length_dw=1, tag=0x73)
    dut.m_axil_awready.value = 1
    dut.m_axil_wready.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = 0x88776655
    dut.mem_w_keep.value = 0x000F
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 2000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0
    await wait_high(dut, "m_axil_awvalid")
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert int(dut.m_axil_awvalid.value) == 0
    assert int(dut.m_axil_wvalid.value) == 1
    await assert_async_reset_cancels(dut)

    # W_AXI：只完成W，AW仍被反压。
    await send_descriptor_only(
        dut, write=True, address=base + 0x108, length_dw=1, tag=0x74)
    dut.m_axil_awready.value = 0
    dut.m_axil_wready.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = 0xCCBBAA99
    dut.mem_w_keep.value = 0x000F
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 2000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0
    await wait_high(dut, "m_axil_wvalid")
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert int(dut.m_axil_awvalid.value) == 1
    assert int(dut.m_axil_wvalid.value) == 0
    await assert_async_reset_cancels(dut)

    # W_B：AW与W已经独立完成，B响应尚未返回。
    await send_descriptor_only(
        dut, write=True, address=base + 0x10C, length_dw=1, tag=0x75)
    dut.m_axil_awready.value = 1
    dut.m_axil_wready.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    dut.mem_w_data.value = 0x88776655
    dut.mem_w_keep.value = 0x000F
    dut.mem_w_last.value = 1
    dut.mem_w_valid.value = 1
    await wait_ready(dut, "mem_w_valid", "mem_w_ready", 2000)
    await Timer(1, units="ps")
    dut.mem_w_valid.value = 0
    await wait_high(dut, "m_axil_awvalid")
    assert int(dut.m_axil_wvalid.value) == 1
    await RisingEdge(dut.clk)
    dut.m_axil_awready.value = 0
    dut.m_axil_wready.value = 0
    await wait_high(dut, "m_axil_bready")
    await assert_async_reset_cancels(dut)

    # R_AR：读地址被下游反压。
    await send_descriptor_only(
        dut, write=False, address=base + 0x200, length_dw=1, tag=0x76)
    await wait_high(dut, "m_axil_arvalid")
    await assert_async_reset_cancels(dut)

    # R_R：AR已经握手，等待R响应。
    await send_descriptor_only(
        dut, write=False, address=base + 0x204, length_dw=1, tag=0x77)
    await wait_high(dut, "m_axil_arvalid")
    dut.m_axil_arready.value = 1
    await RisingEdge(dut.clk)
    dut.m_axil_arready.value = 0
    await wait_high(dut, "m_axil_rready")
    await assert_async_reset_cancels(dut)

    # CPL_DESC：BAR miss产生UR，但描述符被K07反压。
    dut.cpl_req_ready.value = 0
    await send_descriptor_only(
        dut, write=False, address=base + 0x1000, length_dw=1, tag=0x78)
    await wait_high(dut, "cpl_req_valid")
    await assert_async_reset_cancels(dut)

    # CPL_DATA：零长度读的SC描述符已经握手，Payload被反压。
    dut.cpl_req_ready.value = 1
    dut.cpl_data_ready.value = 0
    await send_descriptor_only(
        dut, write=False, address=base + 0x208, length_dw=1,
        first_be=0, tag=0x79)
    await wait_high(dut, "cpl_req_valid")
    await RisingEdge(dut.clk)
    await wait_high(dut, "cpl_data_valid")
    await assert_async_reset_cancels(dut)


@cocotb.test()
async def randomized_100k_reference(dut):
    await reset_dut(dut)
    bfm, sink, _ = await start_env(
        dut, seed=20260807, random_ready=True, max_delay=3)
    rng = random.Random(20260807)
    count = int(os.getenv("K09_RANDOM_REQUESTS", "100000"))
    base = 0x90000000
    dut.bar0_base.value = base
    model_memory = bytearray(bfm.memory)
    expected_ur = 0
    expected_ca = 0
    expected_axi_write_errors = 0
    expected_poisoned_writes = 0
    length_histogram = {}

    for transaction in range(count):
        write = rng.random() < 0.54
        # 大多数请求保持短小以控制10万组回归时间；同时显式抽取所有
        # MPS/RCB/4KiB边界桶，不能只依赖Directed用例覆盖长读。
        if write and rng.random() < 0.01:
            length_dw = rng.choice((15, 16, 17, 31, 32))
        elif (not write) and rng.random() < 0.005:
            length_dw = rng.choice(
                (15, 16, 17, 31, 32, 33, 255, 256, 1023, 1024))
        else:
            length_dw = rng.choice((1, 1, 1, 1, 2, 2, 4, 8))
        length_histogram[length_dw] = length_histogram.get(length_dw, 0) + 1
        max_dw_offset = 1024 - length_dw
        dw_offset = rng.randrange(max_dw_offset + 1)
        offset = dw_offset * 4
        first_be = rng.randrange(16) if length_dw == 1 else rng.randrange(1, 16)
        last_be = 0 if length_dw == 1 else rng.randrange(1, 16)
        hit = rng.random() < 0.82
        probe = hit and rng.random() < 0.025
        mse = not (hit and rng.random() < 0.025)
        poisoned = write and rng.random() < 0.025
        inject_error = hit and mse and not probe and not poisoned and \
            not (length_dw == 1 and first_be == 0) and rng.random() < 0.02
        address = base + offset if hit else base + 0x1000 + offset
        is_64 = rng.random() < 0.25
        if not hit and rng.random() < 0.25:
            address |= 1 << 32
            is_64 = True
        tag = transaction & 0xFF
        requester = 0x0010 | ((transaction >> 8) & 0xE0)
        tc = transaction & 0x7
        attr = (transaction >> 3) & 0x7
        dut.bar0_probe_active.value = int(probe)
        dut.memory_space_enable.value = int(mse)
        write_log_start = len(bfm.writes)
        read_log_start = len(bfm.reads)

        if write:
            payload = bytes(rng.randrange(256) for _ in range(length_dw * 4))
            expected_poisoned_writes += int(poisoned)
            if inject_error:
                bfm.inject_write_error(offset, 2 + (transaction & 1))
                expected_axi_write_errors += 1
            await send_request(
                dut, write=True, address=address, length_dw=length_dw,
                first_be=first_be, last_be=last_be,
                requester_id=requester, tag=tag, tc=tc, attr=attr,
                poisoned=poisoned, is_64=is_64, payload=payload)
            await wait_idle(dut)
            write_executes = hit and mse and not probe and not poisoned and \
                not (length_dw == 1 and first_be == 0)
            accesses = bfm.writes[write_log_start:]
            expected_accesses = (1 if inject_error else length_dw) \
                if write_executes else 0
            assert len(accesses) == expected_accesses
            for index, (axi_address, data, strobe, response) in enumerate(accesses):
                assert axi_address == offset + index * 4
                assert data == int.from_bytes(
                    payload[index * 4:index * 4 + 4], "little")
                assert strobe == byte_mask_for_dw(
                    index, length_dw, first_be, last_be)
                assert (response >= 2) == (inject_error and index == 0)
            assert len(bfm.reads) == read_log_start
            if write_executes and not inject_error:
                apply_expected_write(
                    model_memory, offset, payload, length_dw, first_be, last_be)
            assert sink.queue.empty(), "随机Posted Write产生Completion"
        else:
            if inject_error:
                bfm.inject_read_error(offset, 2 + (transaction & 1))
            await send_request(
                dut, write=False, address=address, length_dw=length_dw,
                first_be=first_be, last_be=last_be,
                requester_id=requester, tag=tag, tc=tc, attr=attr,
                is_64=is_64)
            if not hit or not mse or probe:
                expected_items = [make_error_completion(
                    1, requester, 0x0100, tag, tc, attr)]
                expected_ur += 1
            elif inject_error:
                expected_items = [make_error_completion(
                    4, requester, 0x0100, tag, tc, attr)]
                expected_ca += 1
            else:
                expected_items = make_sc_completions(
                    model_memory, base, address, length_dw,
                    first_be, last_be, requester, 0x0100, tag, tc, attr)
            for item in expected_items:
                assert_completion(await sink.get(), item)
            await wait_idle(dut)
            accesses = bfm.reads[read_log_start:]
            read_executes = hit and mse and not probe and \
                not (length_dw == 1 and first_be == 0)
            expected_accesses = (1 if inject_error else length_dw) \
                if read_executes else 0
            assert len(accesses) == expected_accesses
            for index, (axi_address, data, response) in enumerate(accesses):
                assert axi_address == offset + index * 4
                assert data == int.from_bytes(
                    model_memory[axi_address:axi_address + 4], "little")
                assert (response >= 2) == (inject_error and index == 0)
            assert len(bfm.writes) == write_log_start

        if transaction % 1000 == 999:
            assert bfm.memory == model_memory

    assert bfm.memory == model_memory
    assert int(dut.mem_request_count.value) == count
    assert int(dut.mem_read_count.value) + int(dut.mem_write_count.value) == count
    assert int(dut.ur_completion_count.value) == expected_ur
    assert int(dut.ca_completion_count.value) == expected_ca
    assert int(dut.axi_read_error_count.value) == expected_ca
    assert int(dut.axi_write_error_count.value) == expected_axi_write_errors
    assert int(dut.poisoned_write_count.value) == expected_poisoned_writes
    if count >= 100000:
        for boundary_length in (15, 16, 17, 31, 32, 33, 255, 256, 1023, 1024):
            assert length_histogram.get(boundary_length, 0) > 0, (
                f"随机Length边界桶{boundary_length}未覆盖")
        assert (expected_ca + expected_axi_write_errors) >= count // 100
        assert expected_poisoned_writes >= count // 100
    dut._log.info(
        "K09_RANDOM_REQUESTS=%d ur=%d ca=%d axi_reads=%d axi_writes=%d "
        "axi_write_errors=%d poisoned_writes=%d boundary_lengths=%s",
        count, expected_ur, expected_ca,
        int(dut.axi_read_count.value), int(dut.axi_write_count.value),
        expected_axi_write_errors, expected_poisoned_writes,
        {key: length_histogram.get(key, 0) for key in
         (15, 16, 17, 31, 32, 33, 255, 256, 1023, 1024)})

    evidence_path = os.getenv("K09_RANDOM_EVIDENCE")
    if evidence_path:
        with open(evidence_path, "w", encoding="utf-8") as stream:
            stream.write(
                "K09_RANDOM_SIGNOFF seed=20260807 "
                f"requests={count} random_ready=1 max_delay=3 "
                f"ur={expected_ur} ca={expected_ca} "
                f"axi_reads={int(dut.axi_read_count.value)} "
                f"axi_writes={int(dut.axi_write_count.value)} "
                f"axi_write_errors={expected_axi_write_errors} "
                f"poisoned_writes={expected_poisoned_writes}\n")
