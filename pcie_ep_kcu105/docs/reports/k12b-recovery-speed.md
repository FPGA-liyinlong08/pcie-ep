# K12-B Recovery.Speed 执行记录

日期：2026-08-13

状态：**K12-B Recovery.Speed 骨架 PASS；尚未接入生产LTSSM和实板**

## 1. 实现边界

新增独立控制器：

```text
rtl/phy/pcie_recovery_speed_ctrl.sv
```

控制器只处理速率阶段，不实现K12-C Equalization Phase 0～3，也不解析Ordered Set。
状态序列为：

```text
L0 -> QUIESCE -> SPEED_WAIT -> RECOVERY_IDLE -> L0
                         \-> FALLBACK_WAIT -> FALLBACK_IDLE -> L0
```

正常切速流程先拉高`traffic_quiesce`，再请求`phy_txelecidle`并驱动目标
`phy_rate`，等待`phy_phystatus`，最后等待对端确认。超时、拒绝、CDR失锁或非法
目标不会留下半完成的高速状态，fallback路径恢复Gen1。

## 2. 验证结果

```text
make k12b
K12_CHECKER_SELFTEST_PASS speed_done_order=1 fallback=1
K12B_RECOVERY_SPEED_PASS
K12B_PASS
```

正向5项全部通过：

- 正常Gen1→Gen3：PHY完成、对端确认后回到L0，协商速率为Gen3；
- PHY done超时：置sticky错误，进入Gen1 fallback并回到L0；
- 对端拒绝：置`peer_reject_sticky`，进入Gen1 fallback；
- 非法目标`2'b11`：命令被接收并记录错误，不驱动PHY、不quiesce；
- 负向Checker：故意跳过`SPEED_WAIT`的bad stub被检出。

测试默认将控制器32-cycle超时参数覆盖为4 cycles，以快速覆盖边界；生产默认参数
仍为32 cycles，待与真实PHY完成延迟共同冻结。

## 3. 与K11的关系

K12-B控制器目前是独立验证模块，没有接入`kcu105_pcie_ep_gen1_top`，因此没有生成
新的bit，也没有烧写远端设备。K11-PHASE-RELEASE-v1及其无调试bit保持不变，K11
真实PHY/枚举/BAR回归仍是后续接入时的回退门。

## 4. 未完成项

仍需完成：mailbox与控制器正式连接、Recovery.RcvrLock/RcvrCfg、完整Ordered Set
边界、EQ Phase 0～3、Preset/Coefficient合法性、PHY TX/RX EQ done、CDR失锁实链路
验证、DLL/TLP静默和K12开发bit实现。
