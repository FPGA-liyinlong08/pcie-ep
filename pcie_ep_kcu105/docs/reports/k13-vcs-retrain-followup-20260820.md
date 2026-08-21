# K13 VCS Retrain Follow-up（2026-08-20）

## 本轮提交

- `4253fae`：增加 `requested_rate` 语义输出。LTSSM 在 `active_rate` 尚未收到
  `PhyStatus` 提交前，仍能广告本次 Recovery 目标；fallback 状态强制广告 Gen1。
- `2b8819d`：VCS runner 增加 `K13_RXEQ_BOOTSTRAP=0/1` 入口，用于分离纯切速门和
  RXEQ bootstrap 门。
- `65a0bbb`：RXEQ/peer 失败发生在原 Gen3 `Recovery.Speed` 已结束之后时，LTSSM
  重新进入一次 `Recovery.Speed`，完成显式 Gen1 fallback 的 PhyStatus 握手。
- `f2ebd9d`：partner retrain 只接受 `Rate ID[7]=1` 的定向 TS1；fallback 后的
  `0x0e` 能力广告不再被误当成新的 Gen3 请求。Rate ID[3:0] 仍只用于解码能力。
- 工作区诊断改动：VCS 只在 Endpoint 与 Root Port 都稳定 Gen1 L0（含 DLL Active、
  `user_lnk_up`）后才允许第二次 Retrain；增加三边界 Ordered-Set 比较器、统一事件快照
  以及 `K13_RETRAIN_SOURCE=dual|rp|ep` A/B 入口。等待窗口仍由
  `K13_FALLBACK_WAIT` 配置（默认 20,000 个 `phy_pclk`）。

## 已通过

- K11B2 顶层 lint、K13 controller lint、K13 integration lint。
- K13 controller Verilator：4/4 PASS。
- K13 production LTSSM + behavioral partner Verilator：6/6 PASS。
- 单元波形确认 `requested_rate=Gen3` 可早于 `active_rate=Gen3`，命令/提交顺序不变。
- 真实 Xilinx Root-Port VCS 的初始 Gen1 枚举、BAR、InitFC/DLL 仍 PASS；首次
  Gen3 速率命令、Gen3 `PhyStatus` 和 RXEQ failure→Gen1 fallback 事件可观察。

## 独立 Partner Gate C 进展

在 `sim/verilator/k13_integration` 增加了独立的脚本化 Partner 状态流程：第一次
Gen3 只返回 RXEQ `done`（不返回 `AdaptDone`），等待 DUT 完成 Gen1 fallback 并由
Partner 发送 Gen1 TS1/TS2、Idle；确认回到 Gen1 L0 后再次发起 Gen3 Retrain，第二次
提供完整 RXEQ completion。原有三项 K13 integration 回归继续通过：

```text
production_ltssm_gen1_to_gen3_eq_closed_loop                 PASS
partner_initiated_speed_change_closes_recovery_and_eq        PASS
production_gen3_failure_fallback_then_retry                  PASS
```

本轮又增加三项 fallback Partner Gate C 边界用例，当前 K13 integration 全量为
6/6 PASS：

```text
fallback_fixed_latency_nine_ts1_returns_to_gen1_l0           PASS
fallback_vcs_splice_keeps_eight_ts1_threshold                PASS
fallback_eight_complete_ts1_enters_rcvrcfg                   PASS
```

第一项使用固定延迟、无丢失的 `9 TS1 -> 8 TS2 -> Idle`，要求恢复 Gen1 L0；第二项
逐字复现 VCS 输入端看到的 `5 个完整 TS1 + 第 6 个 TS1/TS2 拼接`，要求保持在
`Recovery.RcvrLock`；第三项在至少 8 个完整 TS1 后切换 TS2，要求进入
`Recovery.RcvrCfg`。这些结果证明生产 LTSSM 的 8-TS1 确认规则正确，未修改门限，
也未把 RXEQ workaround 作为 PASS。

第三项现在进一步覆盖第二次 Gen3 `Recovery.Idle -> L0` 的最小语义边界：Partner 在
Recovery.Idle 后停止 Ordered-Set 发射，向 Gen3 RX 提供合法的零 Data Stream logical-idle
block；`pcie_gen3_os_rx` 产生 `idle_valid`，LTSSM 连续收齐 8 个 idle 后进入 L0。测试同时
断言 `phy_rate=Gen3`、`active_rate=Gen3`、`negotiated_speed=Gen3` 和 `eq_done=1`。
这不是完整 Gen3 SDS、128b/130b payload、TLP/DLLP 或 DLL Active 验收；这些仍保留给后续
Gen3 协议冻结门。

## 真实 Root-Port VCS 当前分叉

命令：

```text
K13_ENABLE=1 K13_VCS_RETRAIN=1 K11B2_MODE=1 ./sim/vcs/run_k11b_serial.sh
```

