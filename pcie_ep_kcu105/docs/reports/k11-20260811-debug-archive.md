# K11 实板链路问题排查归档（2026-08-11）

## 1. 当前结论

KCU105、PCIe Lane 0、J74 x1设置、100 MHz参考时钟、PERST#、金手指、主机插槽和
Root Port已经由**同一块板卡、同一台主机、同一插槽上的官方XDMA Gen3 x1工程**完成
过严格的硬件验证。该基线有效，后续不再通过重复下载XDMA、示波器测量或更换插槽来
重复证明板级物理通道。

自研Endpoint当前尚未完成K11实板验收。2026-08-11的排查已经证明自研镜像能够完成
Receiver Detect、释放PHY/GT复位并在PHY原生接口边界连续提交Gen1 TS1，但在最新冷启动
中没有收到Root Port返回的TS1/TS2，最终停留在`POLLING_ACTIVE`，Linux没有枚举出
`1234:e001`。

因此后续优先级应从“板级硬件是否正常”转向：

1. 自研LTSSM/MAC与standalone `pcie_phy`原生接口的契约是否完全匹配；
2. TS1内容、控制字符、有效周期和Ordered Set间隔是否符合该PHY接口要求；
3. PHY封装中的Rate、Powerdown、Electrical Idle、Receiver Detect和状态握手是否存在
   配置或时序误用；
4. 使用仿真或Xilinx示例设计进行接口级对照，形成可复现输入后再修改RTL。

## 2. 今日怀疑对象与排查结果

| 怀疑对象 | 验证方法与证据 | 当前判定 |
|---|---|---|
| KCU105 Lane 0、J74、金手指、主机插槽 | 官方XDMA Gen3 x1在同板、同机、同插槽达到8 GT/s x1，驱动和BAR正常 | **已排除** |
| PCIe 100 MHz REFCLK与板级PERST#可用性 | 官方XDMA通过；自研ILA也捕获到PERST#下降和释放 | **已排除板级失效** |
| Root Port不支持x1或该板卡 | 官方XDMA Gen3 x1正常 | **已排除** |
| GT未上电或PLL未锁定 | `gtpowergood=1`、`qpll1lock=1` | **已排除** |
| GT TX复位或同步未完成 | `txresetdone=1`、`pciesynctxsyncdone=1` | **已排除** |
| PHY一直要求TX Electrical Idle | TS1窗口中`phy_txelecidle=0`且GT `txelecidle_in=0` | **已排除** |
| PHY状态复位/PIPE复位卡死 | `phy_phystatus_rst`撤销后4个`phy_pclk`周期释放`pipe_rst_n` | **已排除** |
| PERST#低电平时Endpoint错误发送 | PERST#下降后立即清除TX valid并进入Electrical Idle，随后GT/QPLL复位 | **已排除** |
| Receiver Detect失败 | `RxStatus=3/phystatus=1`，LTSSM从Detect.Active进入Polling.Active | **已排除** |
| LTSSM没有请求发送TS1 | PHY边界捕获连续TS1字节和`phy_txdata_valid=1` | **已排除MAC未提交** |
| Root Port处于D3hot导致不训练 | 强制写入D0后仍无对端TS1 | **D3hot不是唯一原因** |
| Root Port Link Disable或Secondary Bus Reset残留 | `LnkCtl.Disabled=0`、`BridgeCtl.SecondaryReset=0` | **已排除静态控制位残留** |
| Root Port未执行软件Retrain | D0、Secondary Bus Reset和Retrain均已执行，状态仍为`Train+ / DLActive-` | **软件复位无效，不再重复** |
| AER、BadTLP、BadDLLP或Completion Timeout | Root Port相关状态均为0 | **未发现此类错误** |
| DLL/LCRC/Sequence/Replay导致最新启动失败 | 最新启动停在Polling.Active，尚未进入DLL；计数为0 | **不是本次直接原因** |
| 配置空间或BAR导致最新启动失败 | 最新启动没有TLP和配置请求 | **不是本次直接原因** |
| L0中RxElecIdle瞬态导致首次退出 | ILA捕获`RxElecIdle=1 && RxValid=1`持续8拍后退出；已增加RxValid门控并完成回归 | **原问题已定位并修复** |
| RxElecIdle修复即能完成枚举 | 修复后实板仍出现CFG_COMPLETE停留或新的Polling.Active失败 | **已否定** |
| standalone PHY接口集成或TS1实际编码/节拍 | 目前只证明MAC向PHY提交TS1和GT状态正常，尚未完成Xilinx接口级逐周期对照 | **仍是最高优先级** |

