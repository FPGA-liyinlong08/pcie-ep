# K14 Phase D1：K02 Golden PHY Rate-Change Contract

## 结论

2026-08-25 在同一块 KCU105 上连续采集的 5 次 K02 Golden Gen1→Gen3
切速全部通过。以 `PHY_RATE=Gen3`/事件记录器起点为时间零，QPLL1LOCK 在
78.000～78.344 us 恢复，首个有效 PHYSTATUS 在 101.528～113.164 us 出现；
最终 5 次均满足 `PHY_RATE=2`、`QPLL1LOCK=1`、`PCIERATEGEN3=1` 和
`PCIEUSERGEN3RDY=1`，且未发生 QPLL re-lock 后再次丢锁。

最重要的逐拍控制结论是：Golden 切速包在切速前和切速期间均保持
`as_cdr_hold_req=0`。这与退役 K13 replay 的 CDR-hold 假设不同，新的
`pcie_phy_command_ctrl` 必须按本报告的实测值实现。

## 构建与测量方法

- Vivado：2021.2；PHY 时钟：250 MHz（4 ns/拍）。
- Golden 顶层：`kcu105_pcie_phy_bringup_top`，由 `phy_bringup_seq →
  phy_ctrl → pcie_phy_x1_gen3` 驱动。
- 构建参数：`K02_PHY_CTRL_WAIT_AFTER_READY_NS=2000000000`，ILA 开启。
- bitstream SHA256：
  `93717cc5e2631078da49bb0d97fad2f2d687c3d0f321450e4a0c3609120a6c25`。
- ILA 在 `seq_state_w == S_DONE (4'h8)` 时触发，事件记录器保存相对于本次
  rate change 的 QPLL fall/rise、PHYSTATUS 和完成时间，避免 8192 点窗口
  无法覆盖约 110 us 全过程的问题。
- 机器判定脚本：`scripts/analyze_k02_golden_trace.py`。

原计划使用 3,000,000,000 ns arm delay。Vivado 2021.2 的 `-generic` 在
参数类型转换前将该无类型十进制值按 32 位有符号整数解析，导致绑定为负数并跳过
arm window。RTL 纳秒参数已改为 `longint unsigned`，实现脚本同时把外部 generic
限制为 `1..2000000000`。本次有效测量使用 2,000,000,000 ns。第一次
`capture-wait` 和只覆盖约 24.6 us 的 `S_GEN3_WAIT` 早期采样不计入 5 次签署样本。

## 五次有效样本

| CSV 时间戳 | QPLL fall | QPLL rise | QPLL rise | PHYSTATUS | PHYSTATUS | final valid | 结果 |
|---|---:|---:|---:|---:|---:|---:|---|
| 17:28:51 | 10 拍 | 19,560 拍 | 78.240 us | 27,349 拍 | 109.396 us | `0x3b` | PASS |
| 17:29:38 | 10 拍 | 19,520 拍 | 78.080 us | 27,432 拍 | 109.728 us | `0x3b` | PASS |
| 17:30:21 | 10 拍 | 19,503 拍 | 78.012 us | 28,291 拍 | 113.164 us | `0x3b` | PASS |
| 17:31:04 | 10 拍 | 19,586 拍 | 78.344 us | 25,382 拍 | 101.528 us | `0x3b` | PASS |
| 17:31:47 | 9 拍 | 19,500 拍 | 78.000 us | 26,351 拍 | 105.404 us | `0x3b` | PASS |

CSV SHA256：

- `20260825_172851_k02_phy.csv`：`666d69fdd53ccf99475416133008c8a95b6fc34027c929423f3860b07aac6fdc`
- `20260825_172938_k02_phy.csv`：`ad6b98e61fbede840235bbdff730fed77664fb981a006280800ea32224e6fb03`
- `20260825_173021_k02_phy.csv`：`91c7f9249d2b6eb1712bbaaf3b6979d45d88370571d584f48d535433a5e3b411`
- `20260825_173104_k02_phy.csv`：`3c9d8a86d84428e6eecbe1e8bb8a63b2b20de7e5e2cba3345c66e1208c31f5e4`
- `20260825_173147_k02_phy.csv`：`f23edf1857c2ada53475d7211b26159a1caa1a8c4de4a30c9081c2453bf8efb8`

这些原始 CSV/ILA 位于 gitignored 的 `fpga/kcu105/build_k02/capture/`，报告中的
哈希用于把后续分析结果绑定到原始现场。

## Golden raw-command contract

从 `S_GEN1_OFF_GAP` 到切速完成，外部 PHY 命令必须满足：

| 信号 | pre-rate/gap | apply/wait |
|---|---:|---:|
| `PHY_POWERDOWN` | P0 (`2'b00`) | P0 (`2'b00`) |
| `PHY_TXDETECTRX` | 0 | 0 |
| `PHY_TXELECIDLE` | 1 | 1 |
| `as_mac_in_detect` | 0 | 0 |
| `as_cdr_hold_req` | 0 | 0 |
| `PHY_RATE` | Gen1 (`2'b00`) | Gen3 (`2'b10`) |
| TXEQ/RXEQ controls | 0 | 0 |

`phy_bringup_seq` 源码定义 10 us（2500 拍）pre-rate gap；之后只改变
`PHY_RATE`。`PCIERATEQPLLRESET`、`QPLL1RESET`、`PCIERATEGEN3` 和
`PCIEUSERGEN3RDY` 是 K02 PHY/GT 内部对该 raw command 的响应和诊断证据，
不是 wrapper 对 controller 暴露的额外命令或完成输入。生产 controller 的语义
完成条件使用 fresh PHYSTATUS 边沿；QPLL/Gen3-ready 继续由 D3/D4 ILA 证明。

## D2/D3 验收窗口

- 命令顺序与上表逐拍一致，10 us gap 不少拍、不重复发起。
- QPLL1LOCK 恢复：不晚于事件起点后 25,000 拍（100 us）。
- 首个有效 PHYSTATUS：不晚于事件起点后 32,500 拍（130 us）。
- 结束时 `PHY_RATE=2`、`QPLL1LOCK=1`、`PCIERATEGEN3=1`、
  `PCIEUSERGEN3RDY=1`。
- 不允许 QPLL re-lock 后再次丢锁、额外 raw owner 或 TXEQ/RXEQ 活动。

上述窗口覆盖 5 次同板实测离散性，但不放宽到 K13 曾出现的至少 262.14 us
QPLL 恢复或 PHYSTATUS 不完成现象。
