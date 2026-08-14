# K13 Recovery.Speed CDR-hold 验证报告（2026-08-14）

本文档记录本轮实际执行结果、已知限制和冻结决定。硬件连接、JTAG 和远程 Root
Port 操作说明保留在 `docs/kcu040-hardware-and-remote.md`。

## 1. 修改内容

依据 PG239 PHY assist contract，生产 LTSSM 在 `Recovery.Speed` 拉高
`as_cdr_hold_req`，离开该状态后拉低：

```verilog
assign as_cdr_hold_req = (ltssm_state == RECOVERY_SPEED);
```

当前 MAC 尚未实现 L1/Loopback 状态，因此本轮只覆盖 `Recovery.Speed`。该信号同时
加入 K13 诊断总线；集成仿真在进入 `Recovery.Speed` 时断言为 1，回到
`Recovery.Idle` 后断言为 0。

涉及文件：

- `rtl/phy/pcie_ltssm_mac_gen1.sv`
- `rtl/ep/kcu105_pcie_ep_gen1_top.sv`
- `sim/verilator/k13_integration/k13_ltssm_partner_top.sv`
- `sim/verilator/k13_integration/test_k13_integration.py`
- `fpga/kcu105/run_k11b2_impl.{sh,tcl}`
- `fpga/kcu105/run_k11b2_ila_hw.tcl`

## 2. 实际执行结果

- K13 集成 lint：通过。
- K13 集成仿真：两条测试 `2/2 PASS`。
- Vivado 诊断实现：`K13_ILA_IMPL_PASS`。
- 器件：`xcku040-ffva1156-2-e`。
- GT：`GTHE3_CHANNEL_X0Y7` / `GTHE3_COMMON_X0Y1`。
- 诊断 WNS：`-0.053 ns`。

该 bit/LTX 仅用于诊断，不能作为正式实现版本。

诊断 bit/LTX SHA256：

```text
bit  e31eccff25b8c5a4366841273d25dbacec33978c18cf8983d91d532690b96b0e
ltx  cdb4eee983c5854a8cf5fd27dcdc2aa5d9212cba195bceaf3fac0c7cdf2b60d4
```

实板采样文件：

`fpga/kcu105/build_k13_gen3_ila_cdr_hold_gt_primitive/capture/20260814_114555_u_ila_pipe.csv`

关键采样点：

| Sample | 事件 |
|---:|---|
| 680 | `as_cdr_hold_req: 0 -> 1`，LTSSM 进入 `Recovery.Speed` |
| 692 | `phy_rate: 0 -> 2`，`rxrate: 0 -> 2` |
| 702 | `QPLL1LOCK: 1 -> 0`，实际 `QPLL1RESET: 0 -> 1` |
| 707 | 实际 `QPLL1RESET: 1 -> 0` |
| 4095 | `QPLL1LOCK` 仍为 0，`as_cdr_hold_req` 仍为 1 |

`QPLL1PD` 全程为 0，`PCIERATEQPLLRESET` 按预期产生脉冲；但 QPLL1LOCK 没有在
采样窗口内恢复。因此 CDR hold 已正确接入并生效，但没有阻止 QPLL1 在 Gen3
rate change 时失锁。

## 3. 已知限制

- 当前结果是诊断构建，WNS 为负，不能作为正式实现时序通过。
- Root Port 在本轮采样后没有保持 Endpoint 枚举，不能宣称 Gen3 x1、BAR 或
  最终链路通过。
- `as_cdr_hold_req` 当前只覆盖 `Recovery.Speed`；L1 和 Loopback 状态尚未实现。
- RXEQ 尚未参与本次失败窗口；`phy_rxdata_valid/start_block/sync_header` 没有
  形成有效 Gen3 RX block。
- Gen1 x1 枚举成功只证明 Gen1/CPLL 基线可用，不能证明 Gen3/QPLL1 路径正常。

## 4. 冻结决定

本 A/B 关闭“`as_cdr_hold_req=0` 是 QPLL1 失锁根因”的假设，但该信号修正仍然
保留，作为 PG239 合约要求。

以下范围继续冻结，不进入下一轮重构：

- 完整 Gen3 EQ 重构；
- DLL/TLP/BAR 修改；
- 最终 Gen3 PASS 标记；
- 用当前负 WNS 诊断 bit 作为正式硬件实现。

## 5. 下一步优先级

1. 观察 `PCIEUSERRATESTART`、`PCIEUSERRATEDONE`、`PCIEUSERGEN3RDY` 的真实
   rate-handshake 时序；
2. 核对生成 PHY 内部 rate FSM/pipeline 与 `GTHE3_CHANNEL` rate 端口的对应关系；
3. 核对 `QPLL1RESET` 脉冲后的参考时钟、复位释放和 lock-detector 恢复条件；
4. 在上述门禁通过后，再恢复 RXEQ、Ordered-Set 和正式 Gen3 验收。

源码诊断提交：

```text
5cbac7f K13: hold RX CDR during Recovery.Speed
```

仿真生成的 `error.dat`、`rx.dat`、`tx.dat`、`ucli.key`、`xelab.pb` 和 `xvlog.pb`
不属于源码或报告归档。
