# PG239 RX/TX Equalization 取证要点

参考手册：[pg239-pcie-phy-en-us-1.0.pdf](../reference/pg239-pcie-phy-en-us-1.0.pdf)。以下结论来自 PG239 v1.0 的 Table 12、Table 13 和 Equalization Sequences（PDF 页 18–19、24–27）。

## 已确认的 PHY 协议

- `phy_rxeq_ctrl=2'b00`：Idle。
- `phy_rxeq_ctrl=2'b01`：保留值，不是 RX adaptation 命令。
- `phy_rxeq_ctrl=2'b10`：RX EQ。
- `phy_rxeq_ctrl=2'b11`：RX EQ bypass。
- `phy_rxeq_done` 和 `phy_rxeq_adapt_done` 都为高才算 RX EQ 成功。
- `phy_rxeq_done=1` 且 `phy_rxeq_adapt_done=0` 表示新 proposal，必须重新发起 RX EQ；检测到 done 后要把 CTRL 清回 `00`。
- `phy_rxeq_preset_sel` 与 `phy_rxeq_new_txcoeff` 只有在 `RXEQ_DONE` 为高时有效。`preset_sel=1` 时 `new_txcoeff` 只有低 4 位有效；选择 coefficient 时才使用完整 18 位。
- TX coefficient 的 18 位排列为 `[17:12]` pre-cursor、`[11:6]` main-cursor、`[5:0]` post-cursor。

## 对当前自研 EP 的直接影响

1. `RXEQ_TWO_PASS` 的方向是正确的，但清零并等待旧 DONE 释放是必要条件；不能把 level-held/stale DONE 当成第二次结果。
2. 当前 `pcie_equalization_ctrl.sv` 的状态推进已经能在 VCS 中完成 `0→1→2→3→4`，但这只能证明控制器状态机和 PHY 模型反馈闭环，不能证明端口角色下的 EQ phase 分工正确。
3. Endpoint 是 PCIe upstream port。PG239 的文字说明要求按端口角色区分 RX Adapt/TX Adapt 所属 phase：upstream port 的 RX Adapt 在 Phase 2、TX Adapt 在 Phase 3；downstream port 相反。当前控制器把 RX 命令放在 P1/P3、TX 命令放在 P0/P2，需要按角色重新核对，而不是继续放宽 TS1/TS2 门限。
4. `phy_rxeq_preset_sel/new_txcoeff` 不能直接作为常态 TS 字段拼接；必须在 `RXEQ_DONE` 脉冲采样，并依据 preset 或 coefficient 两种格式编码到 Gen3 TS EQ 字段。当前 `pcie_gen3_os_tx.sv` 中的固定 tuple 仍应视为未闭环实现。

## 下一轮验证顺序

1. 在真实 VCS 日志中按 post-rate Recovery epoch 分开统计 TS1/TS2，确认 EP 停在 `Recovery.RcvrCfg` 时收到的 TS2 数量及 EQ 字段。
2. 按 Endpoint/upstream 角色重画 Phase 0–3 时序，先修正 TX/RX Adapt phase 归属。
3. 对 RXEQ done-only 和 done+adapt_done 分别采样 `preset_sel/new_txcoeff`，再实现规范的 TS EQ tuple 编码。
4. 保持 8 个完整 TS1/TS2 的门限不变；只有 TS2→Recovery.Idle 收敛后，才继续验证 Gen3 L0/TLP。

## 最新真实 VCS 取证（2026-08-21）

在 `K13_RXEQ_TWO_PASS=1` 下，第二次 Recovery 的 RXEQ 已完成：
`done=1/adapt_done=1`，随后 `eq_phase=4/eq_done=1`。这一步不是当前失败点。

EQ 完成后 Endpoint 的 Gen3 TX 原始 PIPE 连续有效，且 LTSSM 为
`Recovery.RcvrCfg`、发送模式为 TS2（`mode=2`、`gen3_mode=1`、`start_block=1` 周期
正常出现）。对应日志见 `sim/vcs/build/k11b2_simulate.log` 的
`K13_EP_RECOVERY_TX_RAW`。

但 Root Port 仍停在 `cfg_ltssm_state=0xc`，Endpoint 未收到有效的 TS2 接收回报，最终
`ts_accept=0`。本轮在 Root Port 的 `pipe_rx0_data_valid` 取证窗口没有得到有效样本，
因此当前第一分叉已从“EP 是否发 TS2”收敛到“EP→RP 的 Gen3 RX/GT/PIPE 串行接收链路或
其 rate/reset 接线”。这也解释了为什么继续改 RXEQ done-only 或放宽 8 个 TS 门限不能
解决本次停滞。

