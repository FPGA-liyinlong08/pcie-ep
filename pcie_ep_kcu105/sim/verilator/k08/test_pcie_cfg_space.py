"""K08配置空间单模块cocotb测试。

生产RTL尚未建立时，先以错误Stub运行identity_and_bar_probe_guard，证明Checker会按
具体寄存器值检出身份、BAR尺寸和Byte Enable错误。其余测试在同一文件中逐步扩展。
"""

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from k08_cfg_model import CfgSpaceModel, SC, UR


TEST_BDF = 0x0100  # 01:00.0
NEGATIVE_MARKER = Path(__file__).with_name("negative_checker_observed.txt")
OUTPUT_NAMES = (
    "captured_bdf",
    "bdf_valid",
    "local_completer_id",
    "bar0_base",
    "bar0_probe_active",
    "memory_space_enable",
    "bus_master_enable",
    "max_payload_size",
    "max_read_request_size",
    "rcb_128b",
    "link_disable",
    "target_link_speed",
)


class CfgDriver:
    def __init__(self, dut):
        self.dut = dut

    async def reset(self):
        dut = self.dut
        dut.rst_n.value = 0
        dut.hot_reset.value = 0
        dut.link_up.value = 0
        dut.link_training.value = 0
        dut.dll_active.value = 0
        dut.link_speed.value = 0
        dut.link_width.value = 0
        dut.cfg_req_valid.value = 0
        dut.cfg_req_write.value = 0
        dut.cfg_req_dw_addr.value = 0
        dut.cfg_req_be.value = 0
        dut.cfg_req_wdata.value = 0
        dut.cfg_req_requester_id.value = 0
        dut.cfg_req_tag.value = 0
        dut.cfg_req_target_bdf.value = 0
        dut.cfg_rsp_ready.value = 0
        await ClockCycles(dut.clk, 4)
        await FallingEdge(dut.clk)
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 2)

    async def issue(
        self,
        *,
        write,
        addr,
        be=0xF,
        wdata=0,
        target_bdf=TEST_BDF,
        requester_id=0,
        tag=0,
        idle_cycles=0,
        timeout_cycles=32,
    ):
        dut = self.dut
        if idle_cycles:
            await ClockCycles(dut.clk, idle_cycles)
        await FallingEdge(dut.clk)
        dut.cfg_req_write.value = int(write)
        dut.cfg_req_dw_addr.value = addr
        dut.cfg_req_be.value = be
        dut.cfg_req_wdata.value = wdata
        dut.cfg_req_requester_id.value = requester_id
        dut.cfg_req_tag.value = tag
        dut.cfg_req_target_bdf.value = target_bdf
        # 先反压响应，避免一拍响应在Monitor采样前被立即消费。
        dut.cfg_rsp_ready.value = 0
        dut.cfg_req_valid.value = 1

        accepted = False
        for _ in range(timeout_cycles):
            if int(dut.cfg_req_ready.value):
                await RisingEdge(dut.clk)
                accepted = True
                break
            await RisingEdge(dut.clk)
            await FallingEdge(dut.clk)
        assert accepted, "配置请求在限定周期内没有握手"

        await FallingEdge(dut.clk)
        dut.cfg_req_valid.value = 0

        for _ in range(timeout_cycles):
            await RisingEdge(dut.clk)
            await ReadOnly()
            if int(dut.cfg_rsp_valid.value):
                return {
                    "status": int(dut.cfg_rsp_status.value),
                    "rdata": int(dut.cfg_rsp_rdata.value),
                    "completer_id": int(dut.cfg_rsp_completer_id.value),
                }
        raise AssertionError("配置响应在限定周期内没有出现")

    async def complete_response(self, response, stall_cycles=0):
        """检查反压稳定性，然后显式完成响应握手。"""
        dut = self.dut
        for _ in range(stall_cycles):
            await RisingEdge(dut.clk)
            await ReadOnly()
            assert int(dut.cfg_rsp_valid.value), "反压期间cfg_rsp_valid被撤销"
            observed = {
                "status": int(dut.cfg_rsp_status.value),
                "rdata": int(dut.cfg_rsp_rdata.value),
                "completer_id": int(dut.cfg_rsp_completer_id.value),
            }
            assert observed == response, "反压期间配置响应字段发生变化"

        await FallingEdge(dut.clk)
        dut.cfg_rsp_ready.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.cfg_rsp_ready.value = 0

    async def access(self, *, rsp_stall_cycles=0, **kwargs):
        response = await self.issue(**kwargs)
        await self.complete_response(response, rsp_stall_cycles)
        return response

    async def read(self, addr, **kwargs):
        return await self.access(write=False, addr=addr, **kwargs)

    async def write(self, addr, data, **kwargs):
        return await self.access(write=True, addr=addr, wdata=data, **kwargs)


