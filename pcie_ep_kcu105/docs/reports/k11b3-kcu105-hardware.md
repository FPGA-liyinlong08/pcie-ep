# K11-B3 KCU105实板x1链路A/B验证报告

日期：2026-08-11

状态：**官方XDMA Gen3 x1对照PASS；自研Endpoint的首次L0退出原因已由双ILA定点捕获，Linux最终枚举仍FAIL，协议RTL暂不修改**

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

两个ILA深度均为4096，K11-B3链路退出触发位置为3072。构建和硬件操作入口为：

```bash
make k11b2-ila-lint
make k11b2-ila-vivado
make k11b2-ila-hw-program-arm-linkdown
make k11b2-ila-hw-capture-linkdown-wait   # 重启Root Port后只等待已Arm的ILA
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
但不作为K11正式时序验收证据。最新双ILA构建DRC为0 Error、0 Critical Warning，WNS为`-0.042 ns`；该镜像仅用于定位。

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

问题在此暂停。恢复排查时应使用最新ILA镜像，以链路退出事件为触发条件重新冷启动抓取，
重点比较最后一个成功配置请求、Hot Reset状态、TX TS1 Training Control、Recovery状态跳转
及Root Port最后一个Ordered Set；不要先做无证据的协议RTL修改。

## 9. 暂停归档结论

- K02硬件基础通过：官方XDMA Gen3 x1证明lane、时钟、复位和插槽正常；
- K03只能判定“曾进入Gen1 x1 L0”，不能判定稳定训练验收通过；
- K05 DLL Active和K08配置Completion具有真实交互证据；
- Linux最终枚举和BAR访问尚未完成，K11保持未冻结；
- 调试阶段允许负WNS，正式发布阶段仍必须重新完成WNS/WHS不小于0的时序门禁。

## 10. K11-B3链路退出定点捕获结果（2026-08-11）

本轮先建立并验证了链路退出事件检测器：仅在已经观察到`link_up && dll_active`后，
第一次`!link_up || !dll_active`产生单周期脉冲；训练早期状态跳转不触发，PERST#后可重新
触发。Verilator结果为触发器2/2、跨域1/1通过；K03、K08回归也通过。

诊断镜像构建结果：合法布局布线完成，DRC为0 Error、0 Critical Warning，WNS为`-0.042 ns`
（仅用于调试）。双ILA均已Arm，随后执行一次Linux冷启动。原始采样文件为：

```text
fpga/kcu105/build_k11b2_ila/capture/20260811_110502_u_ila_pipe.csv
fpga/kcu105/build_k11b2_ila/capture/20260811_110502_u_ila_core.csv
```

按`phy_pclk`采样点排序的关键窗口如下：

| 采样点 | LTSSM | link/DLL | RxElecIdle | qualified | TS1/TS2 | HotReset/forceRecovery |
|---:|---|---|---:|---:|---|---|
| 3055–3062 | L0 (`0x0a`) | 1/1 | 0 | 0 | 0/0 | 0/0 |
| 3063–3069 | L0 (`0x0a`) | 1/1 | 1 | 0 | 0/0 | 0/0 |
| 3070 | L0 (`0x0a`) | 1/1 | 1 | 1 | 0/0 | 0/0 |
| 3071 | Recovery.RcvrLock (`0x0b`) | 0/1 | 1 | 1 | 0/0 | 0/0 |
| 3072 | Recovery.RcvrLock (`0x0b`) | 0/0 | 1 | 0 | 0/0 | 0/0 |

`link_loss_trigger`在PIPE域和Core域均为采样点3072，说明跨域事件检测路径有效。触发前
没有观测到TS1/TS2、Hot Reset或`force_recovery`，而`rxelecidle`连续7个采样后
`rxelecidle_qualified`置位，随后LTSSM从L0进入Recovery.RcvrLock。这是本轮能够判定的
直接退出原因：**qualified RxElecIdle，而非配置请求、Hot Reset或DLL LCRC/Sequence错误**。

同时采样摘要为：`cfg_count=52`、`cpl_count=52`、`bdf=0a00`、LCRC/Sequence/Replay/CDC
错误为0；Core触发窗口内没有新的TLP握手。主机冷启动后仅发现Root Port `00:01.0`，没有
`1234:e001` Endpoint，和“链路退出后未完成枚举”的现象一致。

当前证据仍不能区分两种更底层的来源：

1. Root Port确实让链路进入持续Electrical Idle；
2. standalone PHY在仍有RX数据活动时错误地报告`rxelecidle`。

因此本轮不修改协议功能RTL。Core ILA在4096深度、3072触发位置的窗口内没有保留最后一个
配置请求和Completion的原始128-bit首拍，只保留了计数器；这属于当前探针时间窗口的缺口，
不能声称已经取得最后一包的payload证据。

为仿真闭环，K03新增定向用例`l0_enters_recovery_after_sustained_rxelecidle`：在L0保持
`phy_rxelecidle=1`连续7拍仍停留L0，第8拍进入Recovery.RcvrLock，且Hot Reset不置位。
该用例把实板观察到的输入序列固化为可复现激励。下一轮若继续排查，应优先对比同一窗口的
PHY原始`RxData/RxValid/RxElecIdle`行为，或调整Core域采样策略以捕获最后一笔配置TLP；在
获得区分Root Port与PHY来源的证据前，不应改变LTSSM的Electrical Idle判定规则。

## 11. K11-B3.1 RxElecIdle/RxValid矛盾复核（2026-08-11）

为区分“Root Port真实进入Electrical Idle”和“standalone PHY状态输出不一致”，在新的诊断
bitstream中加入仅调试用的`dbg_phy_rxidle_conflict`探针。它只在已经看到
`link_up && dll_active`、且当前仍为`link_up`时置位，条件为：

```text
phy_rxelecidle && phy_rxvalid
```

该信号不参与LTSSM、DLL或TLP功能。调试bitstream完成合法布局布线，DRC为0 Error、0
Critical Warning，WNS为`-0.263 ns`；负时序只按本轮ILA诊断政策允许，不作为发布镜像验收。

本次使用新镜像执行JTAG下载、双ILA Arm、Linux冷启动和等待式采样。原始文件为：

```text
fpga/kcu105/build_k11b2_ila/capture/20260811_124436_u_ila_pipe.csv
fpga/kcu105/build_k11b2_ila/capture/20260811_124436_u_ila_core.csv
```

关键窗口（PIPE域）如下：

| 采样点 | LTSSM | link/DLL | RxElecIdle | RxValid | RxData | RxDataK | qualified | conflict |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 3071 | L0 (`0x0a`) | 1/1 | 0 | 1 | `0x00004a4a` | `0x0` | 0 | 0 |
| 3072–3079 | L0 (`0x0a`) | 1/1 | 1 | 1 | `0x000000bc`、`0x00002a00`、`0x0000000e`、`0x00004a4a`… | `0x1`、`0x0`… | 3079置1 | 1 |
| 3080 | Recovery.RcvrLock (`0x0b`) | 0/1 | 1 | 1 | `0x00007cbc` | `0x3` | 1 | 0 |
| 3081 | Recovery.RcvrLock (`0x0b`) | 0/0 | 1 | 1 | `0x00007c7c` | `0x3` | 0 | link_loss脉冲 |

因此本次实板证据已经明确：**在LTSSM离开L0之前，standalone PHY同时报告
`RxElecIdle=1`和`RxValid=1`，且`RxData/RxDataK`仍在变化；8个采样周期后才进入
Recovery.RcvrLock。** 退出前没有TS1/TS2、Hot Reset、`force_recovery`或DLL错误；计数器仍为
LCRC=0、Sequence=0、Replay=0、CDC=0。该结果重复并加强了上一轮的判断：直接触发条件是
qualified RxElecIdle，但其更底层来源至少存在PHY/PIPE状态语义不一致，不能把该信号直接
等价为“线路已无有效接收数据”。

冷启动后的主机证据仍为仅发现Root Port `00:01.0`，没有`1234:e001` Endpoint；Root Port
启动日志没有新增AER报错。旧的首次未门控探针采样不作为证据，本节只采用上述门控后的有效
采样。

下一步闭环输入序列已确定为：在L0/DLL Active下保持`RxValid=1`、`RxData`持续变化，同时
将`RxElecIdle`连续置1至少8个`phy_pclk`周期；期望当前RTL在第8个周期进入Recovery.RcvrLock。
该序列已由K03 directed test覆盖。**本轮不修改协议功能RTL**；下一次修改前应先在PHY
行为模型中复现该矛盾，并单独验证standalone PHY文档对`RxElecIdle`和`RxValid`的优先级定义。

## 12. K11-B3.2 RxValid门控修复与复核（2026-08-11）

在完成B3.1实板取证后，按闭环计划修改Electrical Idle滤波条件：

```text
rxelecidle_sample = phy_rxelecidle && !phy_rxvalid
```

只有`rxelecidle_sample`连续8个PIPE周期才允许L0进入Recovery；L0中
`RxElecIdle=1 && RxValid=1`的重叠窗口会清零滤波计数。训练阶段的Ordered Set、Gen1
`RxValid`采样和CFG_IDLE检测逻辑未改动。

软件仿真结果：

- K03：9/9通过，包含“RxElecIdle/RxValid重叠不退出”和“RxValid撤销后8拍退出”两条路径；
- K05：5/5通过，随机信用事件10000组；
- K06：5/5核心用例及2/2仲裁用例通过，Sequence回绕10000包；
- K08：单元6/6通过，随机配置事务100000组；K07+K08 TLP集成2/2通过；
- K09/K10集成回归通过；K11-B3触发器2/2、CDC 1/1通过。

修复后的ILA镜像已重新实现：DRC为0 Error、0 Critical Warning，WNS=`-0.041 ns`，仅按
调试构建政策允许负时序。JTAG下载并再次Linux冷启动后，主机仍未枚举`1234:e001`。本次
即时ILA采样为：

```text
fpga/kcu105/build_k11b2_ila/capture/20260811_131201_u_ila_pipe.csv
fpga/kcu105/build_k11b2_ila/capture/20260811_131201_u_ila_core.csv
```

该样本没有触发`link_loss`，但PIPE域4096个采样全部停在`CFG_COMPLETE (0x08)`，
`link_up=0`、`DLL Active=0`、`RxElecIdle=1`、`RxValid=0`；DLL摘要出现1次FC错误和1次
malformed DLLP。Core域仍记录`cfg_count=52`、`cpl_count=52`，说明主机配置交互曾经发生，
但本次启动没有形成可保持的L0。Root Port执行Secondary Bus Reset后仍未出现Endpoint，
故本轮不能宣布枚举修复成功，也不能把`CFG_COMPLETE`样本误判为过滤逻辑已验证通过。

当前判定：B3.1已明确原始退出原因，B3.2已完成最小门控修复及仿真闭环，但实板仍有
“CFG_COMPLETE→CFG_IDLE/L0”训练或DLL错误路径未解决。下一步应针对CFG_COMPLETE之后的
TS2/Idle接收、PHY `RxValid`语义和FC/malformed错误建立新的定点采样；在获得该证据前不再
增加新的协议功能修改。

## 14. K11-B3.4 冷启动与XDMA物理链路对照（2026-08-11）

恢复自研调试镜像并布防 `Detect.Active` ILA 后，执行了一次真实Linux冷启动。冷启动后的
Root Port仍为 `PMCSR=0x0103 (D3hot)`，未枚举端点；ILA却再次捕获到完全相同的训练起点：

```text
DETECT_ACTIVE + RxStatus=3/phystatus=1
    -> POLLING_ACTIVE
    -> 端点连续发送TS1，Root Port方向仍为RxValid=0/RxElecIdle=1
