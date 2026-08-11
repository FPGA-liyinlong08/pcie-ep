# K11 G2 Gen1/CPLL A/B上板验证报告

日期：2026-08-11  
结论：**G2完成；Gen1-only/CPLL仍未枚举，但Root Port稳定进入Gen1 x1训练。原
Gen3/QPLL1配置不是唯一根因，板级物理引脚无需重查。**

## 1. 验证目标与边界

官方XDMA Gen3 x1曾在同一块KCU105、同一主机、同一插槽和同一Lane达到8 GT/s x1，
驱动、BAR和AER均正常。因此G2不重复检查金手指、GT TX/RX引脚、Lane映射、板级极性、
参考时钟或PERST#；本轮只验证自研MAC与standalone `pcie_phy`的配置和真实GT边界。

原K02 PHY配置为最大Gen3、QPLL1，但自研MAC运行时固定请求Gen1。G2建立独立A/B分支：

| 项目 | 原基线 | G2诊断 |
|---|---|---|
| 最大速率 | 8.0 GT/s | 2.5 GT/s |
| PLL | QPLL1 | CPLL |
| Lane/GT | x1 / X0Y7 | x1 / X0Y7 |
| PHY模块接口名 | `pcie_phy_x1_gen3` | 相同，位于独立IP目录 |
| RTL/LTSSM/TS1 | 不变 | 不变 |

## 2. PHY接口与数字证据

- Vivado生成摘要确认`phy_max_speed=2.5_GT/s`、`pll_type=CPLL`、100 MHz参考时钟、
  x1及`GTHE3_CHANNEL_X0Y7`；生成网表线速为2.5 GT/s，未生成GTHE3 Common。
- Gen1 PHY边界仍使用`phy_txdata[15:0]`及`phy_txdatak[1:0]`，高16 bit不参与Gen1；
  TS1内容和连续发送节拍没有因A/B构建改变。
- 原Gen3/QPLL1正式构建的MAC TX到GTHE3 `TXDATA`最差setup曾为`-0.062 ns`，增加
  路由后物理优化后为`-0.007 ns`，因此按正式门禁拒绝生成bitstream。
- G2 Gen1/CPLL完整Endpoint路由后setup WNS=`+0.019 ns`、hold=`+0.030 ns`，
  DRC为0 Error/0 Critical Warning，0条失败布线，成功生成bitstream。
- Xilinx standalone PHY + Xilinx Root Port的既有真实串行仿真可完成L0、枚举和BAR读写。
  G2 CPLL模型已编译通过；VCS展开因浮动许可证排队300秒超时，记为环境阻塞，不能记为
  功能失败。

## 3. 实板步骤与结果

1. 通过JTAG识别唯一`xcku040_0`并下载
   `fpga/kcu105/build_g2_gen1/impl/g2_gen1_cpll_endpoint.bit`；Vivado报告
   `K11B2_HW_PROGRAM_PASS action=program-g2-gen1`。
2. 重启远端Linux主机，确认本次启动时间为`2026-08-11 21:38:11`。
3. `lspci -nn`未出现`1234:e001`，bus 01无Endpoint。
4. Root Port `00:01.0`完整状态为：
   - `LnkSta: Speed 2.5GT/s, Width x1, Train+, DLActive-`；
   - `LnkCtl2 Target Link Speed: 2.5GT/s`；
   - Presence Detect为真；
   - AER的RxErr、BadTLP、BadDLLP及Fatal/NonFatal状态均为0。
5. 每2秒读取一次Link Status，连续5次均为`0x1811`：速度编码Gen1、协商宽度x1、
   Training位为1、Slot Clock位为1。状态是稳定卡在训练，并非偶发枚举窗口。

## 4. 判定与下一出口

G2没有实现Linux枚举，因此功能结果为FAIL；但诊断目标已闭环：

- Gen1/CPLL与Gen3/QPLL1在实板上的最终现象一致，最大速率/PLL过配置不是唯一根因；
- Root Port能稳定报告Gen1 x1训练，故障不是“物理引脚完全无信号”；
- Endpoint此前ILA证明持续发TS1但收不到Root Port TS1/TS2，结合本轮`Train+`，剩余重点是
  standalone PHY接收输出、8b/10b K字符/字节对齐、`RxValid/RxDataK/RxStatus`到自研MAC的
  逐周期解释。

建议G3直接在GT/PHY RX边界做定点捕获或近端环回，不再检查物理引脚，也不再修改已通过
Xilinx Root Port联合仿真的TS1字段。

## 5. 可重复入口

```text
make g2-gen1-vivado
make g2-gen1-vcs-serial
make g2-gen1-hw-program
```

生成器通过`G2_GEN1_ONLY=1`选择独立`fpga/kcu105/ip_g2_gen1`目录，默认K02
Gen3/QPLL1配置和原XCI均不被覆盖。