首次 Gen3 尝试在 RXEQ done-only 模型下回退到 Gen1。修正后 Endpoint 在
`275419629 ps`（约 `275.420 us`）产生 Gen1 `PhyStatus`，并恢复到 Gen1 命令；Endpoint 随后连续发送
合法 Gen1 TS1（原始 PIPE 采样为 `9fbc, ff00, 0002, 4a4a...`）。但加密 Xilinx
Root-Port 在 `cfg_ltssm_state=c`、Gen1 rate 下先保持 `TX Electrical Idle=1`、
`data=0`，约 `303287505 ps`（约 `303.288 us`）才重新进入 Recovery 并发送 TS。新增两侧原始 PIPE
采样后确认，不能把这个过程简化成“Root-Port 只发出 5 个 TS1”：Root-Port 在
`state=b` 先出现模式切换残留 `0/1cbc/1c1c`，随后从 `9fbc,ff00,0e,4a4a...`
开始连续输出至少 9 个完整 Gen1 TS1，之后才在 `state=d` 切到 `45 45`（TS2）。
Endpoint RX 端也持续看到合法的 `datak=01,data=00009fbc` 起始字及随后
`ff00,0000000e,4a4a...`，没有 RX idle、无效或 QPLL 失锁迹象；但 Endpoint 的
Ordered-Set 解析只产生 5 个 TS1 完成事件，接着看到 TS2，并按标准的 8-TS1 门限停在
`Recovery.RcvrLock`。双方从未同时到达 Gen1 L0，因此新的 Gen3 Retrain 没有被测试平台
发起。当前待定位点是 fallback 后 Root/Endpoint PIPE 训练窗口的相位/状态闭环（包括
模式切换残留和加密 Root-Port 的 TS1→TS2 时序），不是放宽 TS1 门限，也不是 EQ/QPLL
判定。

同一次 100,000-cycle 等待回归的关键证据：

```text
Root TX:      303307529:1cbc, 303315529:1c1c,
              303323529..303827504: 9fbc,ff00,0000000e,4a4a... (TS1)
              303923504: 4545 (开始 TS2)
Endpoint RX:  303739504 起 datak=01,data=00009fbc；随后连续
              ff00,0000000e,4a4a...；解析事件为 TS1×5、随后 TS2
```

将等待窗口从 20,000 扩展到 100,000 个 `phy_pclk` 仍未观察到双方 Gen1 L0；Root-Port
随后多次退回 Detect/Polling。这个结果排除了“第二次 Retrain 发得太早”这一测试平台
问题，也没有证据表明是 EQ 或 QPLL 锁定导致该分叉。

这不是 QPLL、KCU105 线缆、J74、REFCLK 或 PERST# 结论；当前失败点是 VCS Root-Port
fallback 后的 Ordered-Set/状态闭环。实板验证必须等该 Gate C 分叉解决后再继续。

## 2026-08-21 VCS 复跑补充

使用相同的真实 Root-Port VCS 路径并将 `K13_FALLBACK_WAIT` 扩大到 `100000` 个
`phy_pclk` 后，分叉稳定复现，最终结果为：

```text
K13_VCS_GEN3_RETRAIN_FAIL wait=100000
ep_state=11 speed_state=0 rate=0 negotiated=0 eq_active=0 eq_phase=7
eq_done=0 fallback=1 speed_timeout=0 ts_accept=0 ts_reject=0
rp_state=2 rp_speed=1 rp_link=0 seen_rp_recovery=1 seen_states=1110
seen_rate=1 seen_phystatus=1 seen_eq=00000
```

本次使用 `-t ps`，以下时间均为仿真时间戳（ps）：Root-Port 首个完整 fallback
TS1 从约 `303323529 ps` 开始；Endpoint 受 PHY/PIPE 延迟影响，首个完整 TS1 约在
`303803504 ps` 才被解析。Root-Port 在 `303875505 ps` 从 `state=b` 进入 `state=d`；
首个 TS2 Ordered Set 的 COM 从 `303899504 ps` 开始，TS2 identifier `45 45` 出现在
`303923504 ps`。Endpoint 第 6 个候选 Ordered Set 的 COM 在 `304059529 ps` 到达，
但其 identifier 在 `304083529 ps` 已被后续 TS2 替换。Endpoint 因而只完成 TS1
计数 5，随后持续看到 TS2，并停留在 `Recovery.RcvrLock`。

该复跑排除了“等待时间不足”这一因素，也进一步表明当前分叉是加密 Root-Port/PHY
PIPE 延迟与 Recovery TS 发射窗口的相位不匹配；本次没有观察到 QPLL、CDR 或 EQ
失败证据。生产 LTSSM 的 8-TS1 门槛不应为适配该模型而放宽。

## 对官方 demo VCS 的借鉴与当前复现

已复核 `/home/wx/Documents/PCIe/pcie3_ultrascale_0_ex` 的完整 `board + glbl` VCS。
该 demo 的 Gen1→Gen3 PASS 使用的是 Xilinx Endpoint + Xilinx Root Port + Xilinx PHY/GT
模型，不能直接证明本工程自定义 Endpoint 已完成切速；但以下三项可直接借鉴：

