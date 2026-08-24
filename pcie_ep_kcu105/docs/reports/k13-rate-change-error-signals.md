# GEN1→GEN3 切速失败：PHYSTATUS 之外的诊断信号

## 结论

PG239 的 PIPE 接口没有定义一个与 `phy_rate` 对应的独立“rate error”输出。`phy_phystatus` 是复位、receiver detect、power change 和 rate change 的完成指示；发起 rate change 后，完成条件就是 PHY 在一个 PCLK 周期内置位 `PHYSTATUS`。如果 PHY 不返回 `PHYSTATUS`，手册要求 MAC 进入 error recovery。`phy_phystatus_rst` 只表示 PHY/GT reset 完成，不是 rate-change 错误码。切速期间 `rxvalid`、`rxdata`、`rxstatus` 也必须忽略，不能把它们当作提前错误指示。

因此，本项目必须用 GT primitive 的状态来定位“不返回 PHYSTATUS”发生在哪一级：时钟/PLL 前置条件、GT rate sequencer/握手，还是 PHY completion/status 路径。

## 本次 bit 的新增/加固诊断

`run_k11b2_impl.tcl` 的 `u_ila_pipe/probe20` 现在取样：

| 字段 | 含义 |
| --- | --- |
| `QPLL1PD`, `QPLL1RESET`, `QPLL1LOCKEN` | QPLL1 控制输入 |
| `TXPLLCLKSEL`, `RXPLLCLKSEL` | GT TX/RX PLL 选择 |
| `TXRATE`, `RXRATE` | GT primitive 实际 TX/RX rate |
| `QPLL1REFCLKLOST`, `QPLL1FBCLKLOST` | 参考时钟、反馈时钟丢失指示 |
| `PCIEUSERRATEDONE` | GT rate-done 输入（当前 IP 若未连接会明确显示为 0） |
| `pcieuserphystatusrst_out` | GT/PHY reset completion |
| `QPLL1REFCLKSEL` | QPLL1 参考时钟选择（`K13_GT_QPLL_PREREQ_DEBUG=1` 时） |

`u_ila_pipe/probe6` 另外包含顶层 `phy_phystatus_rst`，而既有 `dbg_k13_top` 继续记录 PIPE `phy_rate`、`phy_phystatus` 和 LTSSM 状态。这样能把 PIPE reset-completion 与 GT 内部 reset-completion 区分开。

## 解释顺序

1. `PHY_RATE` 从 0 变为 2 后，先看 `TXRATE/RXRATE` 是否实际变为 2，以及 `PCIERATEIDLE` 是否退出 idle。
2. 只有在 `QPLL1LOCKDETCLK` 已接入稳定、独立的检测时钟时，才能使用
   `QPLL1REFCLKLOST/QPLL1FBCLKLOST` 判断参考/反馈时钟；若检测时钟未连接，
   这两个输出没有定义，不能作为切速错误结论。
3. 若两个 loss 位均为 0，但 `QPLL1LOCK` 由 1 变 0 且在 `QPLL1RESET` 释放后不恢复，这是 QPLL 重锁/反馈路径失败；它足以解释后续没有 `PHYSTATUS`。
4. 若 `QPLL1LOCK=1`、rate 已切到 2，但 `PCIERATEGEN3` 或 `PCIEUSERGEN3RDY` 仍为 0，问题在 GT rate sequencer 或 user-rate handshake。
5. 若 GT lock、rate、`PCIEUSERGEN3RDY` 均正常而 PIPE `PHYSTATUS=0`，再检查 PHY completion/status 传播和 reset release；此时 `phy_phystatus_rst`/`pcieuserphystatusrst_out` 应已完成而不能保持异常。
6. `RXVALID/RXSTATUS` 在切速窗口内按 PG239 明确忽略；不要用它们替代 `PHYSTATUS`。

## 现有证据与下一步

