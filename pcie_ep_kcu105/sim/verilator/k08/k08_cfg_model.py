"""K08 Type-0配置空间的独立Python参考模型。

本模型是测试平台的黄金规则，不读取DUT内部状态，也不复用RTL case表达式。
生产RTL出现后，directed和随机回归都应以本文件为唯一事务级期望来源。
"""

from dataclasses import dataclass


SC = 0b000
UR = 0b001


def byte_enable_mask(be: int) -> int:
    """把4-bit Byte Enable扩展为32-bit掩码。"""
    mask = 0
    for lane in range(4):
        if be & (1 << lane):
            mask |= 0xFF << (lane * 8)
    return mask


def merge_bytes(old: int, new: int, be: int) -> int:
    mask = byte_enable_mask(be)
    return ((old & ~mask) | (new & mask)) & 0xFFFF_FFFF


@dataclass(frozen=True)
class CfgResponse:
    status: int
    rdata: int
    completer_id: int


@dataclass(frozen=True)
class DwRule:
    """一个配置DWORD的复位/位属性描述。"""

    reset_value: int = 0
    rw_mask: int = 0
    dynamic_mask: int = 0
    special: str = ""


def build_rule_table():
    """建立完整1024-DW黄金属性表；未实现项显式为R0/WI。"""
    table = [DwRule() for _ in range(1024)]

    def put(byte_addr, **kwargs):
        table[byte_addr // 4] = DwRule(**kwargs)

    put(0x000, reset_value=0xE001_1234)
    put(0x004, reset_value=0x0010_0000, rw_mask=0x0000_0547)
    put(0x008, reset_value=0xFF00_0001)
    put(0x00C, reset_value=0)
    put(0x010, reset_value=0, rw_mask=0xFFFF_F000, special="bar0_4k_probe")
    put(0x02C, reset_value=0xE001_1234)
    put(0x034, reset_value=0x0000_0040)
    put(0x040, reset_value=0x0002_0010)
    put(0x044, reset_value=0)
    put(0x048, reset_value=0x0000_2000, rw_mask=0x0000_701F,
        special="mrrs_0_to_5")
    put(0x04C, reset_value=0x0010_0013)
    put(0x050, reset_value=0x0001_0000, rw_mask=0x0000_02D8,
        dynamic_mask=0x2BFF_0000, special="retrain_w1_pulse")
    put(0x064, reset_value=0)
    put(0x068, reset_value=0)
    put(0x06C, reset_value=0x0000_000E)
    put(0x070, reset_value=0x0000_0003, rw_mask=0x0000_000F,
        special="target_speed_1_to_3")
    return tuple(table)


RULE_TABLE = build_rule_table()


class CfgSpaceModel:
    """K08-CFG-SPACE-v1的事务级状态模型。"""

    COMMAND_RW_MASK = RULE_TABLE[0x004 // 4].rw_mask
    DEVICE_CONTROL_RW_MASK = RULE_TABLE[0x048 // 4].rw_mask
    LINK_CONTROL_RW_MASK = RULE_TABLE[0x050 // 4].rw_mask
    rules = RULE_TABLE

    def __init__(self):
        self.link_up = 0
        self.link_training = 0
        self.dll_active = 0
        self.link_speed = 0
        self.link_width = 0
        self.reset()

    def reset(self) -> None:
        self.captured_bdf = 0
        self.bdf_valid = False
        self.command = 0
        self.bar0_base = 0
        self.bar0_probe_active = False
        self.device_control = 0x2000
        self.link_control = 0
        self.target_link_speed = 2  # 项目编码：2=Gen3；配置空间编码为3
        self.retrain_link_pulse = False

    hot_reset = reset

    def set_link_state(
        self,
        *,
        link_up=None,
        link_training=None,
        dll_active=None,
        link_speed=None,
        link_width=None,
    ) -> None:
        if link_up is not None:
            self.link_up = int(bool(link_up))
        if link_training is not None:
            self.link_training = int(bool(link_training))
        if dll_active is not None:
            self.dll_active = int(bool(dll_active))
        if link_speed is not None:
            self.link_speed = int(link_speed) & 0x3
        if link_width is not None:
            self.link_width = int(link_width) & 0x7

    def read_dw(self, addr: int) -> int:
        addr &= 0x3FF
        rule = self.rules[addr]
        if addr == 0x004 // 4:
            return rule.reset_value | (self.command & rule.rw_mask)
        if addr == 0x010 // 4:
            return 0xFFFF_F000 if self.bar0_probe_active else self.bar0_base
        if addr == 0x048 // 4:
            return self.device_control & rule.rw_mask
        if addr == 0x050 // 4:
            # 非法内部编码3按Gen1（线路编码1）报告。
            speed = self.link_speed + 1 if self.link_speed < 3 else 1
            width = 1 if self.link_up and self.link_width == 1 else 0
            return (
                (self.link_control & 0xFFFF)
                | ((speed & 0xF) << 16)
                | ((width & 0x3F) << 20)
                | ((self.link_training & 1) << 27)
                | ((self.dll_active & 1) << 29)
            )
        if addr == 0x070 // 4:
            return (self.target_link_speed + 1) & 0xF
        return rule.reset_value

    def _write_dw(self, addr: int, data: int, be: int) -> None:
        addr &= 0x3FF
        data &= 0xFFFF_FFFF
        be &= 0xF
        self.retrain_link_pulse = False
        rule = self.rules[addr]

        if addr == 0x004 // 4:
            merged = merge_bytes(self.command, data, be)
            self.command = merged & rule.rw_mask
        elif addr == 0x010 // 4:
            if be == 0xF and data == 0xFFFF_FFFF:
                self.bar0_probe_active = True
            else:
                merged = merge_bytes(self.bar0_base, data, be)
                self.bar0_base = merged & rule.rw_mask
                self.bar0_probe_active = False
        elif addr == 0x048 // 4:
            merged = merge_bytes(self.device_control, data, be)
            candidate = merged & rule.rw_mask
            # MRRS线路编码6/7为保留值；写入时保持旧的合法编码。
            if ((candidate >> 12) & 0x7) > 5:
                candidate = (
                    (candidate & ~0x7000) | (self.device_control & 0x7000)
                )
            self.device_control = candidate
        elif addr == 0x050 // 4:
            merged = merge_bytes(self.link_control, data, be)
            self.link_control = merged & rule.rw_mask
            self.retrain_link_pulse = bool(
                (be & 0x1) and (data & (1 << 5))
            )
        elif addr == 0x070 // 4:
            old_wire_value = self.target_link_speed + 1
            merged = merge_bytes(old_wire_value, data, be)
            requested = merged & 0xF
            if requested in (1, 2, 3):
                self.target_link_speed = requested - 1

    def access(
        self,
        *,
        write: bool,
        addr: int,
        be: int,
        wdata: int,
        target_bdf: int,
    ) -> CfgResponse:
        """执行一次已握手请求，并返回应产生的响应。"""
        target_bdf &= 0xFFFF
        function_number = target_bdf & 0x7
        device_number = (target_bdf >> 3) & 0x1F
        # 脉冲在每个新事务开始前自动撤销；UR也不能延长上一次脉冲。
        self.retrain_link_pulse = False

        if function_number != 0:
            cid = self.captured_bdf if self.bdf_valid else 0
            return CfgResponse(UR, 0, cid)

        if (
            self.bdf_valid
            and device_number != ((self.captured_bdf >> 3) & 0x1F)
        ):
            return CfgResponse(UR, 0, self.captured_bdf)

        # 固件临时Bus Number切换到OS最终Bus Number时，更新完整BDF。
        if not self.bdf_valid or target_bdf != self.captured_bdf:
            self.captured_bdf = target_bdf
            self.bdf_valid = True

        if write:
            self._write_dw(addr, wdata, be)
            rdata = 0
        else:
            self.retrain_link_pulse = False
            rdata = self.read_dw(addr)

        return CfgResponse(SC, rdata, self.captured_bdf)

    @property
    def outputs(self):
        return {
            "captured_bdf": self.captured_bdf,
            "bdf_valid": int(self.bdf_valid),
            "local_completer_id": self.captured_bdf if self.bdf_valid else 0,
            "bar0_base": self.bar0_base,
            "bar0_probe_active": int(self.bar0_probe_active),
            "memory_space_enable": (self.command >> 1) & 1,
            "bus_master_enable": (self.command >> 2) & 1,
            "max_payload_size": 0,
            "max_read_request_size": (self.device_control >> 12) & 0x7,
            "rcb_128b": (self.link_control >> 3) & 1,
            "link_disable": (self.link_control >> 4) & 1,
            "target_link_speed": self.target_link_speed,
        }
