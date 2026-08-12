# K11-PHASE-RELEASE-v1 阶段总结

日期：2026-08-13
状态：**PASS / K11阶段性release，可进入K12**

## 1. Release 边界

本release冻结KCU105上的Gen1 x1 Endpoint基线：standalone PHY、自研LTSSM/MAC、
DLL/FC/Replay、TLP/配置空间、4 KiB BAR0和Demo AXI4-Lite Slave已贯通。Linux可以
枚举`1234:e001`，并通过真实MMIO读取签名和写读scratch。

这是进入K12升速与Equalization开发的稳定基线，不是K14最终量产发布。以下项目继续
保留到K14：严格断电意义的20次cold boot、100次PERST#/重训、长时MMIO压力、最终
CDC/DRC/时序复签以及偶发错误的统计门。

## 2. 冻结产物

Release bit（构建目录按`.gitignore`管理，可由脚本重建）：

```text
fpga/kcu105/build_g12_ordered_set_release/impl/k11b2_gen1_endpoint.bit
SHA256=026b92b3d2c8586cc5e7809b3c8a0f4d2ff97349e8ea09ff803a9f2899117628
K11B2_IMPL_PASS
ILA_DEBUG=0
WNS=+0.019 ns
DRC=0 errors
```

构建时使用：

```text
G9_WAIT_REMOTE_DETECT=1
G12_ORDERED_SET=1
K11B2_ILA_DEBUG=0
```

`G12_ORDERED_SET`用于选择独立release构建目录；G12-B边界修复本身已进入生产RTL。
G9等待参数保留当前实板验证基线，ILA和所有条件`mark_debug`逻辑均被裁掉。Hardware
Manager烧写后明确报告没有supported debug core。

调试版在本机保留于：

```text
fpga/kcu105/archive/g12_debug_20260812_203305/
debug bit SHA256=c591953399c9ceb1ab33b7676a082bd258769ab107244959162a0fdb368790d7
debug ltx SHA256=79e3f09464b69e3a230c9550b47017495d38bfd01c439b4763f95acfc58d115d
```

大型bit/LTX/CSV不提交Git；Git保存可重建脚本、SHA256、结论和关键采样路径。

## 3. 从失败到release的修复过程

### 3.1 K11离线和真PHY基础闭环

K11-A先在MAC Packet边界以上连接K04～K10生产RTL，完成双向CDC、DLL Active、
配置空间、BAR和Hot Reset离线集成。K11-B随后使用Xilinx真实PHY模型和Root Port串行
环境，完成InitFC、枚举、BAR、随机MMIO、坏LCRC/NAK、ACK丢失/Replay及PERST恢复。

### 3.2 G1：Receiver Detect后的P1→P0握手

接口审计发现Detect成功后不能立即开始训练。修复加入独立`PHY_POWERUP`阶段：先请求
P0，等待第二次`PhyStatus`确认，再发送TS1。定向测试、K03回归、VCS和实板ILA均证明
修复生效。它是明确缺陷，但不是当时无法枚举的唯一原因。

### 3.3 G2～G8：排除PHY/GT伪根因

Gen1/CPLL A/B、GT原始RX、静态属性、动态RX控制、XDMA参考、热接管、Detect.Quiet
P0以及提前Detect等试验排除了Lane/引脚/极性/REFCLK、GT RX复位、P0/P1、CDR Hold、
8b/10b、PLL选择和单纯Detect延迟等因素。XDMA先建链后Standalone热接管能进入L0，
说明自研训练、配置和事务路径具备工作能力，问题集中到首次双向启动时序。

这些A/B大多是诊断实验，没有全部进入release RTL；保留的是被独立证明必要的修复。

### 3.4 G9：等待Root Port首次活动

增加`WAIT_REMOTE_DETECT`启动策略，避免Endpoint过早推进而错过Root Port第一次双向
活动窗口。G9实板证明RX Electrical Idle会撤销，Endpoint可推进至Configuration。
该等待参数保留在本release中，并与ILA开关解耦，使正式bit保留功能而移除调试资源。

