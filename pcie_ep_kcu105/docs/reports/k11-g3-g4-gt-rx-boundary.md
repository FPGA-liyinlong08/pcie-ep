# K11 G3/G4/G5 GT 接收边界验证报告

日期：2026-08-11

状态：**G3/G4/G5完成；物理通道和GT RX配置已排除，问题收敛到Standalone未促使Root Port发送训练序列**

## 1. 验证目的

G1修正P1 Receiver Detect完成后缺失的P1→P0独立`PhyStatus`握手，G2使用
Gen1-only/CPLL PHY完成A/B后，实板仍不能枚举。本轮不重复检查已由官方XDMA Gen3 x1
证明正确的板级Lane、引脚、极性、REFCLK、PERST#和Root Port，而是把观测点下沉到
GTHE3边界：

1. G3直接采集GT原始RX状态，区分GT没有收到电气活动与PHY后处理屏蔽数据；
2. G4对比当前Standalone PHY与成功XDMA routed DCP的GTHE3属性及输入驱动；
3. G4实板采集RX电源、CDR hold、速率、极性和8b/10b控制时序。

## 2. 构建与采样

为避免宽ILA造成时序和CDC污染，本轮加入`K11B2_ILA_PIPE_ONLY=1`诊断模式，只生成
`u_ila_pipe`。跨100 MHz复位域的`GTRXRESET/RXUSERRDY`不直接接入250 MHz ILA，使用
同一GT的`RXRESETDONE`确认最终复位完成结果。

最终实现结果：

```text
ILA_PIPE_ONLY=1
WNS=+0.004 ns
WHS=+0.004 ns
DRC Error=0
CDC Critical=0
GTHE3_CHANNEL=GTHE3_CHANNEL_X0Y7
GTHE3_COMMON=GTHE3_COMMON_X0Y1
```

下载后在Detect.Active触发，按授权重启Root Port主机完成一次冷启动。原始采样：

```text
fpga/kcu105/build_k11b2_ila/capture/20260811_223515_u_ila_pipe.csv
```

## 3. G3：GT原始RX输出

4096个采样点的统计：

```text
RXRESETDONE=1:       4096
RXVALID=1:              0
RXELECIDLE=0:           0
RXSTATUS!=0:            1  # Receiver Detect完成拍，值为3
PHY RXVALID=1:          0
PHY RXDATA_VALID=1:     0
PHY RXELECIDLE=0:       0
PHY TX非ElectricalIdle: 804
PHY TX非零数据:         804
PHY TX DataK非零:       202
```

结论：不是Standalone PHY在GT之后丢弃了已接收的数据。GT接收器本身在训练窗口始终报告
Electrical Idle，没有产生RXVALID；与此同时Endpoint TX边界连续提交训练序列。

## 4. G4：GT静态配置对照

`report_g4_gt_compare.tcl`打开当前Standalone与官方XDMA成功镜像的routed DCP。二者均使用
`GTHE3_CHANNEL_X0Y7`。RX CDR、RX buffer、RX termination、Electrical Idle、8b/10b及
模拟接收相关属性一致；复位、RX/TX user-ready、PowerDown、Rate、Electrical Idle和
Receiver Detect输入也都由同类PHY/PIPE控制逻辑驱动。

去除对象名称、文件路径等非功能属性后，仅剩两项与时钟结构对应的差异：

```text
PCIE_BUFG_DIV_CTRL: standalone=16'h1008, XDMA=16'h3508
TX_PROGDIV_CFG:     standalone=8.000,    XDMA=4.000
```

这两项来自Standalone与XDMA不同的用户时钟/并行接口宽度，不构成RX模拟或终端配置差异。

## 5. G4：GT动态RX控制

关键状态时间线：

| 样点 | LTSSM | PhyStatus/RxStatus | RXPD | RXCDRHOLD | RXRATE | RXPOLARITY | RX8B10BEN | RXELECIDLE/RXVALID |
|---:|---|---|---:|---:|---:|---:|---:|---|
| 0 | Detect.Quiet | 0/0 | 2 (P1) | 0 | 0 | 0 | 1 | 1/0 |
| 3072 | Detect.Active | 0/0 | 2 (P1) | 0 | 0 | 0 | 1 | 1/0 |
| 3154 | Detect.Active | 1/3 | 2 (P1) | 0 | 0 | 0 | 1 | 1/0 |
| 3155 | PHY.PowerUp | 0/0 | 0 (P0) | 0 | 0 | 0 | 1 | 1/0 |
| 3291 | PHY.PowerUp | 1/0 | 0 (P0) | 0 | 0 | 0 | 1 | 1/0 |
| 3292 | Polling.Active | 0/0 | 0 (P0) | 0 | 0 | 0 | 1 | 1/0 |