## 3. 今日取得的关键时序证据

### 3.1 首次L0退出

链路曾达到`L0 && DLL Active`。第一次退出前，PHY同时报告`RxElecIdle=1`和
`RxValid=1`，RX数据仍在变化；连续8个采样后LTSSM进入Recovery.RcvrLock。退出前没有
TS1/TS2、Hot Reset、DLL LCRC错误、Sequence错误或Replay错误。

针对该输入序列，LTSSM已改为只累计：

```text
rxelecidle_sample = phy_rxelecidle && !phy_rxvalid
```

相应directed test和K03/K05/K06/K08/K09/K10相关回归通过。但这只修复了已捕获的L0
误退出条件，没有解决当前的完整枚举问题。

### 3.2 PERST#与PHY复位

PERST#下降时序：

```text
PERST#↓ -> pipe_rst_n=0、TX valid=0、TX Electrical Idle=1
         -> txresetdone=0、qpll1lock=0
         -> pciesynctxsyncdone=0
```

PERST#释放后的PHY时序：

```text
PERST#↑
  -> pciesynctxsyncdone=1
  -> txresetdone=1、qpll1lock=1
  -> phy_phystatus_rst↓
  -> 4个phy_pclk后pipe_rst_n=1
```

当前没有发现复位极性、复位期间继续发送、PLL未锁定或PIPE复位不释放的问题。

### 3.3 Detect到Polling与TS1发送

多次冷启动和软件复位后的共同序列为：

```text
DETECT_ACTIVE
  -> Receiver Detect完成（RxStatus=3、phystatus=1）
  -> POLLING_ACTIVE
  -> Endpoint在PHY边界连续提交TS1并退出TX Electrical Idle
  -> Endpoint RX持续没有Root Port TS1/TS2
```

最新`D0 + Retrain`采样仍停留`POLLING_ACTIVE (0x02)`，`link_up=0`、
`dll_active=0`，没有DLLP、TLP、配置请求和Completion。

## 4. Root Port侧排查归档

冷启动后曾读到：

```text
PMCSR     = 0103    # D3hot
LnkCtl    = 0000    # Link Disable=0，Retrain=0
LnkSta    = 1811    # Gen1 x1，Train+，DLActive-
LnkCtl2   = 0001    # Target Link Speed=Gen1
BridgeCtl = 0012    # Secondary Bus Reset=0
```

随后已依次执行并读回：

- Root Port恢复D0；
- Secondary Bus Reset置位/清除；
- Link Control Retrain；
- Linux冷启动和PCIe rescan。

以上操作均没有让Root Port向Endpoint返回TS1，也没有枚举出`1234:e001`。这些动作不再
作为下一轮主要排查手段。Root Port本身、插槽和物理通道已有XDMA Gen3 x1成功基线，不能
仅依据自研镜像下的`Train+ / DLActive-`就判定Root Port硬件异常。

## 5. 已完成的软件与硬件验证

- K03、K05、K06、K08、K09、K10相关定向和回归测试通过；
- K11链路退出检测器及跨时钟单脉冲测试通过；
- ILA调试镜像完成合法布局布线，DRC为0 Error、0 Critical Warning；
- 调试阶段允许负WNS，最新一次诊断实现曾达到正WNS，但调试镜像不作为最终时序验收；
- 已捕获配置请求、Completion及Root Port ACK的早期成功交互；
- 已捕获L0首次退出、RxElecIdle/RxValid冲突、Detect/Polling、PERST#两边沿、PHY状态复位
  释放、GT TX reset-done/QPLL/TX同步和D0+Retrain结果。

