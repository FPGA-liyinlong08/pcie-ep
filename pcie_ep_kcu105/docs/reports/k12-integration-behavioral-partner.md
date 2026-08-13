# K12-A/B/C 行为 PHY Partner 集成报告

日期：2026-08-13  
状态：**PASS / K12 集成仿真门禁通过**

## 1. 范围

本次把 K12-A CDC mailbox、K12-B Recovery.Speed 和 K12-C Equalization
Phase 0～3 接入同一个行为 PHY Partner 顶层，检查跨模块握手和
Ordered Set 边界契约。该顶层用于 K12 仿真门禁，不替代 Xilinx standalone
PHY、真实 Root Port 串行模型或 KCU105 实板验证。

集成文件：

- `sim/verilator/k12_integration/k12_behavioral_partner_top.sv`
- `sim/verilator/k12_integration/test_k12_integration.py`
- `sim/verilator/k12_integration/Makefile`

## 2. 覆盖场景与结果

| 场景 | 结果 | 检查点 |
|---|---|---|
| Gen1→Gen3 正常速率握手 | PASS | mailbox 传递目标速率；Partner 在边界产生 phystatus；进入 Gen3 L0 |
| EQ 正常握手 | PASS | Phase 0→1→2→3→done，TX/RX done 均在边界产生 |
| Peer Reject | PASS | Recovery.Speed 记录拒绝并回退 Gen1 |
| EQ timeout | PASS | EQ 进入 fail，清除有效控制，停止等待 |
| 提前 Partner done 负向注入 | PASS | checker 置位 `boundary_violation`，负向测试按预期失败 |

自动回归输出：

```text
TESTS=4 PASS=4 FAIL=0 SKIP=0
K12_INTEGRATION_PASS
K12_INTEGRATION_CHECKER_SELFTEST_PASS ordered_set_boundary=1
K12_INTEGRATION_GATE_PASS
```

## 3. 结论与限制

K12-A/B/C 已完成行为 Partner 级联验证，正常路径没有发现速率或 EQ
完成信号越过 Ordered Set 边界，Peer Reject 和 EQ timeout 均能回到安全路径。
`force_early_done` 是专用故障注入开关，负向门禁确认边界 checker 可检出违规。

本报告不宣称 Gen3 真实链路、真实 PHY EQ、VCS Root Port 串行或实板枚举通过；
这些内容仍属于 K12-D/K12-E 及 K13 门禁。下一步是把同一接口契约接入真实 PHY
串行环境，并补充 CDR loss、TS 合法性和生产 LTSSM 接线验证。
