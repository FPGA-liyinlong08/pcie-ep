# K13 QPLL 重锁问题：2026-08-25 上板 A/B 记录

## 问题定义

K13 Root Port Gen1→Gen3 retrain 后，预期 sequence 为：

```text
PHY_RATE=2 → PCIERATEQPLLRESET → QPLL1RESET → QPLL1LOCK → PHYSTATUS
```

本记录使用同一套 compact ILA、GT primitive probe、16-bit event recorder、250 MHz
采样时钟和 `phy_rate 0→2` 事务定义。baseline/TXEQ-off 使用
`K13_GOLDEN_RATE_REPLAY=0`；随后追加 Golden replay 实验，结果见文末。

## Bitstream

用户明确允许使用 WNS 为负的诊断 bitstream；这些 bitstream 仅用于本轮 KCU105
诊断，不作为生产时序签核结果。

| 版本 | 配置 | WNS / hold | SHA256 |
|---|---|---:|---|
| baseline | `K13_PRE_RATE_TXEQ_ENABLE=1` | `-0.246 / +0.004 ns` | `d470aa29f229b47201e35a04867ed1cffaf5d2271499f880bdb060be53433d5e` |
| TXEQ-off | `K13_PRE_RATE_TXEQ_ENABLE=0` | `-0.276 / +0.004 ns` | `39423c9b51c5ca00138542e586a4961698a30010210c75b0190647c28424a7e6` |

## 硬件环境与操作

- 板卡：KCU105，器件 `xcku040`。
- Root Port：远端 `192.168.11.126`，通过 `remote_pcie_host.sh retrain-gen3` 发起
  Gen3 retrain。
- 为清除此前失败事务状态，baseline 首次有效捕获前重启了一次远端 Root Port 主机。
- 每个版本重复两次；每次均为同一 Vivado 会话内 `program → arm → retrain → upload`。
- 不使用 Golden replay，不修改 QPLL 配置、`QPLL1LOCKDETCLK`、RXEQ、TS、EQ、LOCK
  或 `PCIEUSERRATEDONE`。

## Baseline 结果

两次均成功触发 QPLL reset ILA：

- [capture 1 CSV](../../fpga/kcu105/build_k13_gen3_ila_gt_primitive_qpll_prereq_minimal_diag/capture/20260825_140209_u_ila_pipe.csv)
- [capture 2 CSV](../../fpga/kcu105/build_k13_gen3_ila_gt_primitive_qpll_prereq_minimal_diag/capture/20260825_140729_u_ila_pipe.csv)

两个 event recorder 结果一致：

| 事件 | 相对 `phy_rate 0→2` |
|---|---:|
| QPLL1RESET rise | `+9` cycles |
| QPLL1RESET fall | `+14` cycles |
| QPLL1LOCK fall | `+9` cycles |
| QPLL1LOCK rise | valid，时间戳达到 `0xffff` |
| 最终 QPLL1LOCK | `0` |
| 最终 PHYSTATUS | `0` |

`0xffff` 是 16-bit recorder 在 250 MHz 下约 262 µs 的饱和值。两次 CSV 的末尾
event record 均为 `ffff00000009000e0009ffffffffffff0000ffff03f7`；按
`valid[13:15]` 的 live end-state 解码为 `QPLL1LOCK=0、QPLL1RESET=0、PHYSTATUS=0`。
中间出现的 `...23f7` 只是较早采样点，不能作为窗口末端的锁定证据。

## TXEQ-off 结果

两次均完成 bitstream 下载并 arm；远端 Root Port 两次均回到 Gen1，目标速率保持
8 GT/s，但 ILA 在等待窗口内都没有触发 `PCIERATEQPLLRESET`。TXEQ-off 没有产生
与 baseline 相同的可捕获 QPLL reset 事务，因此不能归因于“TXEQ-off 使 QPLL 更快
重锁”。本轮没有生成 TXEQ-off capture CSV，避免把空 buffer 当作硬件证据。

## 当前结论与后续

1. baseline 的中间采样出现过 lock-rise 事件，但两次 CSV 末尾状态均为
   `QPLL1LOCK=0、QPLL1RESET=0、PHYSTATUS=0`，不能称为最终恢复 LOCK。
2. TXEQ-off A/B 未进入相同的 rate/QPLL reset 事务；它改变了 rate contract 的
   前置路径，值得作为下一轮 command ownership/时序差分的入口，但还不能直接
   作为生产修复。
3. 下一轮优先做 K02/K13 的精确 PHY command ownership 与输入序列差分；Golden
   replay 追加实验结果见下节。

## Golden replay 追加实验

Golden replay 版本使用 `K13_PRE_RATE_TXEQ_ENABLE=1`、
`K13_GOLDEN_RATE_REPLAY=1`，其余 K13、GT probe、event recorder 和采样时钟保持
不变。由于 `K13_MINIMAL_DIAG=1` 的 timing gate 仍会拦截负 WNS，使用用户明确
授权的 routed DCP 生成诊断 bitstream。

| 项目 | 结果 |
|---|---|
| WNS / hold | `-0.322 / +0.004 ns` |
| DRC | `0 Errors`（bitgen 4 个调试核 warning） |
| bitstream | `build_k13_gen3_ila_gt_primitive_qpll_prereq_golden_replay_minimal_diag/impl/k13_gen3_endpoint_ila_golden_replay_negative_wns.bit` |
| SHA256 | `21a6bb5493d9a8a53b9cdc581e4d9b941b134826dae74d6cba3bb23f6922175c` |
| capture | [Golden replay CSV](../../fpga/kcu105/build_k13_gen3_ila_gt_primitive_qpll_prereq_golden_replay_minimal_diag/capture/20260825_144314_u_ila_pipe.csv) |

硬件流程为同一 Vivado 会话内 `program → arm → Root Port retrain → upload`。
Golden replay 成功触发 `PCIERATEQPLLRESET`，但 CSV 末尾 event record 为
`ffff00000008000d0008ffffffffffff0000ffff03f7`，仍表示：

```text
QPLL1LOCK=0 / QPLL1RESET=0 / PHYSTATUS=0
```

远端 Root Port 最终状态仍为 `2.5GT/s x1`，未完成 Gen3 equalization。因此在
当前实现中，Golden replay 没有使 QPLL 在观测窗口末端恢复 LOCK，也没有产生
`PHYSTATUS/PCIEUSERGEN3RDY`。

本次 sticky event timestamp 在第二次 rate trigger 前已经达到 `0xffff`，所以
`valid[5]` 的 lock-rise 事件不能单独证明本次触发对应的 relock；本次结论以
触发后末尾的 `valid[13:15]` live end-state 为准。下一轮应让 recorder 在每个
新的 `phy_rate 0→2` 前沿重新 arm，或每次测试重新清除事务状态。
