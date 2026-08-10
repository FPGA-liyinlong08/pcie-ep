# K11-B3 KCU105实板x1链路A/B验证报告

日期：2026-08-10

状态：**官方XDMA Gen3 x1对照PASS；自研Endpoint曾短暂达到L0/DLL Active并完成配置交互，Linux最终枚举FAIL，问题暂停归档**

## 1. 验证目的

此前用于板级对照的已有XDMA bitstream实际配置为x4，不能严格排除KCU105 x1通道、
J74设置或Root Port适配问题。因此重新使用Vivado 2021.2生成官方XDMA v4.1 Gen3 x1
Endpoint示例，并与自研K11 Gen1 x1 Endpoint在同一块KCU105、同一插槽和同一次接线
条件下执行A/B验证。

## 2. XDMA Gen3 x1对照工程

固定配置：

- 器件：`xcku040-ffva1156-2-e`；
- Vendor/Device：`10ee:9031`；
- 最大链路：Gen3 x1；
- PCIe REFCLK：100 MHz；
- GT：Quad 225，布局结果`GTHE3_CHANNEL_X0Y7/GTHE3_COMMON_X0Y1`；
- Vivado实现：WNS `+0.216 ns`，DRC 0 Error、0 Critical Warning。

生成和下载入口：

```bash
make xdma-x1-demo
make xdma-x1-hw-program
```

首次下载后保持KCU105供电并重启Linux Root Port。Linux结果：

```text
0000:01:00.0 Serial controller [0700]: Xilinx Corporation Device [10ee:9031]
LnkSta: Speed 8GT/s (ok), Width x1 (ok)
LnkSta2: EqualizationComplete+, EqualizationPhase1+
          EqualizationPhase2+, EqualizationPhase3+
Kernel driver in use: xdma
```

AER的Uncorrectable/Correctable状态全部为0；驱动成功创建`xdma0_control`、
`xdma0_h2c_0`和`xdma0_c2h_0`等设备节点。BAR0分配为`0x82800000`、大小64 KiB。

该结果证明以下板级条件成立：

- KCU105 PCIe Lane 0收发路径可用；
- 100 MHz REFCLK和PERST#可用；
- J74、金手指、插槽和Root Port能够建立严格的Gen3 x1链路；
- 自研Endpoint未枚举不能再归因于使用x4对照bitstream。

## 3. 自研K11 Gen1 x1对照结果

从Linux安全移除XDMA设备后，通过`make k11b2-hw-program`下载自研bitstream，保持
KCU105供电并再次重启Linux主机。Root Port `0000:00:01.0`结果：

```text
LnkSta: Speed 2.5GT/s (downgraded), Width x1 (downgraded)
        Train- SlotClk+ DLActive+
SltSta: PresDet+
```

但是总线上没有出现`1234:e001`。启动扫描和手工`/sys/bus/pci/rescan`结果相同。
Root Port AER未报告DLP、TLP、FCP、Completion Timeout、BadTLP、BadDLLP或RxErr。

## 4. 首轮结论与诊断门禁

自研Endpoint已经达到Gen1 x1、Presence Detect和Data Link Active，K03物理训练与K05
流控初始化在真实Intel Root Port上具有实板证据。失败范围收敛为配置请求数据路径：

`MAC RX framing -> DLL RX/LCRC/sequence -> TLP codec -> cfg request -> Completion TX`

K11仍不能冻结为实板PASS。下一步应生成带ILA的诊断bitstream，至少采集LTSSM状态、
DLL Active、RX TLP SOP/EOP、LCRC/sequence结果、配置请求握手、Completion TX握手和相关
错误计数；在获得采样证据前不修改协议RTL。

## 5. 两级ILA诊断实现

通过顶层参数`K11B2_ILA_DEBUG`条件化插入诊断逻辑。参数默认为0，正式K11-B2构建
不会保留调试网络或ILA；调试构建设置为1并产生独立的bit/ltx文件。

一级`u_ila_pipe`工作在`phy_pclk`域，采集：

- LTSSM状态、协商速率/宽度、`link_up`和`dll_active`；
- MAC RX/TX的valid、ready、SOP、EOP、DLLP/TLP类型和错误；
- DLL流控状态、sequence/replay状态、RX/TX/ACK/NAK及错误计数摘要；
- RX非DLLP TLP首个SOP触发信号。

二级`u_ila_core`工作在`phy_coreclk`域，采集：

- RX/TX 128-bit packet stream握手和包边界；
- CDC错误、TLP codec分类与Completion计数；
- 可切换的RX请求或TX Completion首拍原始128-bit数据、Keep/Error及握手；
- BAR0、MSE及配置空间状态；
- Core域首个RX TLP首拍握手触发信号。

两个ILA深度均为4096，触发位置为1024。构建和硬件操作入口为：

```bash
make k11b2-ila-lint
make k11b2-ila-vivado
make k11b2-ila-hw-capture-wait   # 保持Vivado连接，等待Root Port启动流量
```

调试bitstream允许存在小幅负时序，只用于定位问题，不作为K11功能或时序验收证据；
正式非ILA构建仍强制WNS和WHS均不小于0。原始采样写入
`fpga/kcu105/build_k11b2_ila/capture/`，生成CSV和Vivado ILA数据文件。

## 6. 相对Git基线`f31412f`完成的修复

### 6.1 配置空间允许Bus Number重分配

