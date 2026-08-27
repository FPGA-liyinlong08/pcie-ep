# K14 Recovery.Speed 触发方式 A/B 测试

本测试将历史 D4 的 Endpoint 触发和后续 Root-Port-only 触发严格分开，不能用
Root-Port-only 结果代替历史 D4 重跑结论。

## Test A：严格复现历史 D4

执行入口：

```text
make k14-recovery-speed-test-a-hw K14_REPEAT_CYCLES=1
```

远端操作顺序：

```text
Root Port Target=Gen1 + Retrain
  -> 连续 3 次确认 2.5 GT/s、x1、DLLActive
  -> Endpoint Link Control.Retrain Link=1
  -> Root Port Target Link Speed=Gen3
  -> Root Port Link Control.Retrain Link=1
```

该路径要求日志出现 `D4_ENDPOINT_RETRAIN_WRITE_PASS`，并由 ILA/CSV确认：

```text
PHY_RATE=2
QPLL1LOCK=1
PCIERATEGEN3=1
PCIEUSERGEN3RDY=1
PHYSTATUS 上升沿
```

## Test B：K14 Root-Port-only 对照

执行入口：

```text
make k14-recovery-speed-test-b-hw K14_REPEAT_CYCLES=1
```

远端操作顺序：

```text
Root Port Target=Gen1 + Retrain
  -> 连续 3 次确认 2.5 GT/s、x1、DLLActive
  -> 不写 Endpoint Retrain bit
  -> Root Port Target Link Speed=Gen3
  -> Root Port Link Control.Retrain Link=1
```

该路径重点检查 Endpoint 的
`partner_retrain_valid = os_ts1_valid && os_rate_id[7]` 是否被接受，并确认同样的
Recovery.Speed/PHY rate transaction 是否完成。

## Test C：烧写后远端 reboot 观察

执行入口：

```text
make k14-recovery-speed-test-c-hw K14_REPEAT_CYCLES=1
```

操作顺序为：

```text
烧写 K14 bitstream → ARM ILA（默认触发条件与 Test A 完全一致）
  → 远端 sudo reboot → 等待 SSH 和 Endpoint 恢复
  → 仅抓取 reboot 后的 Recovery/PHY 信号
```

Test C 不执行任何 `setpci`，也不主动请求 Gen3；它只增加 reboot 变量。默认触发为
`event_state=8 AND PHY_RATE=2`，与 Test A 完全一致，因此只有成功切速才会生成捕获。
如需诊断未完成事务，可使用 `K14_C_TRIGGER=recovery`（Recovery.Speed=18）或
`K14_C_TRIGGER=detect`（Detect.Quiet=0），但这两种诊断结果不能与 Test A 的成功
捕获直接做 PASS/FAIL 等价比较。

## 入口与判定隔离

- `scripts/remote_pcie_host.sh retrain-gen3-d4`：Test A。
- `scripts/remote_pcie_host.sh retrain-gen3-rp-only`：Test B。
- `retrain-gen3` 保留为 Test B 的兼容别名。
- 两个测试共用 K14 ILA bitstream和 `analyze_k02_golden_trace.py`，但日志、CSV前缀及
  PASS标记独立。
- 本测试只签署 PHY 切速；EIEOS、128b/130b、EQ 和 Gen3 L0 仍属于 Phase E。

## 本轮实测记录（2026-08-27）

- Test A 已在 `HW_SERVER_URL=127.0.0.1:3121` 下完成 1 次严格复现并 PASS：
  `D4_ENDPOINT_RETRAIN_WRITE_PASS`，`PHY_RATE=2`，QPLL lock、PHYSTATUS 和
  `PCIEUSERGEN3RDY` 全部满足，CSV 为
  `build_k14_recovery_speed/capture/20260827_110857_k14_recovery_speed.csv`。
- Test B 已完成远端 Root-Port-only 操作，但 K14 success/fail 终态 ILA 均未捕获；
  远端仍保持 Gen1。当前结论是 **B 尚未通过**，不能宣称 partner_retrain_valid
  路径已经进入 Recovery.Speed。下一步应使用 `PHASE_E1_TIMING_DEBUG=1` 的 timing
  recorder 直接检查 T0（partner_retrain_valid）和 T1/T2/T4 边界，再决定是请求未被
  接受还是 PHY 操作失败。
- 已使用现成 timing recorder 做一次 B 诊断：`phase_e1_timing_dump_active_w` 未触发，
  没有生成 timing CSV；结合 K14 success/fail ILA 均无事件，当前证据更接近
  `partner_retrain_valid` 未形成，而不是 PHY 已切速后失败。该判断仍需增加直接
  `partner_retrain_valid` probe 或修复 recorder 的无请求超时快照后再签署。
- Test C 已完成 1 次纯 reboot 观察并 PASS：烧写/ARM 后执行远端 `sudo reboot`，
  等待 SSH 经历断开并恢复（约 32 s），随后 Endpoint 重新枚举为 `1234:e001`、
  Gen1 x1、`DLActive+`；全程没有执行 `setpci`。捕获为
  `build_k14_recovery_speed/capture/20260827_115801_k14_recovery_speed.csv`。
- Test C 已按 Test A 的同一成功触发重新执行 1 次：ILA 日志确认
  `event_state=8 AND PHY_RATE=2`，但 reboot 后 30 s 内未出现该事件，因而没有生成
  capture CSV；远端最终仍为 `1234:e001`、Gen1 x1、`DLActive+`。该结果是“同触发条件下
  未发生 Gen3 PHY 完成事务”，不是触发器不一致。若需观察中间态，仍可显式使用
  `K14_C_TRIGGER=recovery` 或 `K14_C_TRIGGER=detect`，但只能作为诊断抓取。