历史上板抓取已经观察到 `QPLL1LOCK: 1→0` 后不恢复、`PCIERATEGEN3=0`、`PCIEUSERGEN3RDY=0`、`PHYSTATUS=0`。这比单看 `PHYSTATUS` 更接近根因，但此前没有同时捕获 `REFCLKLOST/FBCLKLOST`，无法判断是时钟前置条件还是 QPLL 重锁本身。新 bit 的目的就是补齐这个区分。

本次构建参数为 `K13_RXEQ_TWO_PASS=0`、`K13_GT_QPLL_PREREQ_DEBUG=1`，实现通过（`WNS=-0.302 ns`，诊断 bit 允许负裕量）。

## 本轮实板证据（2026-08-24）

镜像和探针：

```text
bit = fpga/kcu105/build_k13_gen3_ila_gt_primitive_qpll_prereq/impl/k13_gen3_endpoint_ila.bit
bit_sha256 = fb2da9b6184dfba40199a6943ac12d03fc57356ab68bc0000819fc5db0d5c463
capture = fpga/kcu105/build_k13_gen3_ila_gt_primitive_qpll_prereq/capture/20260824_081257_u_ila_pipe.csv
Root Port = 00:01.0, Endpoint = 01:00.0
```

远程主机重启后 Endpoint 能以 Gen1 枚举；对 Root Port 写入 Target Link Speed=8GT/s 并 retrain 后，主机仍报告 `2.5 GT/s`。ILA 的 `dbg_k13_top` 触发样本为 512，实际 `PHY_RATE/RXRATE` 在 sample 3307 变为 2。GT primitive 关键变化如下：

| sample | 观测 |
| ---: | --- |
| 0–3306 | `TXRATE=0`、`RXRATE=0`；`QPLL1LOCK=1`；`PCIERATEGEN3=0`；`PCIEUSERGEN3RDY=0`；`PCIEUSERRATESTART=0`；`PCIEUSERRATEDONE=0` |
| 3307 | PIPE `PHY_RATE=2`，GT `TXRATE=2/RXRATE=2`；`PCIERATEIDLE` 仍为 1 |
| 3310 | `RXVALID` 从 1 变 0（切速窗口内按 PG239 忽略） |
| 3316 | `PCIERATEIDLE` 变 0，但 `PCIERATEGEN3`/`PCIEUSERGEN3RDY` 仍为 0 |
| 3317 | `QPLL1RESET: 0→1`，`QPLL1LOCK: 1→0` |
| 3322 | `QPLL1RESET: 1→0`，`QPLL1LOCK` 没有恢复；直到 sample 4095 仍为 0 |

整个窗口 `QPLL1PD=0`、`QPLL1LOCKEN=1`、`TXPLLCLKSEL=RXPLLCLKSEL=2`、`QPLL1REFCLKSEL=001`，而两个 `LOST` 位保持高。进一步检查生成的
`pcie_phy_x1_gen3_gt.v` 可见 `qpll1lockdetclk_in` 被固定为 `1'H0`；依据
UG576，这使 `QPLL1REFCLKLOST/QPLL1FBCLKLOST` 失去诊断意义，不能据此
断定板上 REFCLK/FBCLK 真丢失。`phy_phystatus_rst=0` 和 GT
`pcieuserphystatusrst_out=0` 表明 reset completion 已结束，故不是“仍在
PHY reset 中”。有效硬件证据仍是 `QPLL1LOCK` 在 QPLL1RESET 释放后不恢复。

本轮比“只看到 PHYSTATUS=0”更具体：**rate 请求和 GT TX/RX rate 已经到 2，但 QPLL1 在随后 reset 脉冲后失锁不恢复，且 GEN3RDY/PCIERATEGEN3/USERRATESTART/DONE 都没有完成。** `PCIEUSERRATEDONE=0` 是可疑输入，但历史上把它固定为 1 的 A/B 仍然得到相同结果，因此目前不能把 DONE 单点作为修复。

## 与 VCS 的差异

