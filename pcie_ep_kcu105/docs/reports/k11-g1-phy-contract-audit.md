# K11 G1 PHY接口契约审计报告

日期：2026-08-11  
结论：**G1 PASS；发现并修复一个可独立复现的 PHY 控制时序缺陷。实板已证明修复生效，但链路仍未枚举，因此它不是唯一根因。**

## 1. 审计范围

- `pcie_phy` XCI、生成 wrapper 与自研 LTSSM/MAC 的端口、位宽和固定配置；
- Gen1 x1 下 `RxValid/RxDataValid`、16/32-bit 数据使用、DataK、Rate、Powerdown、
  Electrical Idle、Receiver Detect 和 `PhyStatus` 时序；
- TS1/TS2 的 16 个 Symbol、K/Data 属性、Link/Lane、N_FTS、Rate 和 Control 字段；
- K02/K03 Verilator、Xilinx standalone PHY + Root Port VCS 联合仿真。

## 2. 审计结论

以下项目匹配，未发现需要修改的配置或映射：

- XCI 为 x1、100 MHz参考时钟、GT X0Y7；运行时固定 Gen1；
- Gen1 有效数据位于 `phy_*data[15:0]`，高 16 bit 为 0，`datak[1:0]`逐字节对应；
- `phy_rate=2'b00`固定Gen1，TS Rate ID `8'h02`为Gen1能力编码；
- TS1 为 `BC F7 F7 FF 02 00 4A...`，TS2仅identifier改为`45`，K属性正确；
- `phy_async_en`的XCI/生成模型表达差异属于生成器映射，不是当前故障。

发现的缺陷位于 Receiver Detect 之后：旧 RTL 在 P1 中收到 Detect 完成脉冲后直接进入
Polling.Active，同时请求 P0、撤销 TX Electrical Idle 并提交 TS1，没有等待 P1→P0
电源转换自己的 `PhyStatus` 完成脉冲。Xilinx PHY 示例控制器和真实 PHY 仿真均把 Detect
与 Return-to-P0 作为两项独立操作。

## 3. 修复与门禁

新增状态 `PHY_POWERUP=15`：

```text
Detect.Active --Detect PhyStatus/RxStatus=011--> PHY.PowerUp
PHY.PowerUp   --P0 PhyStatus-----------------> Polling.Active
```

在 PHY.PowerUp 中固定 `powerdown=00`、`txdetectrx=0`、`txelecidle=1`、
`txdata_valid=0`。第二个 `PhyStatus` 到达后才撤销 Electrical Idle 并发送 TS1；等待超时
则回 Detect.Quiet 并增加超时计数。

验证结果：

| 门禁 | 结果 |
|---|---|
| 修复前定向复现 | FAIL：Detect完成后立即观察到`txelecidle=0` |
| 修复后定向测试 | PASS |
| K03 Verilator directed/random | PASS，10/10；100次训练；2000包 |
| K02 PHY模型随机向量 | PASS，10000向量 |
| K03 lint/Checker自检/扰码器 | PASS |
| K03 Vivado OOC | PASS，WNS=4.792 ns |
| K03+K02集成布局布线/比特流 | PASS，DRC 0 Error，WNS=0.203 ns |
| Xilinx PHY + Xilinx Root Port VCS | PASS：经过状态15，完成L0、枚举和BAR读写 |

## 4. G1出口与后续判据

G1的软件门禁已闭环。该修复解释了自研端点与 standalone PHY 之间的一处明确契约违例，
但仿真通过不能单独证明它就是实板唯一根因。下一次实板冷启动应以以下信号作为判据：

1. Detect成功后先观察状态15及独立的P0完成脉冲；
2. 随后进入Polling.Active并发送TS1；
3. Root Port返回TS1/TS2，LTSSM离开Polling.Active；
4. Linux枚举出`1234:e001`并可完成BAR0基本读写。

若第1、2项通过而第3项仍失败，应转入G2，核对standalone PHY的速率/PLL配置、
真实GT收发状态和自研MAC的PHY边界。官方XDMA Gen3 x1已在同板、同机、同插槽通过，
因此不再重复核对物理引脚、Lane映射或板级极性，也不再修改已通过独立Checker的TS字段。

## 5. 实板冷启动验证

2026-08-11使用包含本修复的K11-B3 ILA镜像上板，完成了真实Linux主机重启。
最终Detect.Active触发采样为：

| 采样 | LTSSM | `PhyStatus/RxStatus` | TX Electrical Idle | TX Valid |
|---:|---|---|---:|---:|
| 0‑3071 | Detect.Quiet | 0/0 | 1 | 0 |
| 3072‑3154 | Detect.Active | 末拍1/3 | 1 | 0 |
| 3155‑3291 | PHY.PowerUp | 末拍1/0 | 1 | 0 |
| 3292‑4095 | Polling.Active | 0/0 | 0 | 1 |

这证明实板上Receiver Detect和P1→P0确实由两个独立`PhyStatus`完成，
第二个脉冲之前没有发送TS1。G1接口修复的实板验收通过。

但该窗口内Endpoint没有收到Root Port TS1/TS2，最终仍停在
`Polling.Active`，没有DLLP、配置请求或Completion。Linux也未枚举`1234:e001`；
Root Port为Gen1 x1、`Train+ / DLActive-`，AER中`RxErr/BadTLP/BadDLLP`均为0。

证据文件：

- `fpga/kcu105/build_k11b2_ila/capture/20260811_193254_u_ila_pipe.csv`：下载后的G1握手采样；
- `fpga/kcu105/build_k11b2_ila/capture/20260811_202311_u_ila_pipe.csv`：冷启动PERST#下降窗口；
- `fpga/kcu105/build_k11b2_ila/capture/20260811_202719_u_ila_pipe.csv`：最终冷启动Detect→PowerUp→Polling窗口。

实板结论是：**G1缺陷已修复并验证，但链路未识别问题仍存在，出口指向G2。**
