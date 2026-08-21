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
  `user_lnk_up`）后才允许第二次 Retrain；增加双方 fallback 原始 PIPE 采样，并将
  等待窗口改为 `K13_FALLBACK_WAIT` 可配置（默认 20,000 个 `phy_pclk`）。

## 已通过

- K11B2 顶层 lint、K13 controller lint、K13 integration lint。
- K13 controller Verilator：4/4 PASS。
- K13 production LTSSM + behavioral partner Verilator：2/2 PASS。
- 单元波形确认 `requested_rate=Gen3` 可早于 `active_rate=Gen3`，命令/提交顺序不变。
- 真实 Xilinx Root-Port VCS 的初始 Gen1 枚举、BAR、InitFC/DLL 仍 PASS；首次
  Gen3 速率命令、Gen3 `PhyStatus` 和 RXEQ failure→Gen1 fallback 事件可观察。

## 独立 Partner Gate C 进展

在 `sim/verilator/k13_integration` 增加了独立的脚本化 Partner 状态流程：第一次
Gen3 只返回 RXEQ `done`（不返回 `AdaptDone`），等待 DUT 完成 Gen1 fallback 并由
Partner 发送 Gen1 TS1/TS2、Idle；确认回到 Gen1 L0 后再次发起 Gen3 Retrain，第二次
提供完整 RXEQ completion。全量三项 K13 integration 回归通过：

```text
production_ltssm_gen1_to_gen3_eq_closed_loop                 PASS
partner_initiated_speed_change_closes_recovery_and_eq        PASS
production_gen3_failure_fallback_then_retry                  PASS
```

第三项的验收边界是第二次 Gen3 `Recovery.Idle`、`phy_rate=Gen3`、`active_rate=Gen3`、
`negotiated_speed=Gen3` 和 `eq_done=1`。当前 `pcie_ltssm_mac_gen1` 尚未把 Gen3
Recovery.Idle 的 Data Stream/SDS 转成 L0，因此该测试没有宣称 Gen3 L0；这保留给后续
Gen3 协议冻结门。

## 真实 Root-Port VCS 当前分叉

命令：

```text
K13_ENABLE=1 K13_VCS_RETRAIN=1 K11B2_MODE=1 ./sim/vcs/run_k11b_serial.sh
```

首次 Gen3 尝试在 RXEQ done-only 模型下回退到 Gen1。修正后 Endpoint 在
`275.419629 ns` 产生 Gen1 `PhyStatus`，并恢复到 Gen1 命令；Endpoint 随后连续发送
合法 Gen1 TS1（原始 PIPE 采样为 `9fbc, ff00, 0002, 4a4a...`）。但加密 Xilinx
Root-Port 在 `cfg_ltssm_state=c`、Gen1 rate 下先保持 `TX Electrical Idle=1`、
`data=0`，约 `303.287505 ns` 才重新进入 Recovery 并发送 TS。新增两侧原始 PIPE
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

## 下一步

1. 对加密 Root-Port fallback 的 PIPE 模式切换做最小化对照：比较初始 Gen1 建链与
   fallback 的首个 `COM` 对齐、RX 延迟和 Root-Port `state=b→d` 触发条件，确认
   Endpoint 解析少收的 TS1 是串行模型窗口相位问题还是由对端状态响应触发。
2. 用独立 partner FSM 复现 Root-Port 的 Gen3→Gen1 fallback，再次 Gen3 Retrain；
   不修改生产 LTSSM 来放宽 TS1 计数，也不把 EQ workaround 当作速率 PASS。
3. Root-Port fallback 闭环通过后，再分别打开 `K13_RXEQ_BOOTSTRAP=1`，验证真实
   RXEQ/EQ Phase 0～3、Gen3 L0 和事务静默。