该序列符合UltraScale GTH Receiver Detect要求：在P1完成检测，再返回P0进行正常接收。
进入Polling.Active时RX已在P0、CDR未Hold、Gen1速率、无极性反转且8b/10b已启用。

## 6. 旧基线与成功镜像同板A/B

为确认当前失败是否由近期RTL改动引入，分别测试三个镜像：

| 镜像 | 实现/加载结果 | Root Port结果 |
|---|---|---|
| Git旧基线`f31412f`隔离构建 | WNS `+0.020 ns`、WHS `+0.014 ns`，DRC/CDC通过 | Gen1 x1，`Train+ / DLActive-`，无Endpoint |
| 2026-08-10保留的原成功Standalone bit | 原文件直接下载 | Gen1 x1，`Train+ / DLActive-`，无Endpoint |
| 官方XDMA Gen3 x1 demo | 同一JTAG、同一插槽、同一主机启动 | 枚举`10ee:9031`，Gen3 x1，`Train- / DLActive+` |

旧源码和原始成功产物现在均不能复现Standalone L0，因此失败不能直接归因于`f31412f`之后的
代码回归。XDMA在相同测试会话中稳定枚举，进一步排除Lane映射、物理引脚、极性、REFCLK、
PERST#和Root Port硬件失效。

## 7. G5：成功XDMA的GT动态参考

从官方XDMA的opt DCP直接插入窄ILA，时钟使用`user_clk`，只观察同一
`GTHE3_CHANNEL_X0Y7`的RX/TX边界信号。实现结果：

```text
WNS=+0.180 ns
WHS=+0.013 ns
DRC Error/Critical=0
```

第一次在`TXDETECTRX=1`触发的采样记录了启动早期的一次失败Detect：

```text
fpga/kcu105/build_g5_xdma_rx_ila/capture/20260811_230754_xdma_rx.csv
RXPD=P1, RXELECIDLE=1, RXVALID=0, RXSTATUS=0
```

随后使用常驻Vivado会话，在主机复位后先等待`RXVALID=0`，再即时重布防`RXVALID=1`，抓到
本次成功启动的实际建链边界：

```text
fpga/kcu105/build_g5_xdma_rx_ila/capture/20260811_231930_xdma_rx_retrain.csv
```

| 样点 | RXRESETDONE | RXPD | RXELECIDLE | RXVALID | RXCDRHOLD | RXRATE | RXPOLARITY | RX8B10BEN |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 1 | P0 | 1 | 0 | 0 | Gen1 | 0 | 1 |
| 929 | 1 | P0 | 0 | 0 | 0 | Gen1 | 0 | 1 |
| 1024 | 1 | P0 | 0 | 1 | 0 | Gen1 | 0 | 1 |

XDMA成功时，对端电气活动先到达（`RXELECIDLE 1→0`），约95个`user_clk`周期后GT给出
`RXVALID=1`。这些动态RX控制与Standalone进入Polling.Active后的控制值一致；唯一实质差异是
Standalone始终收不到前面的对端电气活动。

## 8. 结论与下一步

G3/G4/G5排除：

- GT RX复位未完成；
- GT RX在接收数据但被Standalone PHY后处理屏蔽；
- RX保持在低功耗、CDR被Hold、速率选择错误、极性反转或8b/10b未启用；
- Standalone与成功XDMA在RX模拟/终端静态属性上存在关键差异。
- 板级Lane、物理引脚、极性、REFCLK、PERST#或Root Port失效。
- 当前失败是近期源码提交造成的确定性回归。

剩余现象是：Standalone完成对Root Port的Receiver Detect并发送TS1，但Root Port方向始终为
Electrical Idle；XDMA则能促使Root Port发出训练序列。下一步执行G6，直接验证Root Port是否
检测到Standalone RX终端：下载Standalone后，不先改RTL，依次做Root Port Secondary Bus Reset、
Link Disable/Enable和总线rescan，并同步触发`RXELECIDLE`下降沿。若热重训能进入L0，问题属于
上电/首次Detect时序；若仍无电气活动，则进一步对比Standalone与XDMA的TX Detect/终端呈现时序，
而不是回到物理引脚检查。