补充证据是最终失败快照中的 Root Port `cfg_current_speed=1`（仍是 Gen1），而此前
Root Port 曾在内部 PIPE 观测到 `pipe_tx0_rate=2` 并进入 `0x29` 等化相关状态；也就是
Root Port 发端曾切到 Gen3，但没有完成由 Endpoint 返回 TS2 驱动的最终速率提交。

本轮只增加了 VCS 观测，不改变功能 RTL；下一步应对照官方 demo 的 GT wrapper、Gen3
rate/elec-idle、RX reset release 和 PIPE RX valid 接线，再决定是否继续实现规范的 TS
EQ tuple。当前仍不能标记 Gen3 L0 PASS。

### 新增 GT 内部取证

新增的 `K13_EP_RX_CONTRACT` 采样显示：在 Endpoint 已把公共 PIPE
`phy_rate` 置为 `2'b10` 时，GT 仍报告 `gt_pcierategen3=0`、
`gt_pcieusergen3rdy=0`；同时 `gt_rxcdrlock=1`、`gt_rxresetdone=1`，而
`phy_rxdata_valid=0`、`phy_rxstatus=000`。因此当前更精确的第一分叉是
“动态切速命令到达 MAC/PIPE 边界，但 GT 没有进入 Gen3 PCS ready 状态”，而不是
“Gen3 TS2 内容被 Root Port 解析后拒绝”。

另外，已按 GT 的 `PCIEUSERRATESTART` 做过一次临时自应答实验，
`gt_pcierategen3/gt_pcieusergen3rdy` 和最终 VCS 结果均未改变；该实验已撤回，
不能把它当作最终修复。`TXDATAK` 在 Gen3 强制为零是必要的 PIPE 修正，Verilator
回归仍为 6/6、7/7 PASS，但真实 VCS 的失败点没有因此消失。

这里需要区分“已解决的老问题”和“当前完整链路失败”。项目中的
`rtl/phy/phy_ctrl.v` 已经包含 Xilinx 原始的 rate-change 状态机；K02 使用
`phy_bringup_seq.sv + phy_ctrl.v`，该路径已经解决过 QPLL1 动态切速/重锁问题。
本轮又用官方 `pcie_phy_0` 做了 K13 production controller 的窄场景复测，结果为
`K13_PRODUCTION_PHY_QPLL_LOCK_VCS_PASS` 和
`K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS`：即使 K13 不复用 `phy_ctrl.v`，
`pcie_phy_rate_contract.sv` 在官方 PHY 边界也能完成 QPLL1 unlock/relock 和
`PhyStatus`。因此完整 K11B2 中看到的 QPLL1/Gen3 RX 失败，不能再简单归因于
`phy_ctrl.v` 没有接入；应继续对比“官方 `pcie_phy_0` 窄场景”与“项目
`pcie_phy_x1_gen3 + LTSSM/RP` 完整场景”的顶层接线/时序。

## K02 与 K13 的路径对比（2026-08-21）

| 对比项 | K02 standalone | K13 自研 EP | 判断 |
|---|---|---|---|
| `PHY_RATE` | 上电后固定为 `2'b10` | Recovery.Speed 中由 `0→2` 动态改变 | K13 多了 GT rate-change handshake |
| QPLL1 | `QPLL1LOCK=1`、`QPLL1RESET=0`、`QPLL1PD=0` 全窗口稳定 | Gen3 切换时 lock `1→0`，现有窗口内未恢复；出现短暂 `QPLL1RESET` 脉冲 | 动态切速的 QPLL1 恢复是第一优先级 |
| GT Gen3 状态 | `PCIERATEGEN3=1`、`PCIEUSERGEN3RDY=1` | `phy_rate=2` 但 `PCIERATEGEN3=0`、`PCIEUSERGEN3RDY=0` | 公共 PIPE 命令已改变，GT PCS 尚未 ready |
| RX | `RXRESETDONE=1`，无协议数据属预期 | `RXRESETDONE=1` 但 `RXVALID/RXDATA_VALID=0`、`RXSTATUS=000` | 不是 RXEQ proposal 解析失败 |
| 上层完成条件 | 不含 LTSSM、TS1/TS2 或 EQ | K13 窄场景可完成 `PhyStatus` 和 QPLL1 relock；完整 K11B2 仍在 TS/RX 链路失败 | 窄场景 PASS 不能外推为完整链路 PASS |

