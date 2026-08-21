# K13 VCS Retrain Follow-up（2026-08-20）

## 本轮提交

- `4253fae`：增加 `requested_rate` 语义输出。LTSSM 在 `active_rate` 尚未收到
  `PhyStatus` 提交前，仍能广告本次 Recovery 目标；fallback 状态强制广告 Gen1。
- `2b8819d`：VCS runner 增加 `K13_RXEQ_BOOTSTRAP=0/1` 入口，用于分离纯切速门和
  RXEQ bootstrap 门。
- `65a0bbb`：RXEQ/peer 失败发生在原 Gen3 `Recovery.Speed` 已结束之后时，LTSSM
  重新进入一次 `Recovery.Speed`，完成显式 Gen1 fallback 的 PhyStatus 握手。
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

## 真实 Root-Port VCS 当前分叉

命令：

```text
K13_ENABLE=1 K13_VCS_RETRAIN=1 K11B2_MODE=1 ./sim/vcs/run_k11b_serial.sh
```

首次 Gen3 尝试在 RXEQ done-only 模型下回退到 Gen1。修正后 Endpoint 在
`275.419629 ns` 产生 Gen1 `PhyStatus`，并恢复到 Gen1 命令；Endpoint 随后连续发送
合法 Gen1 TS1（原始 PIPE 采样为 `9fbc, ff00, 0002, 4a4a...`）。但加密 Xilinx
Root-Port 在 `cfg_ltssm_state=c`、Gen1 rate 下先保持 `TX Electrical Idle=1`、
`data=0`，约 `303.287505 ns` 才重新进入 Recovery 并发送 TS。该次只发出 5 个
TS1（随后转 TS2），Endpoint 按标准的 8-TS1 门限停在 `Recovery.RcvrLock`；双方从未
同时到达 Gen1 L0，因此新的 Gen3 Retrain 没有被测试平台发起。

将等待窗口从 20,000 扩展到 100,000 个 `phy_pclk` 仍未观察到双方 Gen1 L0；Root-Port
随后多次退回 Detect/Polling。这个结果排除了“第二次 Retrain 发得太早”这一测试平台
问题，也没有证据表明是 EQ 或 QPLL 锁定导致该分叉。

这不是 QPLL、KCU105 线缆、J74、REFCLK 或 PERST# 结论；当前失败点是 VCS Root-Port
fallback 后的 Ordered-Set/状态闭环。实板验证必须等该 Gate C 分叉解决后再继续。

## 下一步

1. 对加密 Root-Port 的 fallback TS1 计数/状态转换继续做最小化观测，确认 5-TS1
   早转 TS2 是模型的固定行为还是由 Endpoint 响应触发。
2. 用独立 partner FSM 复现 Root-Port 的 Gen3→Gen1 fallback，再次 Gen3 Retrain；
   不修改生产 LTSSM 来放宽 TS1 计数，也不把 EQ workaround 当作速率 PASS。
3. Root-Port fallback 闭环通过后，再分别打开 `K13_RXEQ_BOOTSTRAP=1`，验证真实
   RXEQ/EQ Phase 0～3、Gen3 L0 和事务静默。
