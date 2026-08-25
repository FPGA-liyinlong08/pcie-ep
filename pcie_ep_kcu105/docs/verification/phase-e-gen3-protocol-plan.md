# Phase E：Gen3协议与完整Endpoint计划

状态：**E0/E1软件门禁PASS；E1实板已看到有效PIPE/EIEOS/block lock/TS1，但首次建锁存在一次性malformed，尚未硬件签署；E2 RTL/仿真/实现PASS、待复测**

## 目标与入口

Phase D已证明Golden方式Gen1→Gen3 PHY切速可以稳定完成。本阶段从已签署的
Phase C canonical Gen1 release和Phase D PHY transaction出发，依次完成Gen3
Ordered Set、Recovery、Equalization、L0及Linux枚举/BAR压力。

生产边界继续保持：

`K03 LTSSM/MAC → pcie_phy_command_ctrl → K02 PHY wrapper`

K04～K10继续冻结；K13只保留为历史实验和反例，不恢复其raw command MUX。任何阶段
失败都回到SHA256为
`1489516e07a8d75b30992a1589805306d2b0e3f4a447bc3ec14e708f3605ee70`的
canonical Gen1 bitstream。

## E0：冻结Phase D接口

- 固定rate transaction的`valid/ready/done/result/abort`及Golden 2500拍gap；
- 固定`PHY_RATE`、PowerDown、TXEI、Detect Assist、CDR Hold的唯一owner；
- 归档D1～D4报告、ILA CSV哈希、实现参数和bitstream SHA256；
- 重跑ownership、K03、K11 serial/stress及Gen1 3×5实板门禁。

完成条件：Phase D commit可复现，Gen1默认路径不包含ILA且不启用Gen3。

## E1：Gen3 Ordered Set与128b/130b数据通路

1. 冻结32-bit PIPE Gen3 block接口、Sync Header、StartBlock和RxDataValid语义；
2. 完成EIEOS生成/识别、block lock、128b/130b扰码/解扰和TS block边界；
3. 对现有`pcie_gen3_os_tx/rx`逐字段审计，不从K13波形反推协议字段；
4. 建立Gen1/Gen3 parser互斥和切速拍边界断言，禁止在block lock前消费TS；
5. 使用独立partner模型、随机bit slip、错误Sync Header和EIEOS丢失注错。

完成条件：仿真中至少1000次随机切速均重新获得block lock，TS1/TS2逐字段与参考模型
一致，Gen1 Packet路径逐周期不变。

实板补充门禁（2026-08-26）：冻结K14切速成功后必须观察到`RxDataValid`、
`RxStartBlock`、Ordered-Set Sync Header、精确EIEOS、block lock和至少一个TS1/TS2，
且不得出现`lock_lost`或`malformed`。首轮有效trace已满足所有正向里程碑，但记录到
一次`malformed`，因此E1实板状态仍为FAIL；增强探针在稳定RcvrLock中观察约117秒
未能再次触发该脉冲，当前把问题限定为首次建锁窗口的一次性事件，未放宽验收条件。

## E2：Recovery.RcvrLock

软件与实现状态（2026-08-25）：PASS。生产LTSSM只在精确EIEOS建立block lock后消费
TS1，第8个字段匹配的TS1进入`Recovery.RcvrCfg`。失锁、malformed、提前TS2、字段
不匹配或timeout均回到既有`Recovery.Speed`语义授权点，由K14 owner执行Gen1
fallback；E2不直接驱动raw PHY命令。

- rate transaction成功后只进入Gen3 `Recovery.RcvrLock`；
- 明确EIEOS、block lock、TS1连续计数、timeout和回退条件；
- PERST、Hot Reset、CDR loss和malformed block必须确定性回到Gen1安全路径；
- ILA同时观察语义状态、raw rate最终条件、block lock和TS计数。

软件/实现门禁已满足；单独E2 debug build保持K14原`probe0=31`、`probe1=118`逐位
不变，并追加14-bit语义状态和8-bit PIPE状态。2026-08-25的E2 trace当时未看到
`RxDataValid/RxStartBlock/RxValid`；2026-08-26独立E1 hold trace已经证明同板切速后
可以出现有效PIPE block、EIEOS、block lock和TS1，因此“PIPE恒死”不再是当前结论。
E2连续20次门禁仍未执行、未通过；先关闭E1首次建锁`malformed`，再以原E2语义路径
复测，且不得修改K14 raw owner。

## E3：Recovery.RcvrCfg

- 实现Gen3 TS1/TS2的Link/Lane、Rate ID、Speed Change和Training Control交换；
- 明确RcvrLock→RcvrCfg→Equalization/Idle的唯一跳转条件；
- 覆盖partner拒绝、字段不匹配、乱序TS、EIEOS重入和timeout；
- 保持DLL/TLP traffic quiesce，禁止在Recovery期间泄漏Packet。

完成条件：真实Root Port双方稳定完成RcvrCfg，失败均能保存trace并安全回退Gen1。

## E4：Equalization Phase 0～3

1. 先冻结独立的语义EQ transaction，不向LTSSM暴露raw TXEQ/RXEQ管脚；
2. controller继续唯一驱动TXEQ/RXEQ control、preset和coefficient；
3. 依次实现Phase 0、1、2、3，每一阶段单独建立test/ILA门禁；
4. 覆盖preset合法性、coefficient边界、reject、timeout、repeat和fallback；
5. 不允许通过固定EQ Complete位或跳相位进入L0。

完成条件：同板连续20次四阶段完整通过，GT侧Done/Adapt结果与协议状态一一对应。

## E5：Gen3 L0与现有协议栈恢复

- 仅在EQ、block lock和Recovery.Idle全部完成后恢复16-bit Packet接口；
- 审计切速前后DLL sequence、ACK/NAK、Replay和Flow Control生命周期；
- 验证Gen3 L0下TLP/DLLP边界、LCRC、坏包注错及Recovery重入；
- K04～K10不得因Gen3接入改变接口或协议行为。

完成条件：VCS真实PHY环境完成DLL Active、枚举、BAR、随机MMIO、坏LCRC/NAK、ACK
丢失/Replay和PERST恢复，并证明Gen1回归无退化。

## E6：Linux Gen3 release签署

无ILA release必须满足DRC 0 Error、WNS/WHS非负、无debug hub，并记录所有generic、
工具版本和bitstream SHA256。KCU105验收顺序为：

1. 3轮Root Port reboot，每轮5次MMIO和AER=0；
2. `LnkSta=8.0 GT/s x1`、DLL Active、`1234:e001`、4 KiB BAR0；
3. 100次标准Retrain，成功率100%，每次检查rate/EQ状态和AER；
4. 10万次随机8/16/32-bit MMIO及坏LCRC/Replay注错；
5. Hot Reset、PERST、remove/rescan和长时运行；
6. 任一失败先保存现场/ILA，不先remove/rescan，不修改K04～K10绕过。

全部通过后才建立Gen3 canonical release；在此之前，Gen1 canonical release始终是生产
默认和恢复基线。
