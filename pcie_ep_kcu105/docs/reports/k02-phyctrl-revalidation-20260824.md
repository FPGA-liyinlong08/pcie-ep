# K02 `phy_ctrl.v` 实板复核（2026-08-24）

## 结论

重新烧录 K02 调试 bit 并在真实 Gen1→Gen3 切速时抓取 ILA 后，确认第一次
Gen3 QPLL1 重锁是成功的；随后第二次 QPLL1LOCK 下降不是自发掉锁，而是
`S_DONE` 撤掉 `gen3_en` 后，`phy_ctrl.v` 主动执行回 Gen1 的 rate contract。
因此原先“QPLL 曾短暂锁定但没有保持稳定”的表述不准确：问题是测试状态机
在 `S_DONE` 主动启动了下一次速率切换。

## 原始波形

捕获文件：
`fpga/kcu105/build_k02_phyctrl/capture/20260824_101516_k02_phyctrl.csv`

ILA 触发条件为 `seq_state_w == 4'd6`（`S_GEN3_WAIT`）。关键转移：

| sample | QPLL1LOCK | QPLL1RESET | PHY_RATE | PCIERATEQPLLRESET[0] | state | GEN3 request | PHYSTATUS |
|---:|---:|---:|---:|---:|---|---:|---:|
| 0 | 1 | 0 | 0 | 0 | S_GEN3_WAIT | 1 | 0 |
| 1 | 1 | 0 | 2 | 0 | S_GEN3_WAIT | 1 | 0 |
| 10 | 0 | 1 | 2 | 1 | S_GEN3_WAIT | 1 | 0 |
| 15 | 0 | 0 | 2 | 0 | S_GEN3_WAIT | 1 | 0 |
| 8191 | 0 | 0 | 2 | 0 | S_GEN3_WAIT | 1 | 0 |

`PCIERATEGEN3`、`PCIEUSERGEN3RDY` 和 `PHYSTATUS` 全程未置位；
`QPLL1REFCLKLOST`、`QPLL1FBCLKLOST` 在捕获窗口内为 1。

## 发现的脚本问题

`run_k02_phy_ila_hw.tcl` 原默认触发值写成 `eq4'h3`，但 RTL 中 `3` 是
`S_GEN1_WAIT`，真正的 `S_GEN3_WAIT` 是 `4'd6`。已修正默认触发值和注释。

因此，2026-08-19 文档中“实板 PASS”的历史记录目前缺少可复核的原始波形，
而本次按正确 Gen3 状态重新捕获的结果是失败。

## 事件记录器复核（2026-08-24 11:47）

为避免依赖 8192 点窗口覆盖整个切速过程，`k02_phy_event_recorder` 将事件
相对于切速开始锁存到 ILA `probe2`（118 bit），深度仍为 8192。该版调试 bit
通过 `K02_PHY_CTRL_WAIT_AFTER_READY_NS=3000000000` 留出 3 s Arm 窗口。

捕获文件：
`fpga/kcu105/build_k02/capture/20260824_114705_k02_phy.csv`

`probe2` 最终记录 `valid=6'b111111`，在 250 MHz `phy_pclk` 下（4 ns/采样）：

| 事件 | 相对 sample | 相对时间 |
|---|---:|---:|
| QPLL1LOCK 起始状态为 0（未在记录器内观察到下降沿） | 0 | 0 us |
| QPLL1LOCK 0→1 | 19323 | 77.292 us |
| PHYSTATUS 0→1 | 26702 | 106.808 us |
| S_GEN3_WAIT 进入 | 0 | 0 us |
| S_DONE 进入 | 46704 | 186.816 us |
| QPLL1LOCK 再次 1→0 | 46723 | 186.892 us |

因此 `S_DONE` 只表示 `phy_bringup_seq` 的保持计数完成；它发生在 QPLL1
再次丢锁前 19 个采样。源码中 `S_DONE` 只保持 `phy_ready_en`，不保持
`gen3_en`；这会命中 `phy_ctrl.v` 的“无 gen*_en → PHY_RATE=3'b000”分支，
随后 GT Wizard/GT primitive 的 rate-change 输出 `PCIERATEQPLLRESET` 通过
`qpll1reset_in` 复位 QPLL1。捕获窗口末端 `PHY_RATE=0`、`gen3_en=0`、
`debug_state=8'h02` 也与该主动回 Gen1 路径一致。

随后将记录起点前移到 `PHY_RATE=Gen3`/进入 `S_GEN3_WAIT`，避免 QPLL reset
已经发生后才开始记录。最终捕获为：
`fpga/kcu105/build_k02/capture/20260824_115455_k02_phy.csv`

| 事件 | 相对 sample | 相对时间 |
|---|---:|---:|
| QPLL1LOCK 1→0 | 10 | 0.040 us |
| QPLL1LOCK 0→1 | 19376 | 77.504 us |
| PHYSTATUS 0→1 | 25073 | 100.292 us |
| S_GEN3_WAIT 进入 | 0 | 0 us |
| S_DONE 进入 | 45075 | 180.300 us |
| QPLL1LOCK 再次 1→0 | 45094 | 180.376 us |

最终 `valid=6'b111111`，因此六类事件均被记录；这版才是用于后续判断的
有效事件记录结果。若目标是验证 Gen3 保持，应修改 `S_DONE` 的输出使其
持续保持 `gen3_en/gen3_request`，或增加显式的“保持 Gen3”终态；不能把
当前 `S_DONE` 当成切速成功标志。

## Gen3 保持 A/B（2026-08-24 14:11）

已将 `phy_bringup_seq.sv` 的 `S_DONE` 改为持续输出
`gen3_en=1`、`gen3_request=1`，重新实现并烧录：

`fpga/kcu105/build_k02/k02_pcie_phy_bringup_ila.bit`

捕获文件：
`fpga/kcu105/build_k02/capture/20260824_141136_k02_phy.csv`

新版本 `probe2` 记录为：

| 事件 | 相对 sample | 相对时间 |
|---|---:|---:|
| QPLL1LOCK 1→0 | 9 | 0.036 us |
| QPLL1LOCK 0→1 | 19379 | 77.516 us |
| PHYSTATUS 0→1 | 27663 | 110.652 us |
| S_DONE 进入 | 47665 | 190.660 us |
| QPLL1LOCK 再次 1→0 | 未发生 | — |

最终采样值为 `PHY_RATE=2`、`gen3_en=1`、`gen3_request=1`、
`PCIERATEGEN3=1`、`PCIEUSERGEN3RDY=1`、`QPLL1LOCK=1`，且
`valid=6'b111011`（仅二次丢锁事件位为 0）。这证明原二次丢锁由
`S_DONE` 撤销 Gen3 请求、触发回 Gen1 速率切换造成，而不是 Gen3 QPLL
本身无法保持锁定。