首轮ILA证明固件使用临时BDF `0a00`访问Endpoint，并且自研Endpoint能够正确接收配置
请求、生成Completion、通过LCRC/Sequence检查，Root Port也返回ACK。原实现首次命中后
锁定完整BDF，导致固件临时Bus Number切换到OS最终Bus Number时，后续配置请求被拒绝。

修复后规则为：

- 单Function Endpoint仍只接受Function 0；
- 首次命中后只锁定Device Number，不锁定Bus Number；
- 每个有效配置请求均使用当前Target BDF作为Completion的Completer ID；
- Bus Number变化时更新`captured_bdf`。

新增测试先在旧RTL上失败，再在修复后通过；`make k08`共6个用例全部通过，包括10万组
随机配置访问，K08实现WNS为`+1.636 ns`。

### 6.2 L0过滤RxElecIdle瞬态并接受对端Recovery

原L0状态在检测到任意单周期`phy_rxelecidle`后立即进入Recovery。standalone PHY在真实
链路中可能出现短瞬态，该行为会导致Endpoint单方面离开L0。

修复后：

- 连续8个`phy_pclk`采样到RxElecIdle才确认Electrical Idle；
- 单周期毛刺不再触发Recovery；
- 对端发送带当前Link/Lane号的TS1或TS2时，可主动发起正常Recovery。

新增`l0_filters_rxelecidle_glitch_and_accepts_partner_recovery`测试覆盖毛刺过滤和对端发起
Recovery两条路径。

### 6.3 Hot Reset期间正确回送TS1

原`HOT_RESET`状态错误地关闭Ordered Set发送、拉高TX Electrical Idle。修复后Endpoint
在Hot Reset保持期持续发送TS1，并设置`Training Control.Hot Reset=1`，同时不再主动进入
TX Electrical Idle。测试明确检查TX序列中出现Rate ID `0x02`、Training Control `0x01`。

修复后`make k03-verilator`共8个用例全部通过，覆盖100次随机训练和2000个随机Packet；
`make k11b2-lint`通过。

### 6.4 调试构建与硬件操作闭环

新增独立的正式/调试构建策略：

- 正式`k11b2-vivado`仍要求WNS/WHS不小于0；
- `k11b2-debug-finalize`可从合法的已布线DCP生成诊断bitstream，允许小幅负WNS；
- ILA构建和普通调试构建使用独立文件名，避免误当发布镜像；
- 新增JTAG probe/program、ILA program/arm/upload和即时采样入口；
- 新增`decode_k11b3_ila.py`，自动汇总LTSSM、DLL、TLP、配置请求和错误计数。

最新普通调试构建DRC为0 Error、0 Critical Warning，WNS为`-0.116 ns`；按调试策略已上板，
但不作为K11正式时序验收证据。最新双ILA构建DRC通过且WNS为`0.000 ns`。

## 7. 已取得的真实协议交互证据

多轮ILA抓取已经确认：

- Endpoint能够进入Gen1 x1 L0并完成DLL流控初始化；
- Root Port发出的首个TLP为Set Slot Power Limit Message with Data，当前范围不支持该消息，
  被计入unsupported，但没有形成malformed或CDC错误；
- 固件至少发出7个针对临时BDF `0a00`的CfgWr0/CfgRd0请求；
- Endpoint为7个请求全部生成Completion，Root Port为这些Completion全部返回ACK；
- Vendor/Device Completion数据正确为`1234:e001`；
- 另一轮即时采样记录到`cfg_count=52`、`cpl_count=52`，LCRC、Sequence、Replay和CDC错误
  均为0，之后链路回到Detect。

2026-08-10 21:39的最新RTL冷启动触发样本显示：触发时LTSSM为L0、`link_up=1`、
`dll_active=1`、FC状态为Active；首个非DLLP TLP已通过DLL，ACK已发送，LCRC/Sequence/
Buffer/FC/DLLP CRC错误均为0。该次触发窗口过早，只覆盖首个unsupported消息，未覆盖后续
配置扫描，因此不能据此判断最新Hot Reset修复后的最终掉线状态。

## 8. 暂停时的未解决问题

下载包含BDF、RxElecIdle和Hot Reset修复的最新普通调试镜像并冷启动后，Linux仍未保留
`1234:e001`。Root Port最终状态为：

```text
LnkSta: Speed 2.5GT/s (downgraded), Width x1 (downgraded)
        Train+ SlotClk+ DLActive-
```

因此已修复项均应保留，但K11仍不能冻结。当前最可能的剩余范围是固件配置扫描后发生的
Recovery/Hot Reset退出条件、训练序列细节或链路控制寄存器副作用，而不是板级lane、
REFCLK、PERST#、基础LCRC/ACK或最初的配置Completion路径。

问题在此暂停。恢复排查时应使用最新ILA镜像，以“配置请求或TX Completion”为触发条件
重新冷启动抓取，重点比较最后一个成功配置请求、Hot Reset状态、TX TS1 Training Control、
Recovery状态跳转及Root Port最后一个Ordered Set；不要先做无证据的协议RTL修改。

## 9. 暂停归档结论

- K02硬件基础通过：官方XDMA Gen3 x1证明lane、时钟、复位和插槽正常；
- K03只能判定“曾进入Gen1 x1 L0”，不能判定稳定训练验收通过；
- K05 DLL Active和K08配置Completion具有真实交互证据；
- Linux最终枚举和BAR访问尚未完成，K11保持未冻结；
- 调试阶段允许负WNS，正式发布阶段仍必须重新完成WNS/WHS不小于0的时序门禁。