当前 VCS 联合仿真（`sim/vcs/build/k11b2_simulate.log`）在 rate=2 后能看到 `PHYSTATUS=1`、`active_rate=2`、EQ active 并最终 `eq_done=1`；失败发生在 Root Port 的 TS/serial/block-lock 边界，最终 `negotiated=0`。实板则在 GT QPLL/GEN3 ready 阶段已经停住，连 PHY completion 都没有。因此 VCS 的 PHY/PIPE behavioral model 没有建模真实 GT QPLL lock detector、`REFCLKLOST/FBCLKLOST`、QPLL reset/relock 和 user-rate handshake，不能用来否定实板的 QPLL 根因。

下一步应继续保留 VCS 做 PIPE contract 回归，同时以实板 GT primitive 波形为主线：先解决 `QPLL1LOCK` 在 `QPLL1RESET` 释放后的恢复及 `PCIERATEGEN3/PCIEUSERGEN3RDY` 握手，再进入 RXEQ/TS2。当前不应再优先修改 RXEQ，因为实板在 RXEQ 之前已经失败。

## 低 CDR-hold A/B 复测（2026-08-24 15:20）

为排除 CDR hold 和 ILA 触发位置的影响，使用
`K13_CDR_HOLD_FORCE_LOW=1`，并以 `PCIERATEQPLLRESET` 直接触发 ILA：

```text
capture = fpga/kcu105/build_k13_gen3_ila_cdr_hold_low_gt_primitive_qpll_prereq/capture/20260824_152033_u_ila_pipe.csv
```

`dbg_k13_top[0]=as_cdr_hold_req` 全程为 0；`PHY_RATE/RXRATE` 在 sample 503
变为 2；sample 512～517 发生 QPLL reset，`QPLL1LOCK` 由 1 变 0，直到
sample 4095（reset 释放后约 14.3 us）仍为 0，且 `PHYSTATUS`、
`PCIERATEGEN3`、`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART/DONE` 均未完成。
这次 A/B 证明“Recovery.Speed 期间 CDR hold=1”不是导致 QPLL 在前 14.3 us
内恢复失败的唯一因素；但 K02 已知约 77.5 us 才重锁，仍需事件记录器确认
K13 是否更晚恢复，不能仅凭 4096 点窗口断言永久失锁。

同时检查生成 IP 发现 `qpll1lockdetclk_in` 固定为 `1'H0`。根据 UG576，
`QPLL1LOCKDETCLK` 是 `*_REFCLKLOST/*_FBCLKLOST` 诊断输出所需的稳定检测
时钟，且不影响 QPLL lock/reset；因此现有两个 `LOST=1` 只能视为未定义的
诊断值，下一版 bit 必须先接入独立稳定的 100 MHz `phy_refclk` 后再解释。

## 直接以动态 QPLL reset 触发的实板复测（2026-08-24）

为排除 4096 深度 ILA 的触发位置偏后问题，硬件脚本新增
`program-arm-k13-qpll-reset` / `capture-k13-qpll-reset-wait` 动作，改用
`PCIERATEQPLLRESET` 作为切速专用触发源；实际 `QPLL1RESET` 保留在 probe20
中作为观测信号。复测波形：

```text
fpga/kcu105/build_k13_gen3_ila_gt_primitive_qpll_prereq/capture/20260824_085419_u_ila_pipe.csv
```

结果（250 MHz PIPE ILA，每 sample 4 ns）：

| sample | 观测 |
|---:|---|
| 502 | GT `TXRATE/RXRATE=2`，进入 Gen3 rate-change |
| 511 | `PCIERATEIDLE` 退出 idle |
| 512 | `PCIERATEQPLLRESET=1`，实际 `QPLL1RESET=1`，`QPLL1LOCK: 1→0` |
| 517 | `PCIERATEQPLLRESET=0`，实际 `QPLL1RESET=0` |
| 4095 | `QPLL1LOCK` 仍为 0，未出现 `PHYSTATUS` |

本次 reset 事件被固定在 sample 512，reset 释放后仍有约 14.3 us 的观测窗口，
超过 VCS PHY demo 约 8 us 的 relock 时间；因此当前 K13 实板不是单纯 ILA
窗口不足，而是 QPLL reset 释放后确实没有恢复 lock。`PCIERATEGEN3`、
`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART` 也均未完成。