## 6. 后续排查边界

### 6.1 不再重复的方向

- 不再下载XDMA来重复证明KCU105、插槽或x1物理通道；
- 不再优先使用示波器测量PERST#、REFCLK和板级TX波形；
- 不再重复执行D0、Secondary Bus Reset、Retrain或rescan期待偶然恢复；
- 在链路停留Polling.Active且没有TLP时，不修改DLL、TLP、配置空间或BAR功能；
- 不把调试镜像的时序结果当作K11最终验收结论。

### 6.2 下一轮最高优先级

1. 对照Xilinx standalone `pcie_phy`生成模板或示例设计，逐项核对TX/RX数据、DataK、
   Data Valid、Start Block、Sync Header、Rate、Powerdown、Electrical Idle和Receiver
   Detect端口的方向、有效条件和时序；
2. 在Verilator PHY Partner或VCS Xilinx模型中重放实板的
   `Detect -> Polling.Active -> 连续TS1`序列，逐周期检查TS1字符、Link/Lane字段、
   Training Control、Ordered Set长度和间隔；
3. 检查XCI固定配置、PHY wrapper和LTSSM/MAC三者之间是否存在Gen1数据宽度、DataK位宽、
   字节顺序或有效拍解释不一致；
4. 只有发现明确的接口差异并建立先失败的directed test后，才修改协议或PHY封装RTL；
5. 修复后只进行一次冷启动实板复核，以“Root Port返回TS1并进入下一LTSSM状态”为明确
   验收目标。

## 7. 证据索引

详细寄存器、ILA采样点、原始CSV路径和每次修改记录保留在：

- `docs/reports/k11b3-kcu105-hardware.md`；
- `fpga/kcu105/build_k11b2_ila/capture/`；
- `scripts/decode_k11b3_ila.py`。

本归档是后续排查的结论入口；详细报告中的“下一步测量板级PERST#/REFCLK/TX波形”等
历史建议均由本文件第6节取代。

## 8. G1执行更新（2026-08-11）

第6.2节的G1已执行并闭环软件门禁。审计发现：旧RTL在P1中完成Receiver
Detect后直接进入Polling.Active，没有等待P1→P0转换的独立`PhyStatus`。
修复后状态顺序为：

```text
Detect.Active → PHY.PowerUp(15) → Polling.Active
```

修复前的定向测试可稳定观察到Electrical Idle过早撤销；修复后K03全回归、
K02模型、Vivado OOC/集成布局布线，以及Xilinx PHY + Root Port联合仿真均通过。
联合仿真中实际观察到状态0→1→15→2，随后完成L0、枚举和BAR读写。

详细证据见`docs/reports/k11-g1-phy-contract-audit.md`。新比特流已完成实板
冷启动复核：状态0→1→15→2及两个独立`PhyStatus`完全符合修复后契约，
但Root Port仍未返回TS1/TS2，Linux未枚举`1234:e001`。因此G1修复不是原故障的
唯一根因，后续按出口条件转入G2。

## 9. G2执行更新（2026-08-11）

G2没有重复验证板级引脚或Lane映射，而是完成standalone PHY配置A/B：保留原
Gen3/QPLL1基线，新增独立的Gen1-only/CPLL诊断IP。诊断构建只实例化
`GTHE3_CHANNEL_X0Y7`，不实例化`GTHE3_COMMON`；完整Endpoint通过DRC、CDC和正式时序
门禁，WNS为`+0.019 ns`，并成功生成及下载bitstream。

主机冷启动后仍未枚举`1234:e001`，但Root Port稳定报告2.5 GT/s x1、
`Train+ / DLActive-`；Link Status寄存器连续5次均为`0x1811`，AER无RxErr、BadTLP或
BadDLLP。该结果排除了原Gen3/QPLL1过配置是链路失败的必要条件，也再次说明物理通道并非
完全无信号；失败范围收敛到Polling/Configuration训练及standalone PHY RX到MAC的接收
解码路径。详细证据见`docs/reports/k11-g2-gen1-cpll-board.md`。
