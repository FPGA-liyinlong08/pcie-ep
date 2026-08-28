# K15 Autonomous Gen3 Recovery + Equalization 验证计划

日期：2026-08-28

当前状态：K15-A/B及本地EQ/Idle定向门禁通过；Full XDMA双epoch Gate未通过。
详见`docs/reports/k15-autonomous-gen3-equalization-20260828.md`。

## 1. 范围

K15只验证从PERST#到Gen3 idle-only L0的生产控制路径：

```text
Gen1 initial training (Rate ID=0e, Speed Change=0)
  -> Gen1 L0
  -> Root Port autonomous Recovery / TS1 Rate ID=8e
  -> partner request accept
  -> Recovery.Speed / PHY_RATE=Gen3 / QPLL / PhyStatus
  -> Recovery.RcvrLock
  -> Equalization Phase 0 -> 1 -> 2 -> 3
  -> Recovery.RcvrCfg -> Recovery.Idle
  -> Gen3 idle-only L0
```

Gen3 DLLP/TLP、128b/130b正常数据传输、SKP和流控不属于K15，由K16负责。K15在
Gen3 L0必须保持DLL/TLP离线，只发送SDS和逻辑Idle，不得复用Gen1 framer。

## 2. 强制约束

- `GEN3_AUTO_RETRAIN_CYCLES=0`；
- 不使用`force`、人工TS、`setpci`、软件Retrain或Root Port配置写触发升速；
- Full VCS使用真实XDMA Root Port和生产`pcie_phy_x1_gen3`模型；
- PHY raw command只能由`pcie_phy_command_ctrl`驱动；
- 必须连续通过两个PERST# epoch；
- timeout、fallback、EQ failure或Gen3 L0中DLL/TLP上线均立即失败。

## 3. Gate

| Gate | 必须观察到 | 当前自动化入口 |
| --- | --- | --- |
| K15-A | 初始真实EP TS的Rate ID为`0e`、bit7为0，当前PHY仍为Gen1 | `make k15-vcs` |
| K15-B | 真实RP发送`8e`，partner pending被接受，Golden rate change、QPLL和fresh PhyStatus完成 | `make k15-vcs`、`make k14-direct-vcs` |
| K15-C | 显式状态`28/29/2a/2b`依次完成，角色映射为Upstream Phase2 RX Adapt、Phase3 TX Adapt | `make k15-directed-test`、`make k15-vcs` |
| K15-D | Recovery.Idle进入Gen3 idle-only L0并稳定256个PIPE周期，两个epoch均通过 | `make k15-vcs` |

`make k15-static`覆盖EQ FSM、Gen3 OS/idle loopback、PHY semantic/raw owner、K14
Recovery.Speed回归、命令所有权检查和生产顶层lint。`make k15`串联static与Full VCS；
只有日志包含`K15_VCS_PASS epochs=2`时K15才允许关闭。

## 4. Full VCS必需标记

每个epoch必须按因果顺序出现：

```text
K15_INITIAL_GEN3_CAPABILITY_SEEN
K15_RP_SPEED_CHANGE_SEEN
K15_PARTNER_ACCEPT
K15_GEN3_RATE_DONE
K15_EQ_PHASE0_DONE
K15_EQ_PHASE1_DONE
K15_EQ_PHASE2_DONE
K15_EQ_PHASE3_DONE
K15_RECOVERY_IDLE
K15_GEN3_L0_PASS
```

第二个epoch完成后才打印：

```text
K15_VCS_PASS epochs=2
```

任何子集都不能替代最终标记，也不能通过延长timeout、绕过partner确认或在
testbench中推进EQ状态来生成PASS。