### 3.5 G10/G11：Configuration和RX链路取证

G10证明部分reboot会成功枚举，同时暴露Endpoint停在`CFG_COMPLETE`时双方TS行为仍需
精确对齐。G11逐级观察GT/PHY、raw aligner、descrambler和Ordered Set parser，证明
接收数据链路和TS解析正常；问题继续收敛到本端发送Ordered Set的状态切换边界。

### 3.6 G12-A：确认Ordered Set被截断

G12-A加入TX mode、`word_index`、`active_word_index`和`os_tx_complete`观察。ILA显示
状态从`CFG_LANENUM_ACCEPT`切换到`CFG_COMPLETE`时，旧逻辑已经开始下一组TS1：

```text
state 7: word=7, complete=1
state 7: word=0, complete=0
state 7: word=1, complete=0
state 8: word=2, complete=0
```

因此TS1被中途切换为TS2，违反完整Ordered Set边界。

### 3.7 G12-B：边界修复

加入`cfg_complete_pending`。接收数量和最小时序条件满足后只置pending，只有当前TS1
出现`os_tx_complete=1`才进入`CFG_COMPLETE`。修复后的硬件采样为：

```text
sample 382: state=7, TS1, word=6, complete=0
sample 383: state=7, TS1, word=7, complete=1
sample 384: state=8, TS2, word=0, complete=0
```

状态切换和TS1→TS2模式切换现在发生在完整Ordered Set之间。

### 3.8 BAR偶发现象和复核

曾出现一次枚举成功后，BAR前几次读正常、一次Posted Write后后续读返回
`0xffffffff`，Root Port同时记录可纠正Replay Rollover。执行remove/rescan后恢复。
但后续不做rescan的reboot无法重复该失败：3轮reboot、15次BAR mmap全部通过，另有
两次独立reboot BAR通过。因此把它记录为未复现的偶发事件，不据此修改DLL功能逻辑。
调试脚本保留`arm-rx-tlp`入口，若再现，应原地抓取，不先remove/rescan。

## 4. Release 验收证据

- Lint：无ILA生产配置通过。
- VCS真实PHY串行回归：`K11B2_DLL_ACTIVE_PASS`、`K11B2_ENUM_PASS`、
  `K11B2_BAR_PASS`、`K11B2_VCS_REAL_PHY_PASS`。
- 历史K11-B2压力：100组随机BAR/BE、坏LCRC、ACK丢失、PERST恢复通过。
- Release实现：WNS `+0.019 ns`，DRC 0 Error，无ILA/debug hub。
- Release实板：reboot后`01:00.0 1234:e001`，BAR0=`0x82800000`。
- Release实板MMIO：连续5次`pci_bar_mmap_test`通过，signature=`50434945`，
  scratch=`a5c37e19`，UR/CA/AXI错误计数均为0。
- 调试版额外压力：3轮reboot、15次BAR mmap全部通过，当前启动周期无新增AER。

## 5. 已知限制

- 当前release只宣告Gen1 x1；`phy_rate`仍为Gen1，Rate ID只宣告2.5 GT/s。
- 未执行严格断电20次cold boot和100次PERST/重训最终门。
- BAR偶发失效只有单次历史样本，当前无法复现，保留为K14观察项。
- 调试bit存在大量ILA信号和诊断性负WNS，不是release；正式bit必须使用无ILA版本。

## 6. 冻结决定

K11的核心进入条件已经满足：真实PHY Gen1 L0、Linux枚举、配置空间、DLL、BAR、
正式时序和无调试实板bit均闭环。冻结为`K11-PHASE-RELEASE-v1`，允许开始K12。

详细原始报告见`k11-g1-*`、`k11-g2-*`、`k11-g3-g4-*`及`k11b5`～`k11b9`。
