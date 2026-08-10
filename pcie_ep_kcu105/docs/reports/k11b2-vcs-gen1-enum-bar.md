# K11-B2 真实PHY Gen1枚举、BAR与KU040实现阶段报告

日期：2026-08-10

状态：**全部非实板验证 PASS；KCU105实板验收延期**

## 1. 已完成内容

- 新增生产顶层`kcu105_pcie_ep_gen1_top`，连接standalone PHY、K03 MAC、K06 DLL、
  K11-A CDC、K07 TLP、K08配置空间、K09 BAR和K10 Demo；
- 新增板级封装`kcu105_pcie_ep_gen1_board_top`，仅导出已约束的KCU105管脚；
- K03-only负向Stub能进入L0但不能DLL Active，Checker正确输出
  `K11B2_CHECKER_SELFTEST_PASS`；
- 真实Xilinx PHY/GTHE3与UltraScale Root Port串行仿真完成InitFC、配置枚举和BAR访问；
- 将K11-A可综合顶层移入`rtl/ep`，仿真、VCS和Vivado共用同一生产RTL；
- K08修正Function 0匹配：允许Root Port分配非零Device Number，并捕获完整BDF。

## 2. 真实PHY VCS基础结果

修正K08 BDF匹配后，VCS已得到以下固定标记：

```text
K11B2_DLL_ACTIVE_PASS
K11B2_ENUM_PASS bdf=01a0 bar0=80000000
K11B2_BAR_PASS signature=50434945 scratch=a5c37e19
K11B2_VCS_PASS
K11B2_VCS_REAL_PHY_PASS
```

其中BDF为`01:14.0`，说明测试没有假定Device Number必须为0。BAR0全1探测返回
`fffff000`，随后分配`80000000`并打开MSE；BAR0+0读取签名`50434945`，BAR0+0x40
写读`a5c37e19`一致。

## 3. 时序问题与修正

第一次完整实现虽能完成布局布线和DRC，但250 MHz最差路径为TX Packet FIFO BRAM
读口，经Packet/Metadata配对逻辑，直接驱动DLL Replay RAM写使能：

```text
WNS=-0.798 ns
TNS=-674.727 ns
failing endpoints=1835
```

在`pcie_tlp_async_bridge`的TX出口增加一拍弹性寄存器后，保持`valid/ready`、包顺序、
字节序及“仅EOP消费metadata”的契约不变。K11-A双向随机桥回归2/2通过，第二次完整
实现结果如下：

| 项目 | 结果 |
|---|---:|
| 器件/顶层 | `xcku040-ffva1156-2-e` / `kcu105_pcie_ep_gen1_board_top` |
| WNS/TNS | `+0.020 ns / 0.000 ns` |
| WHS/THS | `+0.014 ns / 0.000 ns` |
| GT Channel/Common | `GTHE3_CHANNEL_X0Y7` / `GTHE3_COMMON_X0Y1` |
| PCIe Hard Block | `0` |
| MAC/DLL/CFG/BAR/Demo层次 | 各`1` |
| Block RAM Tile | `7` |
| CDC | `CDC-3 Info=4`、`CDC-9 Info=5`，无Critical |
| DRC | 0 Error、0 Critical Warning |
| Bitstream | 生成成功（构建产物不提交Git） |

Vivado普通Warning ID固定为`Synth 8-3848/3917/6014/6779/7023/7071/7080/7129`
及无负路径查询产生的`Vivado 12-975`；运行脚本对集合做精确门禁，新增Warning失败。

## 4. 许可证问题复核与修改后VCS补签

隔离执行环境内重跑时，elaboration持续显示`VCSCompiler_Net`排队。非隔离环境查询
`27000@wx-linux`确认`lmgrd/snpslmd`均为UP，Compiler/Runtime/MX Runtime各99席且
0占用，证明原因不是席位耗尽，而是隔离网络不能访问本机许可证端口。

在可访问许可证服务的非隔离环境重新执行后，弹性级修改后的RTL得到：

```text
K11B2_DLL_ACTIVE_PASS ep_fc=3 rp_state=10
K11B2_ENUM_PASS bdf=01a0 bar0=80000000
K11B2_BAR_PASS signature=50434945 scratch=a5c37e19
K11B2_VCS_PASS
K11B2_VCS_REAL_PHY_PASS
```

仿真结束时间约153.764 us，CPU约13.72 s。修改前的旧日志不再用于当前RTL签核。

## 5. 真实PHY串行加固结果

执行入口：

```bash
LM_LICENSE_FILE=27000@wx-linux make k11b2-vcs-stress
```

该模式在基础枚举和BAR用例之后继续完成：

- 固定种子`1aceb00c`的100组Scratch随机地址、32-bit数据和非零Byte Enable，
  Scoreboard逐Byte维护期望值并逐事务读回；
- 在Endpoint LCRC判定状态注入一包坏LCRC，计数器增加为1、发送一次NAK，Root Port
  重放后原Memory Read仍返回正确签名；
- 屏蔽一条Completion ACK直至2048-cycle Replay Timer到期，确认Replay计数增加；
  由于Xilinx RP示例模型不会对重复Completion再次ACK，Partner补发先前丢失的合法累计
  ACK，确认Replay occupancy恢复为0且未进入fatal；
- 断言一次PERST#，双方重新训练到Gen1 x1、重新完成InitFC；随后重新读取Vendor/Device、
  配置BAR0和MSE并读取Demo签名。

固定通过标记如下：

```text
K11B2_RANDOM_MMIO_PASS transactions=100 seed=1aceb00c
K11B2_BAD_LCRC_PASS lcrc=1 nak=1
K11B2_ACK_LOSS_PASS replay=1 occupancy=0
K11B2_PERST_RECOVERY_PASS vendor=e0011234 signature=50434945
K11B2_STRESS_PASS
K11B2_VCS_PASS
K11B2_VCS_REAL_PHY_PASS
```

仿真结束时间约532.852 us，CPU约52.54 s；全过程`cdc_errors=0`，没有Replay fatal。
`make k11b2-lint`同步通过。本轮只修改测试平台、执行脚本和文档，没有改变生产RTL，
因此沿用第3节已经通过的Vivado实现结果。

## 6. 未完成项

非实板范围已经完成。尚未完成的只剩KCU105实板Gen1枚举、BAR访问、20次冷启动和
100次PERST#/重训，这些项目按用户要求继续延期。K11-B2可标记为“非实板冻结”，但
K11整体仍保留实板验收门，不能宣称最终完成。
