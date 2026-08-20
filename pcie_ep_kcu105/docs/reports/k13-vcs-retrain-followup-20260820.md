# K13 VCS Retrain Follow-up（2026-08-20）

## 本轮提交

- `4253fae`：增加 `requested_rate` 语义输出。LTSSM 在 `active_rate` 尚未收到
  `PhyStatus` 提交前，仍能广告本次 Recovery 目标；fallback 状态强制广告 Gen1。
- `2b8819d`：VCS runner 增加 `K13_RXEQ_BOOTSTRAP=0/1` 入口，用于分离纯切速门和
  RXEQ bootstrap 门。
- `65a0bbb`：RXEQ/peer 失败发生在原 Gen3 `Recovery.Speed` 已结束之后时，LTSSM
  重新进入一次 `Recovery.Speed`，完成显式 Gen1 fallback 的 PhyStatus 握手。

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

首次 Gen3 尝试在 RXEQ done-only 模型下回退到 Gen1。修正后 Endpoint 会重新进入
`Recovery.Speed`，并完成 Gen1 `PhyStatus`；但加密 Xilinx Root-Port 模型在该 fallback
阶段停留于自身 `Recovery.Speed`，没有向 Endpoint 发送完整的 8 个 Gen1 TS1。测试平台
随后发起第二次 Gen3 Retrain，Root-Port 只发出 5 个 TS1 后转 TS2，Endpoint 因此停在
`Recovery.RcvrLock`，最终未进入第二次 `Recovery.Speed/Equalization`。

这不是 QPLL、KCU105 线缆、J74、REFCLK 或 PERST# 结论；当前失败点是 VCS Root-Port
fallback 后的 Ordered-Set/状态闭环。实板验证必须等该 Gate C 分叉解决后再继续。

## 下一步

1. 在 VCS 中增加 Root-Port fallback 侧的原始 TS/状态观测，确认其停在
   `Recovery.Speed` 的等待条件（目标速率、PhyStatus 或 TS1 计数）。
2. 用独立 partner FSM 复现 Root-Port 的 Gen3→Gen1 fallback，再次 Gen3 Retrain；
   不修改生产 LTSSM 来放宽 TS1 计数，也不把 EQ workaround 当作速率 PASS。
3. Root-Port fallback 闭环通过后，再分别打开 `K13_RXEQ_BOOTSTRAP=1`，验证真实
   RXEQ/EQ Phase 0～3、Gen3 L0 和事务静默。
