# K11-B2 真实PHY Gen1枚举、BAR与KU040实现阶段报告

日期：2026-08-10

状态：**基础Directed、修改后VCS与Vivado PASS；串行加固/实板待完成**

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

## 5. 未完成项

尚未完成：100组串行随机BAR/BE、坏LCRC、ACK丢失、PERST#恢复，以及KCU105实板
Gen1枚举、20次冷启动和100次重训。按阶段门规则，以上项目完成前K11-B2与K11整体
不标记最终冻结，也不进入K12 RTL。