依据：K02 固定 Gen3 的 ILA 记录见
`docs/reports/k02-standalone-pcie-phy.md` 第 7.1 节；K13 动态切速的
`PCIERATEGEN3/QPLL1/PhyStatus` 记录见
`docs/reports/k13-validation-baseline-20260813.md` 的 “GT rate-change 追加证据”。
K02 的关键是 `phy_ctrl.v` 的 `PHY_BUP_PHY_RDY0/1/2/3` 序列；K13 窄场景则证明
`pcie_phy_rate_contract.sv` 的等价边界在官方 PHY 上成立。当前差异已经缩小到：
官方窄场景没有完整 LTSSM/RP 串行接收，而 K11B2 使用项目
`pcie_phy_x1_gen3`、自研 LTSSM、Root Port 以及 `as_cdr_hold_req`/TXEI/RX valid
联合接线。

### 窄场景复测结果

执行：

```bash
VCS_LICENSE_TIMEOUT=300 ./sim/vcs/k13_phy_rate_change/run_k13_phy_rate_change.sh
```

结果：

```text
K13_PRODUCTION_PHY_QPLL_LOCK_VCS_PASS initial_lock=1 final_lock=1 unlock_seen=1 relock_seen=1
K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS rate=gen1_to_gen3 pre_rate_txeq=1 phystatus=1
```

完整产物位于 `/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/k13_phy_rate_change/`。
这项结果证明 K13 rate contract 的 PHY 边界正常，但不覆盖完整 K11B2 的 TS1/TS2
串行 RX、GT 接收状态和 fallback。

### 当前代码层面的边界

`pcie_phy_rate_contract.sv` 的 `RC_WAIT_PHYSTATUS` 在看到 `phy_phystatus` 上升沿
后直接进入 `RC_COMMIT_RDY2`，把目标速率提交给协议层；该模块没有接收
`PCIERATEGEN3`、`PCIEUSERGEN3RDY` 或 `QPLL1LOCK`。因此现有 RTL 可以报告“PIPE
速率切换完成”，但不能单独证明 GT 已进入 Gen3 PCS ready。VCS 的最新失败快照则
同时显示 EP 公共 `phy_rate=2`、GT `rategen3=0/gen3rdy=0`，所以应先补齐这组取证，
再决定是否需要改变完成门控。

### 下一步的最小修改顺序

1. 在 K13 wrapper/top 仅增加只读诊断端口或 ILA：`PCIERATEIDLE`、
   `PCIERATEGEN3`、`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART`、`QPLL1LOCK`、
   `QPLL1RESET`/`QPLL1PD`，不改生成 PHY 的 vendor source。
2. 对齐 K02 与 K13 的同一时间轴：`phy_rate` 改变点 → `RATEIDLE` 下降/恢复 →
   QPLL1 reset/lock → `PCIERATEGEN3/USERGEN3RDY` → `PhyStatus` → RX valid。
3. 只有当 GT ready、QPLL1 lock 和 PIPE RX valid 都恢复后，才继续定位
   TS1/TS2 接收或 EQ tuple；在此之前不再放宽 TS 门限，也不再改 RXEQ done-only。

## 完整 K11B2 最新分叉（2026-08-21，后续复测）

上面的“GT 尚未 ready”结论只对应第一次 `K13_EP_RX_CONTRACT` 取样窗口，不能作为
最终根因。启用 RX parser 提前窗口后，完整 VCS 已观察到：

- `phy_rate=2` 后，EP PIPE RX 最终出现 `rxvalid=1/rx_data_valid=1`，并能解出合法
  Gen3 TS1（`link=9f/lane=0/rate=0e/eq_ctrl=01`）；因此当前不是 QPLL1 未重锁，也
  不是 EP 完全收不到 Gen3 数据。
- K13 RXEQ、EQ phase 0→4 和 `eq_done=1` 均完成；合法 post-rate TS 已跨
  `RATE_WAIT(3)`→`Recovery.Idle(4)` 保留。
- Root Port 仍在 `cfg_ltssm_state=0xc`/等化相关状态，EP 停在
  `Recovery.RcvrCfg(12)`；RP 侧没有完成最终 Gen3 Recovery 收敛，完整 VCS 仍输出
  `K13_VCS_GEN3_RETRAIN_FAIL`。

本轮功能修正包括：

1. `pcie_ltssm_mac_gen1.sv` 仅在真正 `Recovery.Speed` 目标为 Gen3 时提前启用 Gen3
   RX parser，避免错过 EIEOS；
2. `pcie_k13_production_ctrl.sv` 在 `RATE_WAIT` 也锁存字段合法的 post-rate TS；
3. Gen3 EQ phase-0 收到带 EQ 请求的 TS1 时，锁存整个下一个 Ordered Set 的 TS1
   响应模式，避免单周期 `os_ts1_valid` 造成 TS1/TS2 拼接。