```

有效采样：

```text
fpga/kcu105/build_k11b2_ila/capture/20260811_145009_u_ila_pipe.csv
fpga/kcu105/build_k11b2_ila/capture/20260811_145009_u_ila_core.csv
```

该次冷启动窗口中端点未收到任何TS1/TS2，故 `cfg_count/cpl_count=0`，不能进入配置空间
分析；Core ILA的单个unsupported计数属于无有效TLP时的残留采样，不作为协议错误结论。

历史记录已经确认：**XDMA Gen3 x1 曾在同一KCU105、同一主机和同一插槽上完成硬件
验证**，因此主机、插槽、J74 x1配置、参考时钟和PCIe物理通道不再作为本项目的待验证
假设，后续不重复下载XDMA做物理链路验证。

本轮曾临时下载本地XDMA成品做物理对照，但两个候选工程（包括目录名为`x1`的工程）实际
都包含/使用XDMA x4实例，Root Port报告：

```text
01:00.0 Xilinx 10ee:8034
LnkSta: Speed 2.5GT/s, Width x4 (ok)
```

该次对照不增加任何新的有效结论，也**不能替代已有的XDMA Gen3 x1历史验收**；对照完成
后已恢复自研K11调试镜像。

当前结论进一步收敛为：

1. 端点Receiver Detect、PHY时钟/复位释放、POLLING_ACTIVE状态和TS1内部发送均有实板证据；
2. 冷启动、Secondary Bus Reset、Root Port D0和软件Retrain均未让Root Port向端点返回TS1；
3. 物理插槽和主机链路已有XDMA Gen3 x1历史验收，不再重复验证；
4. 下一步不应继续修改DLL/TLP/配置空间，而应制作一个最小PHY-TX诊断镜像或在现有镜像
   增加GT TX reset-done、TX buffer status、TX electrical-idle和Root Port热插拔/PERST#电平
   的探针，优先确认“端点TS1是否真正从GTHE3发出”。

## 13. K11-B3.3 Detect/Polling 与主机电源状态复核（2026-08-11）

为避免把短即时窗口误判为LTSSM卡死，增加了仅调试用的 `program-arm-detect-active`
ILA入口，匹配 `dbg_pipe_top[32:27] = DETECT_ACTIVE`，不改变正式RTL和ILA探针位宽。
该入口的下载、布防和硬件上传均成功；调试构建仍为0 Error、0 Critical Warning，负WNS只作
诊断记录。

有效采样文件：

```text
fpga/kcu105/build_k11b2_ila/capture/20260811_142846_u_ila_pipe.csv
fpga/kcu105/build_k11b2_ila/capture/20260811_143319_u_ila_pipe.csv
fpga/kcu105/build_k11b2_ila/capture/20260811_143727_u_ila_pipe.csv
```

其中 `20260811_142846` 的关键顺序为：

| 采样点 | LTSSM | PHY状态 | TX行为 | RX行为 |
|---:|---|---|---|---|
| 3072 | DETECT_ACTIVE (`0x01`) | `RxStatus=0` | 电气空闲 | `RxValid=0, RxElecIdle=1` |
| 3153 | DETECT_ACTIVE (`0x01`) | `RxStatus=3, phystatus=1` | 尚未发TS1 | `RxValid=0, RxElecIdle=1` |
| 3154 | POLLING_ACTIVE (`0x02`) | Receiver Detect完成 | 开始发送TS1 | `RxValid=0, RxElecIdle=1` |
| 3155以后 | POLLING_ACTIVE (`0x02`) | 正常 | 连续TS1：`F7BC/F7FF/0002/4A4A...`，`datak=3/1/0/0` | 没有收到TS1/TS2 |

该结果证明端点的Receiver Detect、`DETECT_ACTIVE→POLLING_ACTIVE`状态转移和Gen1 TS1
发送路径均工作；在完整4096点窗口中对端一直没有返回有效训练序列，因此不能再把当前
现象归因于端点未发送TS1。

主机Root Port `00:01.0`的配置状态同时读取为：

```text
PMCSR = 0x0103  -> D3hot
LnkSta = 0x5811 -> Speed 2.5GT/s, Width x1, Train+, DLActive-
```

随后已在不修改Endpoint协议RTL的前提下执行：

1. PMCSR低两位写0，恢复Root Port到D0（读回`0x0100`）；
2. Secondary Bus Reset置位/清除；
3. Link Control Retrain置位并轮询32次。

本轮Root Port仍保持 `Train+ / DLActive-`，Linux仍未出现 `1234:e001`；D0恢复没有立即
产生对端TS1。三次采样（`142846`、`143319`、`143727`）均保持同一端点行为：Receiver
Detect成功、端点发TS1、RX没有TS1。`143319`和`143727`分别是在Secondary Bus Reset以及
D0+Retrain后采集，说明简单软件复位不足以恢复主机训练发送状态。

本轮结论：问题已从Endpoint LTSSM/TS1发送侧进一步收敛到**主机Root Port训练状态或
板级PERST#/链路电源状态未真正复位**；尚无证据要求修改协议功能RTL。下一步应在一次真实
冷启动或物理断电重新上电后，在端点ILA布防状态下采集Root Port由Detect到Polling的首次
训练；若冷启动仍没有Root Port TS1，则转向KCU105插槽、J74 x1配置、PERST#电平和参考时钟
链路的板级验证。

## 11. K11-B4 PHY TX边界诊断镜像（2026-08-11）

本阶段不重复验证板卡物理链路。此前同一块KCU105、同一插槽和同一Lane已使用官方
XDMA Gen3 x1镜像完成硬件验证，证明REFCLK、PERST#、J74 x1、金手指、Root Port和
Lane 0物理收发路径均可工作。本阶段探针只验证自研RTL与standalone `pcie_phy`的
集成边界。

新增PIPE域Probe6（低位到高位）如下：

| 位 | 信号 | 诊断目的 |
|---:|---|---|
| 0 | PERST#同步采样 | 确认本次训练复位窗口 |
| 1 | `pipe_rst_n` | 确认PHY接口域已释放复位 |
| 2 | `phy_txdata_valid` | 确认MAC向PHY提交有效数据 |
| 3 | `phy_txelecidle` | 确认MAC是否要求电气空闲 |
| 4 | GT `txresetdone` | 排除GT TX复位未完成 |
| 5 | GT `gtpowergood` | 确认GT电源状态 |
| 6 | GT `qpll1lock` | 确认发送PLL锁定 |
| 7 | GT `pciesynctxsyncdone` | 确认PCIe TX同步完成 |
| 8 | GT `txelecidle_in` | 观察PHY送入GT的电气空闲控制 |
| 9 | GT `pcierategen3` | 观察PHY速率控制状态 |

诊断构建结果：

- `K11B3_ILA_IMPL_PASS`；器件`xcku040-ffva1156-2-e`；GT位置
  `GTHE3_CHANNEL_X0Y7/GTHE3_COMMON_X0Y1`；无PCIe Hard Block；
- DRC：0 Error、0 Critical Warning；CDC无Critical路径，仅保留ILA/异步复位相关
  Warning；
- WNS=`0.000 ns`（调试镜像，允许负时序；本次物理优化后为零）；
- bitstream：`fpga/kcu105/build_k11b2_ila/impl/k11b2_gen1_endpoint_ila.bit`；
- 双ILA已成功下载并Arm，PIPE触发器为`DETECT_ACTIVE`，Core域使用TLP触发器对齐。

这些探针不是对Xilinx PHY IP功能或KCU105物理通道的重新认证，而是区分以下四种集成
故障：GT TX reset-done未完成、PHY复位/电气空闲控制错误、RTL虽产生TS1但PHY未接受，
以及GT已离开空闲而问题应转移到Root Port训练接收侧。仅靠PHY接口侧采样不能证明串行
引脚上已经出现有效波形；如仍需确认引脚活动，应使用GT近端环回或示波器/协议分析仪。

当前硬件动作：ILA已Arm，等待一次主机冷启动产生`PERST#`训练窗口。远端主机可连接，
但无密码方式的`sudo reboot`被拒绝；需要人工执行冷启动后再运行：

```bash
make -C /home/wx/Documents/PCIe/pcie_ep_kcu105 k11b2-ila-hw-capture-wait
```

采样后重点检查Probe6中`txresetdone/gtpowergood/qpll1lock/pciesynctxsyncdone`与
`phy_txdata_valid/txelecidle`的先后关系，并与TS1 Ordered Set窗口对齐。

### 11.1 远端测试主机连接记录

- 主机：`192.168.11.126`；账户：`wx`；主机名：`wx-ubuntu`；
- 已确认免密SSH可用（`BatchMode=yes`）；后续冷启动、日志采集和PCIe状态读取可自动执行；
- 不在工程、脚本或报告中保存账户密码。