class CfgCycleMonitor:
    """独立于Driver的逐周期协议监视器。

    在下降沿ReadOnly阶段采样下一上升沿的握手条件，再于上升沿后检查固定一拍响应、
    无凭空响应、Hot Reset门控和响应stall稳定性。
    """

    def __init__(self, dut):
        self.dut = dut
        self.request_handshakes = 0
        self.response_creations = 0
        self.response_handshakes = 0
        self._stalled_fields = None
        self.task = cocotb.start_soon(self._run())

    @staticmethod
    def _response_fields(dut):
        return (
            int(dut.cfg_rsp_status.value),
            int(dut.cfg_rsp_rdata.value),
            int(dut.cfg_rsp_completer_id.value),
        )

    async def _run(self):
        dut = self.dut
        while True:
            await FallingEdge(dut.clk)
            await ReadOnly()

            rst_n = int(dut.rst_n.value)
            hot_reset = int(dut.hot_reset.value)
            req_fire = bool(
                int(dut.cfg_req_valid.value) and int(dut.cfg_req_ready.value)
            )
            rsp_valid = int(dut.cfg_rsp_valid.value)
            rsp_ready = int(dut.cfg_rsp_ready.value)
            rsp_fire = bool(rsp_valid and rsp_ready)

            if not rst_n:
                assert int(dut.cfg_req_ready.value) == 0
                self._stalled_fields = None
                await RisingEdge(dut.clk)
                await ReadOnly()
                assert int(dut.cfg_rsp_valid.value) == 0
                continue

            if hot_reset:
                assert int(dut.cfg_req_ready.value) == 0

            if rsp_valid and not rsp_ready:
                fields = self._response_fields(dut)
                if self._stalled_fields is not None:
                    assert fields == self._stalled_fields, (
                        "独立Monitor检测到响应stall字段变化"
                    )
                self._stalled_fields = fields
            else:
                self._stalled_fields = None

            await RisingEdge(dut.clk)
            await ReadOnly()

            if req_fire:
                self.request_handshakes += 1
                self.response_creations += 1
                assert int(dut.cfg_rsp_valid.value) == 1, (
                    "请求握手后一拍没有产生响应"
                )
            elif not rsp_valid:
                assert int(dut.cfg_rsp_valid.value) == 0, "检测到凭空响应"

            if rsp_fire:
                self.response_handshakes += 1
                assert int(dut.cfg_rsp_valid.value) == 0, (
                    "响应握手后valid没有清除"
                )

            assert self.response_creations == self.request_handshakes


async def start_tb(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    driver = CfgDriver(dut)
    await driver.reset()
    driver.monitor = CfgCycleMonitor(dut)
    return driver


def assert_response(actual, expected, context=""):
    wanted = {
        "status": expected.status,
        "rdata": expected.rdata,
        "completer_id": expected.completer_id,
    }
    assert actual == wanted, f"{context}响应不符: 期望{wanted}，实际{actual}"


def assert_model_outputs(dut, model, context=""):
    expected = model.outputs
    for name in OUTPUT_NAMES:
        actual = int(getattr(dut, name).value)
        assert actual == expected[name], (
            f"{context}{name}不符: 期望0x{expected[name]:x}，实际0x{actual:x}"
        )


async def model_access(
    driver,
    model,
    *,
    write,
    addr,
    be=0xF,
    wdata=0,
    target_bdf=TEST_BDF,
    requester_id=0,
    tag=0,
    idle_cycles=0,
    rsp_stall_cycles=0,
    context="",
):
    expected = model.access(
        write=write,
        addr=addr,
        be=be,
        wdata=wdata,
        target_bdf=target_bdf,
    )
    actual = await driver.access(
        write=write,
        addr=addr,
        be=be,
        wdata=wdata,
        target_bdf=target_bdf,
        requester_id=requester_id,
        tag=tag,
        idle_cycles=idle_cycles,
        rsp_stall_cycles=rsp_stall_cycles,
    )
    assert_response(actual, expected, context)
    assert_model_outputs(driver.dut, model, context)
    return actual


async def pulse_hot_reset(dut, model):
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.cfg_req_ready.value) == 0
    model.hot_reset()
    assert_model_outputs(dut, model, "Hot Reset后")
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 0


