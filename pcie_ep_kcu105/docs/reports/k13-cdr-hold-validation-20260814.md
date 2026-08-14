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
- 诊断 WNS：`-0.069 ns`。

该 bit/LTX 仅用于诊断，不能作为正式实现版本。

诊断 bit/LTX SHA256：

```text
bit  7d5c8f2285c4b5fef32ac0d3bb56563a3e444dd02aec9912c34f459d4c13a81f
ltx  87dbd596b43ebe21d59aaff932e8e84ebcbaa17bc37e1d3239ca2e4631aaea43
```

实板采样文件：

`fpga/kcu105/build_k13_gen3_ila_cdr_hold_gt_primitive/capture/20260814_162038_u_ila_pipe.csv`

关键采样点：

| Sample | 事件 |
|---:|---|
| 704 | `phy_rate/rxrate` 即将切换，`as_cdr_hold_req=1` |
| 716 | `phy_rate: 0 -> 2`，`rxrate: 0 -> 2` |
| 726 | 实际 `QPLL1RESET: 0 -> 1`，`QPLL1LOCK: 1 -> 0` |
| 731 | 实际 `QPLL1RESET: 1 -> 0`，`QPLL1LOCK` 未恢复 |
| 4095 | `QPLL1LOCK` 仍为 0，`as_cdr_hold_req` 仍为 1 |

`QPLL1PD` 全程为 0，`PCIERATEQPLLRESET` 按预期产生脉冲；但 QPLL1LOCK 没有在
采样窗口内恢复。因此 CDR hold 已正确接入并生效，但没有阻止 QPLL1 在 Gen3
rate change 时失锁。

### 2.1 QPLL1 前置条件探针（本轮新增）

本轮 ILA probe20 直接绑定综合网表中的 `GTHE3_COMMON` 和
`GTHE3_CHANNEL` primitive pin，新增并验证了：

- `QPLL1REFCLKSEL=3'b001`；这是单一 `GTREFCLK0` 输入时的合法选择；
- `QPLL1PD=0`、`QPLL1LOCKEN=1`；
- `TXPLLCLKSEL=2'b10`、`RXPLLCLKSEL=2'b10`；两者均选择 QPLL1；
- `QPLL1REFCLKLOST=1`、`QPLL1FBCLKLOST=1` 在整个采样窗口保持为 1，且没有
  在 `QPLL1RESET` 释放后清零。

因此当前证据已从“helper FSM 输出了什么”推进到“实际 GT primitive 收到了什么”
以及“QPLL1 lock detector 报告了什么”。UG576 定义两个 `*CLKLOST` 为高有效的
参考/反馈时钟丢失指示，且定义 `QPLL1REFCLKSEL=001` 为 `GTREFCLK0`；本次硬件
结果使“QPLL1 参考/反馈前置条件未满足或 lock-detector 时序不正确”成为新的第一
嫌疑，但由于 Gen1/CPLL 基线中两个 loss 输出也保持高，尚不能单凭这一轮区分
“QPLL1 未启用时的无效状态”和“Gen3 切速后的真实丢时钟”。

Root Port 在本轮采样后仍未枚举 `01:00.0`，所以本证据仍不构成 Gen3 PASS。

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

1. 增加 `QPLL1LOCKDETCLK`、实际 `QPLL1REFCLK`/`QPLL1OUTREFCLK` 可观测性，确认
   `*CLKLOST` 在 QPLL1 被选中后是否仍为高；
2. 观察 `PCIEUSERRATESTART`、`PCIEUSERRATEDONE`、`PCIEUSERGEN3RDY` 的真实
   rate-handshake 时序，并核对生成 PHY 内部 rate FSM/pipeline；
3. 进行 Gen2-CPLL、Gen2-QPLL1、Gen3-QPLL1 的最小 A/B，隔离 PLL 选择和动态
   rate-change 复位问题；
4. 在上述门禁通过后，再恢复 RXEQ、Ordered-Set 和正式 Gen3 验收。

前序源码诊断提交：

```text
5cbac7f K13: hold RX CDR during Recovery.Speed
```

仿真生成的 `error.dat`、`rx.dat`、`tx.dat`、`ucli.key`、`xelab.pb` 和 `xvlog.pb`
不属于源码或报告归档。
