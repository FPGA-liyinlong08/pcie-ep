# K12-A Retrain CDC mailbox 执行记录

日期：2026-08-13

状态：**K12-A CDC子项 PASS；Recovery.Speed/EQ 尚未实现**

## 1. 本次执行范围

在不改动K11生产LTSSM的前提下，先实现Core域到`phy_pclk`域的单深度
request/ack mailbox，验证`retrain_link_pulse`和`target_link_speed[1:0]`
作为一个原子命令跨域。生产模块为：

```text
rtl/common/pcie_retrain_cdc_mailbox.sv
```

源域在ack返回前保持payload不变；目标域`d_retrain_valid`保持到
`d_retrain_accept`，忙时重复请求置`s_overflow_sticky`，不覆盖当前命令。

## 2. 验证入口和结果

```text
make k12a
K12_CHECKER_SELFTEST_PASS valid_hold=1 payload_atomic=1 overflow=1
K12A_CDC_MAILBOX_PASS
K12A_PASS
```

正向cocotb共4项测试全部通过：

- `valid_must_hold_until_accept`：valid和payload跨不同时钟保持稳定，直到accept；
- `payload_is_atomic_and_busy_command_is_reported`：源payload改变和忙时重复请求不撕裂；
- `illegal_speed_is_transferred_for_controller_rejection`：`2'b11`原子传输到下游，留给
  Recovery控制器拒绝，不由mailbox伪造PHY动作；
- 生产模块下的负向测试入口不产生误报。

Checker自测使用故意单拍valid的bad stub，实际产生失败并写出：

```text
K12A_NEGATIVE_CHECKER_OBSERVED valid_hold
```

随后Make规则确认失败被捕获，输出`K12_CHECKER_SELFTEST_PASS`。

## 3. K11兼容性复核

本次新增模块未接入K11生产顶层；K11默认路径复核结果：

```text
make k11b2-lint                 PASS
make k11b2-vcs-serial           K11B2_DLL_ACTIVE_PASS
                                K11B2_ENUM_PASS
                                K11B2_BAR_PASS
                                K11B2_VCS_PASS
                                K11B2_VCS_REAL_PHY_PASS
```

因此K11-PHASE-RELEASE-v1仍是有效回退点，K11无调试release bit不变。

## 4. 尚未通过的K12门

本记录不宣称以下功能完成：Recovery.RcvrLock/RcvrCfg/Speed/Idle、EQ Phase 0～3、
PHY done超时、对端拒绝、非法Preset/Coefficient、CDR失锁、Gen1回退、Recovery期间
TLP/DLLP静默和实板升速。下一步是实现K12-B Recovery.Speed骨架，并把mailbox接到
控制器的accept/reject/error边界。