async def set_link_state(dut, model, **kwargs):
    await FallingEdge(dut.clk)
    for name, value in kwargs.items():
        getattr(dut, name).value = value
    model.set_link_state(**kwargs)


@cocotb.test()
async def identity_and_bar_probe_guard(dut):
    """坏Stub必须完成全部操作后，由三个明确的值错误触发JUnit failure。"""
    # 每次运行先删除旧marker，防止历史结果误通过门禁。
    if NEGATIVE_MARKER.exists():
        NEGATIVE_MARKER.unlink()

    driver = await start_tb(dut)
    errors = []
    observed_guards = set()

    identity = await driver.read(0)
    if identity["status"] != SC:
        errors.append(f"Identity响应状态错误: {identity['status']:03b}")
    if identity["rdata"] != 0xE001_1234:
        observed_guards.add("identity")
        errors.append(
            f"Identity错误: 期望e0011234，实际{identity['rdata']:08x}"
        )

    await driver.write(4, 0xFFFF_FFFF, be=0xF)
    bar = await driver.read(4)
    if bar["rdata"] != 0xFFFF_F000:
        observed_guards.add("bar")
        errors.append(
            f"BAR0尺寸掩码错误: 期望fffff000，实际{bar['rdata']:08x}"
        )

    # 先置Command byte1的SERR位，再只写byte0为0；byte1必须保持不变。
    await driver.write(1, 0x0000_0147, be=0xF)
    await driver.write(1, 0x0000_0000, be=0x1)
    command = await driver.read(1)
    if command["rdata"] != 0x0010_0100:
        observed_guards.add("be")
        errors.append(
            "Byte Enable隔离错误: "
            f"期望00100100，实际{command['rdata']:08x}"
        )

    if os.getenv("K08_NEGATIVE_STUB") == "1" and observed_guards == {
        "identity", "bar", "be"
    }:
        NEGATIVE_MARKER.write_text(
            "K08_NEGATIVE_CHECKER_OBSERVED identity bar be\n",
            encoding="utf-8",
        )

    assert not errors, "；".join(errors)


