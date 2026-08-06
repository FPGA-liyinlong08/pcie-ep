# K02 standalone PCIe PHY 原生接口契约

状态：**K02-PHY32-v1.1 条件冻结；VCS 动态与上板延期**

## 1. 顶层模块 `kcu105_pcie_phy_wrapper`

所有端口使用普通 SystemVerilog 端口，不使用 `interface`。x1 向量在封装层统一压成
标量；总线宽度保持 Xilinx 生成端口原值。

### 板级端口

| 端口 | 方向 | 位宽 | 时钟域/管脚 | 说明 |
|---|---:|---:|---|---|
| `pcie_refclk_p/n` | 输入 | 1/1 | AB6/AB5 | 100 MHz PCIe 差分参考时钟 |
| `pcie_perst_n` | 输入 | 1 | K22，异步 | Root Port PERST#，低有效 |
| `pcie_rxp/n` | 输入 | 1/1 | AB2/AB1 | Lane 0 串行接收 |
| `pcie_txp/n` | 输出 | 1/1 | AC4/AC3 | Lane 0 串行发送 |

### 时钟和复位输出

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `phy_pclk` | 输出 | 1 | Gen1/2/3 为 125/250/250 MHz |
| `phy_coreclk` | 输出 | 1 | 固定 250 MHz |
| `phy_userclk` | 输出 | 1 | 固定 125 MHz，K02 不使用 |
| `phy_mcapclk` | 输出 | 1 | PHY 生成，K02 只观测 |
| `pipe_rst_n` | 输出 | 1 | PERST#/PhyStatus 异步置位，`phy_pclk` 四拍释放 |
| `core_rst_n` | 输出 | 1 | 只受 PERST#，`phy_coreclk` 四拍释放 |
| `phy_phystatus_rst` | 输出 | 1 | PHY 原生高有效状态复位，Rate Change 可重新置位 |

## 2. PHY32 数据端口

线路上先出现的字节位于 `data[7:0]`。

| 端口 | 方向 | 位宽 | 所属域 | 复位/空闲规则 |
|---|---:|---:|---|---|
| `phy_txdata` | 输入 | 32 | `phy_pclk` | 复位期间 0 |
| `phy_txdatak` | 输入 | 2 | `phy_pclk` | Xilinx 原生宽度，不扩成 4 bit |
| `phy_txdata_valid` | 输入 | 1 | `phy_pclk` | Gen3 数据块有效；复位 0 |
| `phy_txstart_block` | 输入 | 1 | `phy_pclk` | Gen3 块开始；复位 0 |
| `phy_txsync_header` | 输入 | 2 | `phy_pclk` | Gen3 Sync Header；复位 0 |
| `phy_rxdata` | 输出 | 32 | `phy_pclk` | 只在对应有效信号成立时采样 |
| `phy_rxdatak` | 输出 | 2 | `phy_pclk` | Gen1/2 控制信息 |
| `phy_rxdata_valid` | 输出 | 1 | `phy_pclk` | RX Data 有效 |
| `phy_rxstart_block` | 输出 | 1 | `phy_pclk` | Gen3 块开始 |
| `phy_rxsync_header` | 输出 | 2 | `phy_pclk` | Gen3 Sync Header |

端口名义宽度保持 32 bit，但有效宽度按速率固定：Gen1/2 只有
`data[15:0]` 和 `datak[1:0]` 有效，每拍两个 8b/10b Symbol；Gen3 使用 32 bit
block 数据。Gen1/2 时 `data[31:16]` 必须发送 0、接收侧不得采样。K03 不得改变
上述宽度或字节序；如协议实现需要内部格式转换，只能在 K03 MAC 内部完成。

## 3. PHY 控制与状态

### MAC → PHY

| 端口 | 位宽 | 复位值 | 规则 |
|---|---:|---:|---|
| `phy_txdetectrx` | 1 | 0 | Receiver Detect 命令 |
| `phy_txelecidle` | 1 | 1 | 发送 Electrical Idle |
| `phy_txcompliance` | 1 | 0 | Compliance 模式，本阶段不用 |
| `phy_rxpolarity` | 1 | 0 | 接收极性翻转 |
| `phy_powerdown` | 2 | `2'b10` | P0/P0s/P1/P2 编码为 00/01/10/11 |
| `phy_rate` | 2 | 0 | 00=Gen1、01=Gen2、10=Gen3；11 非法 |
| `phy_txmargin` | 3 | 0 | Gen1/2 TX Margin |
| `phy_txswing` | 1 | 0 | Full/Low Swing 控制 |
| `phy_txdeemph` | 1 | 0 | Gen1/2 De-emphasis |
| `phy_txeq_ctrl` | 2 | 0 | Gen3 TX EQ 控制 |
| `phy_txeq_preset` | 4 | 0 | Gen3 TX Preset |
| `phy_txeq_coeff` | 6 | 0 | Gen3 TX Coefficient |
| `phy_rxeq_ctrl` | 2 | 0 | Gen3 RX EQ 控制 |
| `phy_rxeq_txpreset` | 4 | 0 | 对端 TX Preset 请求 |
| `as_mac_in_detect` | 1 | 1 | LTSSM 位于 Detect；K03 驱动 |
| `as_cdr_hold_req` | 1 | 0 | CDR Hold Assist；K03/K12 驱动 |

### PHY → MAC

| 端口 | 位宽 | 采样域 | 规则 |
|---|---:|---|---|
| `phy_rxvalid` | 1 | `phy_pclk` | 接收有效 |
| `phy_phystatus` | 1 | `phy_pclk` | Power/Rate/Detect 操作完成脉冲 |
| `phy_rxelecidle` | 1 | `phy_pclk` | RX Electrical Idle |
| `phy_rxstatus` | 3 | `phy_pclk` | Detect 成功必须为 `3'b011` |
| `phy_txeq_fs/lf` | 6/6 | `phy_pclk` | TX EQ Full/Low Frequency 指标 |
| `phy_txeq_new_coeff` | 18 | `phy_pclk` | 新 TX 系数 |
| `phy_txeq_done` | 1 | `phy_pclk` | TX EQ 命令完成 |
| `phy_rxeq_preset_sel` | 1 | `phy_pclk` | RX 选择 Preset 模式 |
| `phy_rxeq_new_txcoeff` | 18 | `phy_pclk` | RX 建议的对端 TX 系数 |
| `phy_rxeq_adapt_done` | 1 | `phy_pclk` | RX Adaptation 完成 |
| `phy_rxeq_done` | 1 | `phy_pclk` | RX EQ 命令完成 |

## 4. 握手和合法性

- 控制输入只在 `pipe_rst_n=1` 后改变；复位期间必须保持表中值；
- `phy_rate` 改变后，MAC 保持新值直到观察到 `phy_phystatus` 完成；
- Rate Change 期间 `phy_phystatus_rst` 可置位，从而重置 PIPE 域，但
  `core_rst_n` 必须保持高；
- Receiver Detect 时保持 `PowerDown=P1`、`TxElecIdle=1`、
  `TxDetectRx=1`，直到 `phy_phystatus`；
- `rxstatus=3'b011` 表示检测到接收终端，其他值按未检测到或错误处理；
- `phy_rate=2'b11`、未知 X/Z 控制和在复位期间发送数据均为接口违例；
- 本模块不提供 ready/valid 反压；PHY32 是每拍固定并行接口。
