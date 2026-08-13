# K12-C Equalization Phase 0～3 执行记录

日期：2026-08-13

状态：**K12-C EQ独立控制器 PASS；尚未接入生产LTSSM和实板**

## 1. 实现边界

新增独立控制器：

```text
rtl/phy/pcie_equalization_ctrl.sv
```

状态严格按以下顺序推进：

```text
Phase 0 TX -> Phase 1 RX -> Phase 2 TX -> Phase 3 RX -> DONE
                                             \-> FAIL
```

每个PHY命令保持到对应`phy_txeq_done`或`phy_rxeq_done`；超时后撤销所有EQ控制
输出并进入FAIL。Preset按工程Gen3约束限制为0～9，Coefficient和对端Preset由
上游通过valid信号确认，未确认的参数不会驱动PHY。

## 2. 验证结果

```text
make k12c
K12_CHECKER_SELFTEST_PASS phase_order=1 eq_done_order=1
K12C_EQ_PHASES_PASS
K12C_PASS
```

正向5项全部通过：

- Phase 0→1→2→3正常完成，命令和Preset/Coefficient保持正确；
- 非法Preset和非法Coefficient valid被拒绝，不产生PHY EQ命令；
- TX EQ done超时进入FAIL并清除命令；
- RX EQ done超时进入FAIL并清除命令；
- 负向Checker成功检出跳过Phase 0/1的bad stub。

仿真将默认32-cycle EQ timeout覆盖为4 cycles以快速覆盖边界；生产默认值仍为32，
待行为PHY完成延迟和真实PHY串行测试共同冻结。

## 3. 与K11/K12-B的关系

K12-C控制器目前未接入K12-B，也未接入`kcu105_pcie_ep_gen1_top`，因此没有生成新bit、
烧写远端设备或改变K11 release。K11-PHASE-RELEASE-v1仍是当前硬件回退点。

## 4. 未完成项

仍需完成mailbox→Recovery.Speed→EQ的正式接线、Recovery.RcvrLock/RcvrCfg、完整
Ordered Set边界、TLP/DLLP静默、CDR失锁联动、行为PHY Partner、VCS真实PHY Gen1→Gen3、
Vivado CDC/实现和K12开发bit实板验证。