@cocotb.test()
async def reset_image_and_read_byte_enables(dut):
    """读取全部1024 DW；配置读必须忽略全部16种Byte Enable。"""
    driver = await start_tb(dut)
    model = CfgSpaceModel()
    assert len(model.rules) == 1024
    assert model.rules[0].reset_value == 0xE001_1234
    assert model.rules[4].special == "bar0_4k_probe"
    assert_model_outputs(dut, model, "复位值")

    address_coverage = set()
    for addr in range(1024):
        be = addr & 0xF
        await model_access(
            driver,
            model,
            write=False,
            addr=addr,
            be=be,
            context=f"DW{addr:03x}/BE{be:x}: ",
        )
        address_coverage.add(addr)

    for be in range(16):
        rsp = await driver.read(0, be=be)
        assert rsp["rdata"] == 0xE001_1234, f"配置读错误依赖BE={be:x}"

    assert len(address_coverage) == 1024
    assert model.read_dw(0x100 // 4) == 0
    assert model.read_dw(0xFFC // 4) == 0


@cocotb.test()
async def all_dwords_all_bits_and_byte_enables(dut):
    """1024 DW逐bit写0/1，并对所有可写寄存器遍历16种BE。"""
    driver = await start_tb(dut)
    model = CfgSpaceModel()
    bit_coverage = set()
    dword_count = int(os.getenv("K08_BIT_DWORDS", "1024"))
    short_allowed = os.getenv("K08_ALLOW_SHORT_DIRECTED") == "1"
    assert dword_count == 1024 or (short_allowed and 1 <= dword_count <= 1024)

    for addr in range(dword_count):
        for bit in range(32):
            values = (1 << bit, (~(1 << bit)) & 0xFFFF_FFFF)
            for value_index, value in enumerate(values):
                prefix = f"DW{addr:03x}/bit{bit}/data{value:08x}: "
                await model_access(
                    driver,
                    model,
                    write=True,
                    addr=addr,
                    be=0xF,
                    wdata=value,
                    context=prefix,
                )
                # one-hot检查相邻DW，one-cold轮转检查所有可写状态哨兵，
                # 证明写当前地址不会污染其他寄存器。
                if value_index == 0:
                    sentinel = (addr + 1) & 0x3FF
                else:
                    sentinels = (1, 4, 0x048 // 4, 0x050 // 4, 0x070 // 4)
                    sentinel = sentinels[(addr * 32 + bit) % len(sentinels)]
                    if sentinel == addr:
                        sentinel = sentinels[(addr * 32 + bit + 1) % len(sentinels)]
                await model_access(
                    driver,
                    model,
                    write=False,
                    addr=sentinel,
                    context=f"{prefix}跨DW哨兵{sentinel:03x}: ",
                )
                await model_access(
                    driver,
                    model,
                    write=False,
                    addr=addr,
                    be=(bit + addr) & 0xF,
                    context=prefix,
                )
            bit_coverage.add((addr, bit))

    for addr in (0x004 // 4, 0x010 // 4, 0x048 // 4, 0x050 // 4, 0x070 // 4):
        for be in range(16):
            data = (0xA5C3_6996 ^ (addr << 16) ^ (be * 0x1111_1111)) & 0xFFFF_FFFF
            await model_access(
                driver,
                model,
                write=True,
                addr=addr,
                be=be,
                wdata=data,
                context=f"可写DW{addr:03x}/BE{be:x}: ",
            )
            await model_access(driver, model, write=False, addr=addr)

    assert len(bit_coverage) == dword_count * 32


@cocotb.test()
async def bdf_bar_and_control_directed(dut):
    """验证BDF路由、BAR探测、Command和受限控制字段。"""
    driver = await start_tb(dut)
    model = CfgSpaceModel()

    # 尚未捕获时，Device或Function非0都必须UR且无副作用。
    for bad_bdf in (0x0101, 0x0108):
        rsp = await model_access(
            driver, model, write=False, addr=0, target_bdf=bad_bdf
        )
        assert rsp["status"] == UR
        assert not model.bdf_valid

    await model_access(
        driver,
        model,
        write=False,
        addr=0,
        target_bdf=TEST_BDF,
        requester_id=0xBEEF,
        tag=0x5A,
        rsp_stall_cycles=7,
    )
    assert model.captured_bdf == TEST_BDF

    command_before = model.command
    for bad_bdf in (0x0200, 0x0108, 0x0101):
        rsp = await model_access(
            driver,
            model,
            write=True,
            addr=1,
            be=0xF,
            wdata=0xFFFF_FFFF,
            target_bdf=bad_bdf,
        )
        assert rsp["status"] == UR
        assert model.command == command_before

    # Command完整掩码及零BE无副作用。
    await model_access(driver, model, write=True, addr=1, be=0xF, wdata=0xFFFF_FFFF)
    assert model.command == CfgSpaceModel.COMMAND_RW_MASK
    await model_access(driver, model, write=True, addr=1, be=0, wdata=0)
    assert model.command == CfgSpaceModel.COMMAND_RW_MASK

    # BAR探测保留真实基址，非探测写退出probe并按Byte Enable合并。
    await model_access(driver, model, write=True, addr=4, be=0xF, wdata=0xC123_4567)
    assert model.bar0_base == 0xC123_4000
    saved_base = model.bar0_base
    await model_access(driver, model, write=True, addr=4, be=0xF, wdata=0xFFFF_FFFF)
    assert model.bar0_probe_active and model.bar0_base == saved_base
    probe_rsp = await model_access(driver, model, write=False, addr=4)
    assert probe_rsp["rdata"] == 0xFFFF_F000
    await model_access(driver, model, write=True, addr=4, be=0x8, wdata=0x5A00_0000)
    assert not model.bar0_probe_active
    assert model.bar0_base == 0x5A23_4000

    for addr in list(range(5, 10)) + [0x030 // 4]:
        await model_access(driver, model, write=True, addr=addr, wdata=0xFFFF_FFFF)
        rsp = await model_access(driver, model, write=False, addr=addr)
        assert rsp["rdata"] == 0

    # MRRS仅接受0..5；6/7保持旧值，同时其他可写位仍更新。
    for mrrs in range(6):
        await model_access(
            driver, model, write=True, addr=0x048 // 4, wdata=(mrrs << 12) | 0x1F
        )
        assert model.outputs["max_read_request_size"] == mrrs
    for invalid in (6, 7):
        await model_access(
            driver, model, write=True, addr=0x048 // 4, wdata=invalid << 12
        )
        assert model.outputs["max_read_request_size"] == 5

    # Target Link Speed只接受线路编码1/2/3。
    for wire_value, internal in ((1, 0), (2, 1), (3, 2)):
        await model_access(
            driver, model, write=True, addr=0x070 // 4, wdata=wire_value
        )
        assert model.target_link_speed == internal
    for invalid in (0, 4, 15):
        await model_access(
            driver, model, write=True, addr=0x070 // 4, wdata=invalid
        )
        assert model.target_link_speed == 2


@cocotb.test()
async def link_status_retrain_and_reset_timing(dut):
    """动态Link Status、Retrain脉冲、Hot Reset与PERST时序。"""
    driver = await start_tb(dut)
    model = CfgSpaceModel()

    # PERST#有效期间，即使上游错误保持请求valid也不得握手或产生响应。
    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    dut.cfg_req_valid.value = 1
    dut.cfg_req_target_bdf.value = TEST_BDF
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.cfg_req_ready.value) == 0
    assert int(dut.cfg_rsp_valid.value) == 0
    await FallingEdge(dut.clk)
    dut.cfg_req_valid.value = 0
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Hot Reset有效期间同样阻止新请求；撤销前不得泄漏响应。
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 1
    dut.cfg_req_valid.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert int(dut.cfg_req_ready.value) == 0
        assert int(dut.cfg_rsp_valid.value) == 0
        await FallingEdge(dut.clk)
    dut.cfg_req_valid.value = 0
    dut.hot_reset.value = 0

    # 先建立可观察配置状态。
    await model_access(driver, model, write=False, addr=0)
    await model_access(driver, model, write=True, addr=1, wdata=0x0000_0006)
    await model_access(driver, model, write=True, addr=4, wdata=0xC000_1000)

    for speed in range(4):
        for width in (0, 1, 2, 7):
            for flags in range(8):
                await set_link_state(
                    dut,
                    model,
                    link_up=flags & 1,
                    link_training=(flags >> 1) & 1,
                    dll_active=(flags >> 2) & 1,
                    link_speed=speed,
                    link_width=width,
                )
                await model_access(driver, model, write=False, addr=0x050 // 4)
                assert model.command == 0x0006
                assert model.bar0_base == 0xC000_1000

    pulse_count = 0

    async def count_retrain_pulses():
        nonlocal pulse_count
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            if int(dut.retrain_link_pulse.value):
                pulse_count += 1

    monitor = cocotb.start_soon(count_retrain_pulses())
    before = pulse_count
    await model_access(
        driver,
        model,
        write=True,
        addr=0x050 // 4,
        be=0x1,
        wdata=1 << 5,
    )
    await ClockCycles(dut.clk, 2)
    assert pulse_count == before + 1, "Retrain Link写1没有产生恰好一拍脉冲"
    await model_access(
        driver, model, write=True, addr=0x050 // 4, be=0x1, wdata=0
    )
    await ClockCycles(dut.clk, 2)
    assert pulse_count == before + 1, "Retrain Link写0错误地产生脉冲"
    monitor.kill()

    # 在响应反压期间Hot Reset：响应必须保持，但可写状态与BDF立即清除。
    pending = await driver.issue(write=False, addr=0, target_bdf=TEST_BDF)
    held = dict(pending)
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()
    model.hot_reset()
    assert int(dut.cfg_req_ready.value) == 0
    assert int(dut.cfg_rsp_valid.value) == 1
    assert {
        "status": int(dut.cfg_rsp_status.value),
        "rdata": int(dut.cfg_rsp_rdata.value),
        "completer_id": int(dut.cfg_rsp_completer_id.value),
    } == held
    assert_model_outputs(dut, model, "Hot Reset并发响应后")
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 0
    await driver.complete_response(held, stall_cycles=3)
    await model_access(driver, model, write=False, addr=0)

    # Hot Reset与Ready同拍：既有响应恰好完成一次握手，同时配置状态复位。
    same_cycle = await driver.issue(write=False, addr=0, target_bdf=TEST_BDF)
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 1
    dut.cfg_rsp_ready.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()
    model.hot_reset()
    assert int(dut.cfg_rsp_valid.value) == 0
    assert int(dut.cfg_req_ready.value) == 0
    assert same_cycle["status"] == SC
    assert_model_outputs(dut, model, "Hot Reset与Ready同拍后")
    await FallingEdge(dut.clk)
    dut.hot_reset.value = 0
    dut.cfg_rsp_ready.value = 0
    await model_access(driver, model, write=False, addr=0)

    # PERST与K07共用core reset，可以直接取消正在反压的响应。
    await driver.issue(write=False, addr=0)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.cfg_rsp_valid.value) == 0
    model.reset()
    assert_model_outputs(dut, model, "PERST后")
    await ClockCycles(dut.clk, 2)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    await model_access(driver, model, write=False, addr=0)


@cocotb.test()
async def randomized_100k_reference(dut):
    """固定种子的至少100,000个配置事务，与独立模型逐事务比较。"""
    count = int(os.getenv("K08_RANDOM_TRANSACTIONS", "100000"))
    seed = int(os.getenv("K08_RANDOM_SEED", "20260807"))
    short_allowed = os.getenv("K08_ALLOW_SHORT_RANDOM") == "1"
    assert count >= 100_000 or short_allowed
    rng = random.Random(seed)
    driver = await start_tb(dut)
    model = CfgSpaceModel()
    address_coverage = set()
    be_coverage = set()
    special = (1, 4, 0x048 // 4, 0x050 // 4, 0x070 // 4)

    for index in range(count):
        if index and index % 25_000 == 0:
            await driver.reset()
            model.reset()
            model.set_link_state(
                link_up=0, link_training=0, dll_active=0, link_speed=0, link_width=0
            )
        elif index and index % 10_000 == 0:
            await pulse_hot_reset(dut, model)

        if index % 997 == 0:
            await set_link_state(
                dut,
                model,
                link_up=rng.randrange(2),
                link_training=rng.randrange(2),
                dll_active=rng.randrange(2),
                link_speed=rng.randrange(4),
                link_width=rng.randrange(8),
            )

        addr = rng.choice(special) if rng.random() < 0.45 else rng.randrange(1024)
        be = rng.randrange(16)
        relation = rng.randrange(10)
        if relation < 7:
            target = TEST_BDF
        elif relation == 7:
            target = 0x0200
        elif relation == 8:
            target = 0x0108
        else:
            target = 0x0101

        stall = 64 if rng.randrange(1000) == 0 else rng.randrange(5)
        idle = rng.randrange(4)
        await model_access(
            driver,
            model,
            write=bool(rng.getrandbits(1)),
            addr=addr,
            be=be,
            wdata=rng.getrandbits(32),
            target_bdf=target,
            requester_id=rng.getrandbits(16),
            tag=rng.getrandbits(8),
            idle_cycles=idle,
            rsp_stall_cycles=stall,
            context=f"随机事务{index}/seed={seed}: ",
        )
        address_coverage.add(addr)
        be_coverage.add(be)

    if not short_allowed:
        assert len(address_coverage) == 1024, (
            f"随机地址覆盖不足: {len(address_coverage)}/1024"
        )
        assert be_coverage == set(range(16))