1. **双端标量时序证据**：demo 同时记录 EP/RP 的 LTSSM、当前速率、协商宽度、
   `phy_link_status`、`user_lnk_up` 和 PIPE `rate/elec_idle/phy_status`，并以时间戳对齐
   `Recovery.Speed → EQ Phase 0..3 → Recovery.Idle → L0`。当前工程已在
   `sim/vcs/k11b_serial_board.sv` 加入同样的 board-scope trace aliases；它还额外保留
   `pipe_rate_cmd/active_rate/negotiated_speed`，可直接检查 Rate Contract 的提交顺序。
2. **可选波形而非默认大 dump**：新增 `K13_WAVEFORM=1` 后，VCS 生成受控的
   `sim/vcs/build/k13_vcs_training.vcd`；`K13_TRACE=1` 输出可与 demo 文本日志逐事件比较的
   `K13_TRACE`。默认值仍为关闭，不影响普通回归。
3. **Root-Port directed speed-change 参考**：demo 的 `TSK_SPEED_CHANGE` 先写
   Link Control 2 的 Target Link Speed，再写 Link Control 的 Retrain Link，等待 RP
   `Recovery`/`Recovery.Speed`/`user_lnk_up`。当前 K13 测试仍保留 Endpoint 配置空间和
   Root-Port 内部 directed write 两条入口；新增 `K13_RETRAIN_SOURCE=dual|rp|ep` 可按
   demo 风格选择 `rp` 单一路径做 A/B，但不能把 Xilinx EP/RP 的成功当作自定义 EP 的成功。

本轮已用 `K13_WAVEFORM=1 K13_TRACE=1` 重跑真实 Root-Port fallback 场景：VCS 编译、
elaboration、链接和初始 Gen1 枚举/BAR PASS。PIPE `phy_rate` 就是 Rate Contract 的
命令输出，trace 统一命名为 `pipe_rate_cmd`；它与原 `phy_rate_cmd` 同拍变化，并不是
两个提交阶段。只有 `active_rate` 在 Gen3 `PhyStatus` 后提交。随后 RXEQ done-only
触发 Gen1 fallback。最终分叉仍与此前一致：`K13_VCS_GEN3_RETRAIN_FAIL`，EP 停在
`Recovery.RcvrLock`，Root-Port 在后续 Detect/Polling 循环；没有新的 EQ/QPLL 失败证据。
因此 demo 借鉴内容已经落到可比对的观测基础设施和 directed-RP 操作顺序，尚未构成对
当前 Root-Port fallback TS 窗口分叉的修复。

## 三边界定位与 Retrain A/B（2026-08-21）

`K13_PIPE_COMPARE=1` 现在在同一套比较器中重建并对齐三处 Ordered Set：

1. Root-Port 并行 PIPE TX；
2. Endpoint GT 原始 RX；
3. Endpoint 公共 PIPE RX。

比较器为初始 Gen1 建链和 fallback 分别建立 epoch，逐个输出序号、类型、起止时间、
匹配源序号、跳过数量和跨边界延迟。`dual` 路径在 TS1→TS2 边界给出的关键结果为：

```text
RP PIPE TX:  TS2 seq=9  start=303899504  end=303955504
EP raw GT:   TS2 seq=5  start=304059529  end=304115529
RP_TO_GT:    src_seq=9 dst_seq=5 skipped=4 delay=160025 ps
GT_TO_PIPE:  src_seq=5 dst_seq=5 skipped=0 delay=0 ps
```

此前 TS1 的 `RP_TO_GT` 延迟稳定在约 `415975~416025 ps`；切换边界瞬间缩短到约
`160025 ps`，刚好越过 4 个完整 TS。GT 原始 RX 与公共 PIPE RX 的序号、类型和时间完全
一致。故丢失/拼接发生在 Endpoint GT 原始 RX 之前，当前应归类为 Xilinx 串行 GT/PHY
仿真模型在 Root-Port `state b->d` 时刷新或重排流水线的限制，而不是本工程 PHY wrapper、
公共 PIPE pipeline 或 Ordered-Set parser 丢数。生产 RTL 保持不变，独立 Partner Gate C
作为 fallback 闭环门禁。

官方 demo 风格的 `K13_RETRAIN_SOURCE=rp` 单路径 A/B 同样通过初始 Gen1 DLL Active、
枚举和 BAR 检查，随后在相同边界报告 `skipped=4`：切换时延从约 416 ns 缩短到约
160 ns，最终仍为 `K13_VCS_GEN3_RETRAIN_FAIL`。因此该分叉不由 Endpoint 与 Root-Port
双重触发 Retrain 引起；默认值继续保持兼容的 `dual`。

## 下一步

1. 保留三边界比较器作为串行模型升级后的回归诊断，并用独立 Partner Gate C 作为当前
   fallback 闭环门禁；不针对已定位到 GT 原始 RX 之前的模型丢失修改生产 RTL。
2. 在更新的 Xilinx 仿真模型或实板 ILA 环境重新验证真实 RP fallback；验收必须同时看到
   双方 Gen1 L0、Endpoint DLL Active 和 RP `user_lnk_up`，不能以 workaround 代替。
3. 只有真实 RP fallback 闭环后，才继续第二次 Gen3 Retrain，扩展真实 SDS/Data Stream、
   DLL Active、EQ Phase 0～3和事务恢复；在此之前不声明完整 K13 PASS。
