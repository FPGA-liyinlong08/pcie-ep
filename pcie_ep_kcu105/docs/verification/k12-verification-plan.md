# K12 Recovery.Speed / Equalization 验证计划

状态：**v0.3；K12-A/B/C/D及K12-E真实PHY影子适配已执行PASS，Gen3生产接线继续建设**

## 1. 分层验证

- Verilator/cocotb：LTSSM Recovery/EQ定向、随机、超时和错误注入。
- 行为PHY Partner：可编程速率完成延迟、EQ done、拒绝、非法反馈和CDR失锁。
- VCS：Xilinx standalone PHY与Root Port真实串行Gen1→Gen3过程。
- Vivado：KU040综合、CDC、DRC、完整布局布线；release配置WNS必须不小于0。
- 实板：K12只验证训练和安全回退；Gen3枚举/MMIO作为K13门禁。

## 2. 测试平台先行门

K12-A已先完成request/ack mailbox的正向和负向自测：`K12_CHECKER_SELFTEST_PASS`、
`K12A_CDC_MAILBOX_PASS`。当前只覆盖valid保持、payload原子性、busy/overflow和
非法速率透传；以下Recovery/EQ六类Checker仍是后续K12-B～K12-D门禁。

K12-B已增加独立Recovery.Speed骨架验证：`K12_CHECKER_SELFTEST_PASS`、
`K12B_RECOVERY_SPEED_PASS`。当前覆盖正常切速、PHY done超时、对端拒绝、非法目标、
Gen1 fallback及早期PHY完成负向检查；尚未覆盖真实TS和EQ。

K12-C已增加独立EQ控制器验证：`K12_CHECKER_SELFTEST_PASS`、
`K12C_EQ_PHASES_PASS`。当前覆盖Phase 0～3顺序、非法Preset/Coefficient、TX/RX done
超时和Phase跳跃负向检查；随后已完成 K12-A/B/C 行为 PHY Partner 集成，覆盖正常
速率/EQ、Peer Reject、EQ timeout 和 Ordered Set 边界提前 done 负向检查，固定输出
`K12_INTEGRATION_PASS` 与 `K12_INTEGRATION_CHECKER_SELFTEST_PASS`。

在RTL实现前，错误Stub必须至少被以下Checker检出：

1. 未等待PHY done就离开Recovery.Speed；
2. EQ Phase乱序或跳过；
3. 非法Preset/系数仍驱动PHY；
4. timeout后未回退Gen1；
5. 切速期间仍发送TLP/DLLP；
6. Ordered Set中途切换状态或速率。

## 3. Directed 场景

1. Gen1保持：K12默认关闭时逐拍兼容K11 release。
2. 正常Gen1→Gen3：Recovery.Speed完成，Phase 0→1→2→3，进入新速率Idle/L0。
3. 对端拒绝升速：留在或回到Gen1 L0。
4. PHY Speed done超时：错误计数+Gen1回退。
5. TX EQ done超时与RX EQ done超时：分别回退且命令清零。
6. 非法Preset、非法Coefficient和非法Phase：不得驱动PHY。
7. CDR失锁：中止EQ并回退Recovery.RcvrLock/Gen1。
8. Phase 0～3每个边界都验证完整Ordered Set，不重复G12缺陷。
9. Recovery期间DLL/TLP静默，新L0后重新InitFC并恢复事务。
10. Hot Reset/PERST在每个Speed/EQ子状态到达时都能回到确定复位状态。

## 4. 随机与覆盖

- 随机PHY完成延迟、对端TS字段、Preset、Coefficient、拒绝点和错误时刻。
- 覆盖所有状态和合法跳转、所有错误出口、每个Phase的成功/失败、Gen1回退及再次升速。
- 不允许非法状态跳转、无限等待、命令单拍丢失、TLP泄漏或计数器回绕。

## 5. 阶段通过标记

计划中的自动入口为`make k12`，实现后固定输出：

```text
K12_CHECKER_SELFTEST_PASS
K12_RECOVERY_SPEED_PASS
K12_EQ_PHASES_PASS
K12_FALLBACK_PASS
K12_VCS_REAL_PHY_PASS
K12_IMPL_PASS
```

K12-D已补充CDR loss、TS类型/速率/Lane/Link合法性和Gen1安全回退；K12-E已在
真实standalone PHY + Root Port VCS中完成影子适配，输出`K12E_VCS_REAL_PHY_PASS`，
并保持K11-B2枚举/BAR门禁通过。上述标记、CDC/DRC和非负WNS全部通过后，才生成
K12冻结报告并进入K13；真实Gen3 retrain/EQ生产驱动属于K13生产集成门。
