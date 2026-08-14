# KCU105 PCIe PHY/Gen3 调试记录总结

日期：2026-08-14

## 1. 当前结论

本轮已把问题拆分为两个层次验证：

1. K02 standalone PHY：确认 GT/QPLL1 和 Gen3 PHY 本身可以正常工作；
2. K11/K13 Endpoint：确认真实链路在 `Recovery.Speed` 发生 rate change，但当前仍未完成 Gen3 链路训练。

因此当前结论是：**K02 的 QPLL1 和 Gen3 PHY ready 正常；K13 的完整 Gen3 链路仍失败，首要故障点是 Recovery.Speed 期间 QPLL1 lock 丢失且未恢复。**

## 2. K02 standalone PHY 验证

### 仿真与实现

- Verilator：2/2 用例通过，10,000 组随机向量通过；
- VCS 真实 IP：PHY、GT Wizard、secureip 和 Receiver Detect 仿真通过；
- Vivado：综合、实现、DRC、CDC、时序和 bitgen 通过；
- 实现 WNS：`+0.977 ns`。

### 实板 ILA

重新生成带 `u_ila_k02` 的 bit/LTX，下载 KCU105 后抓取 8192 点窗口。关键状态全窗口保持稳定：

| 信号 | 结果 |
|---|---|
| GTHE3_COMMON `QPLL1LOCK` | `1` |
| `QPLL1RESET` / `QPLL1PD` | `0 / 0` |
| `phy_rate` | `2`，Gen3 |
| `PCIERATEGEN3` | `1` |
| `PCIEUSERGEN3RDY` | `1` |
| `RXRESETDONE` | `1` |
| Receiver Detect | 成功，`receiver_present=1` |

这证明 QPLL1 锁定、Gen3 rate 配置和 GT Gen3 ready 正常。K02 没有 LTSSM、TS1/TS2、Equalization 和枚举，因此 `RXVALID=0` 是预期现象，不能作为完整 PCIe Gen3 L0 通过证据。

详细记录见：[K02 standalone PHY 报告](k02-standalone-pcie-phy.md)。

## 3. K13 基于 `1ab305c` 的 Recovery.Speed 复测

按原参数重新综合/实现、生成 bit/LTX、重新上板，并使用完全相同的 PIPE ILA 触发器抓取：

1. LTSSM 进入 `Recovery.Speed`；
2. `phy_rate/rxrate: 0 -> 2`；
3. `PCIEUSERRATESTART` 产生脉冲，`PCIERATEGEN3` 置 1；
4. 随后 `QPLL1RESET: 0 -> 1`，`QPLL1LOCK: 1 -> 0`；
5. QPLL1 reset 释放后 lock 未恢复；
6. 最终 `PCIEUSERGEN3RDY=0`、`PhyStatus=0`、`data_valid=0`，LTSSM 停在 `Recovery.Speed`，Root Port 未枚举 Endpoint。

这说明 `1ab305c` 已使 rate-change 控制序列实际发生，但没有解决 QPLL1 在切速过程中的锁定恢复问题。该轮 WNS 为 `-0.228 ns`，属于诊断构建，不能作为正式实现时序通过。

详细记录见：[K13 CDR hold 验证报告](k13-cdr-hold-validation-20260814.md)。

## 4. 下一步计划

### P0：定位 QPLL1 lock 丢失的直接原因

以 `1ab305c` 为基线，保留相同 Recovery.Speed 触发条件，补充并对齐抓取：

- QPLL1 `QPLL1LOCK`、`QPLL1RESET`、`QPLL1PD`；
- `QPLLREFCLKLOST`、`QPLLFBCLKLOST`、QPLL lock detector/GT reset 状态；
- `PCIERATEIDLE`、`PCIERATEGEN3`、`PCIERATEQPLLRESET`、`PCIERATEQPLLPD`；
- `PCIEUSERRATESTART`、`PCIEUSERGEN3RDY`、`PhyStatus`、`RXRESETDONE`；
- LTSSM 状态和 Root Port 枚举结果。

重点确认 QPLL1 reset 的产生源、保持时长、释放条件，以及 rate change 后是否重新满足 QPLL1 的参考时钟和反馈时钟前置条件。

### P1：修复并重复完全相同的抓取

只修改 QPLL1/rate-change 相关控制，不绕过 `QPLL1LOCK` 检查。每次修改都执行：

1. 综合/实现并检查 DRC、CDC、WNS；
2. 生成 bit/LTX 并记录 SHA-256；
3. KCU105 重新下载；
4. 使用相同触发器、相同 pre-trigger 和相同采样深度抓取 Recovery.Speed；
5. 与本报告的失败窗口逐点对比。

### P2：验收标准

只有同时满足以下条件，才将 K13 Gen3 标记为 PASS：

- Recovery.Speed 后 QPLL1 lock 保持或恢复为 `1`；
- `PCIEUSERGEN3RDY=1`，`PhyStatus` 正常产生；
- RX `valid/data_valid` 恢复；
- LTSSM 继续经过 `Recovery.RcvrCfg` 并进入 `L0`；
- Root Port 能稳定枚举 Endpoint，且重复冷启动/复位结果一致。

若 QPLL1 已恢复而链路仍停滞，再继续分析 Equalization、TS1/TS2、Lane 0 极性/通道映射和 Root Port 配置，不再把 PHY lock 问题与协议训练问题混在一起。
