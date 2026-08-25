# K13 QPLL 两阶段诊断实现

本实现把 K13 QPLL 重锁问题限定为两个可复现的 A/B 变量，默认生产路径不变：

- `K13_PRE_RATE_TXEQ_ENABLE=1`：保留当前 K13 pre-rate TXEQ 行为。
- `K13_PRE_RATE_TXEQ_ENABLE=0`：只旁路 pre-rate TXEQ transaction，直接满足 rate contract 的 pre-rate gate；不等待 `phy_txeq_done`。
- `K13_GOLDEN_RATE_REPLAY=1`：Golden replay 代码保留为后续诊断实验；本轮 baseline/A-B 固定为 `0`，不以猜测的 gap 或额外 ownership 作为结论。

## Stage 0 构建

最小 timing-clean 诊断 bit：

```bash
cd /home/wx/Documents/PCIe/pcie_ep_kcu105
K13_ENABLE=1 K11B2_ILA_DEBUG=1 K13_MINIMAL_DIAG=1 \
K13_PRE_RATE_TXEQ_ENABLE=1 K13_GOLDEN_RATE_REPLAY=0 \
  ./fpga/kcu105/run_k11b2_impl.sh
```

`K13_MINIMAL_DIAG=1` 自动保留 GT primitive probe、QPLL event recorder 和 compact command bundle，并关闭宽 PIPE/Core ILA；Vivado 脚本会要求 setup/hold timing clean。事件 recorder 使用 16-bit 时间戳，采样后应在 retrain 后约 200–250 us 读取，不重新 reboot、复位或 arm。recorder 不再被 `as_mac_in_detect` 清除，而是以 `phy_rate 0→2` 作为事务零点；record bus 的 `valid[13:15]` 保留窗口末端的 `QPLL1LOCK/QPLL1RESET/PHYSTATUS` 最终电平。

最小 ILA 使用 1024 深度和 459-bit 稳定 probe layout；长时间窗口只由 event recorder 提供。

## Stage 1 / Stage 2

```bash
# Stage 1: 关闭 pre-rate TXEQ
K13_ENABLE=1 K11B2_ILA_DEBUG=1 K13_MINIMAL_DIAG=1 \
K13_PRE_RATE_TXEQ_ENABLE=0 K13_GOLDEN_RATE_REPLAY=0 \
  ./fpga/kcu105/run_k11b2_impl.sh

# Stage 2: 暂不纳入本轮 bitstream；保留代码供下一轮精确 ownership replay
```

两种诊断开关都只在 K13 构建中生效；没有修改 RXEQ、TS、EQ、QPLL 配置、`QPLL1LOCKDETCLK` 或强制 `LOCK/DONE` 的逻辑。

## 当前构建与上板状态

用户已明确授权使用 WNS 为负的诊断 bitstream。两个版本均已完成 bitgen，且
DRC 为 0 Error、CDC 无 critical/error；负 slack 仅作为本轮诊断风险记录：

| 版本 | 配置 | WNS / hold | bitstream |
|---|---|---:|---|
| baseline | `K13_PRE_RATE_TXEQ_ENABLE=1` | `-0.246 / +0.004 ns` | `impl/k13_gen3_endpoint_ila_negative_wns.bit` |
| TXEQ-off | `K13_PRE_RATE_TXEQ_ENABLE=0` | `-0.276 / +0.004 ns` | `impl/k13_gen3_endpoint_ila_pre_rate_txeq_off_negative_wns.bit` |

baseline 已在 KCU105 上完成两次有效 Root Port retrain capture：

- `capture/20260825_140209_u_ila_pipe.csv`
- `capture/20260825_140729_u_ila_pipe.csv`

两次 recorder 结果一致：`QPLL1RESET` rise=`+9`、fall=`+14`，`QPLL1LOCK`
fall=`+9`；`QPLL1LOCK` rise valid 但时间戳达到 16-bit 上限（约 262 us），最终
`QPLL1LOCK=1`，`PHYSTATUS=0`。因此 baseline 不是“始终不锁”，而是本次窗口内
晚重锁且未完成 PHY completion。

TXEQ-off 已在 KCU105 上完成两次 retrain 尝试；两次均未触发
`PCIERATEQPLLRESET` ILA，远端链路保持 Gen1，故当前不能判定 TXEQ-off 带来更快
QPLL 重锁；它至少没有进入与 baseline 相同的可捕获 QPLL reset 事务。Golden replay
仍固定为 `0`，未编程。