Verilator K13 integration 回归仍为 `TESTS=6 PASS=6 FAIL=0`。当前下一步应直接对照
官方 demo 的 Recovery.Equalization phase-0/phase-1 TS 角色与 Root Port 的
`cfg_ltssm_state=0x28/0x29` 转移，确认何时从 EP 的 EQ TS1 响应切回 TS2；不要再把
QPLL1 或 RXEQ done-only 当作主因。

## RP 接收端最终分叉（2026-08-21，完整 VCS 正常流程）

重新运行：

```bash
K13_ENABLE=1 K13_VCS_RETRAIN=1 K13_RXEQ_BOOTSTRAP=0 \
K13_RXEQ_TWO_PASS=1 K11B2_MODE=1 ./sim/vcs/run_k11b2_serial.sh
```

结果仍为 `K13_VCS_GEN3_RETRAIN_FAIL`，但新增的 RP 内部接收事件把卡点定得更具体：

```text
200707604 ps  EP phy_rate=2, PhyStatus=1
              RP rxvalid=0 rxdata_valid=0 rxelecidle=1 rxcdrlock=1 rxresetdone=1
200793534 ps  EP txdata_valid=1 txelecidle=0
              RP rxvalid=0 rxdata_valid=0 rxelecidle=0 rxcdrlock=1 rxresetdone=1
```

这里 `rxresetdone=1` 的含义是 RX reset 已完成，不能读成“RX 仍在 reset”；
同时 `rxelecidle` 已从 1 降为 0、`rxcdrlock=1`，说明 EP 开始发送 Gen3 TS 后，
RP 已看到活动串行信号且 CDR 锁定，但 GT/PCS 没有给出 `RXVALID` 或
`RXDATA_VALID`。因此当前不是 QPLL1 LOCK、RX reset release 或 RXEQ done-only
问题，而是 EP→RP 的 Gen3 PCS/PIPE 接收格式或其 RX valid 门控不匹配。

EP 侧同一窗口已经完成 `RXEQ done+adapt_done`、EQ phase 0→4，并持续输出有
`start_block=1` 边界的 Gen3 TS1/TS2；RP 仍停在 `cfg_ltssm_state=0xc`，最终
`rp_speed=1`。下一步应做唯一的最小 A/B：保持速率和 EQ 控制不变，只对照官方
demo 逐字段核验 EP Gen3 `TXSYNC_HEADER/TXDATA/TXDATAK/TXDATA_VALID` 到
RP GT 的输入与 `RXCTRL0[5:2]` 解码，确认 RP PCS 为何不产生 `RXDATA_VALID`；
在此之前不再修改 QPLL、RXEQ 门限或 fallback 逻辑。

### RP GT 原始 RX 与 TXDATAK A/B（同一轮 VCS）

在 Root Port `rp_gt_channel` 原始端口增加取证后，EP 开始发送 Gen3 TS 的同一事件为：

```text
rp_gt_data=00000000 rp_gt_ctrl=0000 rp_gt_valid=0
rp_gt_start=0 rp_gt_header=00
```

这说明当前不是 RP 上层 PIPE 适配把有效字丢掉，而是 GT 原始 RX 端就没有形成
有效 Gen3 解码字。随后做了可回退的 A/B：临时把 EP Gen3 `TXDATAK` 从规范的
`2'b00` 恢复为旧的 `tx_scrambled_datak`，在同一时间点的 RP 原始 RX 仍为
`valid=0/start=0/header=00`，最终状态也仍为 `K13_VCS_GEN3_RETRAIN_FAIL`。

因此 `TXDATAK` 不是当前唯一分叉，A/B 已恢复为规范实现。下一项应继续核对
EP→RP 串行链路的 Gen3 `TXSYNC_HEADER`、速率命令和 GT 端口映射，尤其是 RP
`GT_RATE/PCIERATEGEN3` 与 EP 发送窗口是否真正同时生效。

### 速率 ready 与 RXSTATUS 复测

同一 RP RX 事件进一步得到：

```text
ep_rate=10 ep_txvalid=1 ep_txidle=0 ep_txdatak=00
rp_gt_rate=10 rp_rategen3=1 rp_gen3rdy=1
rp_rxstatus=000 rp_rxvalid=0 rp_rxdata_valid=0 rp_rxidle=0
```

EP 发端首个序列也已抓到完整的 4 个 EIEOS block，随后从 `start_block=1` 的 TS1
开始；没有发现 EIEOS 缺字或 TXDATAK 错误。由此当前分叉进一步收敛为：RP GT
已经处于 Gen3 ready、串行输入已非电气空闲，但 128b/130b block lock 没有建立，
且没有产生 `RXSTATUS=100` 解码错误。下一步应核对 GT channel 的 block-lock/接收
时钟与官方 demo 配置，而不是继续修改 LTSSM/EQ 控制器。
