# K01 时钟与复位接口契约

状态：**PASS / K01-v1 接口已冻结**

## 1. 顶层模块 `kcu105_refclk_reset`

### 参数

| 参数 | 默认值 | 合法范围 | 含义 |
|---|---:|---:|---|
| `RESET_SYNC_STAGES` | 4 | 2～8 | PIPE/Core 复位同步释放级数 |

### 输入端口

| 端口 | 位宽 | 时钟域 | 复位值/电气 | 契约 |
|---|---:|---|---|---|
| `pcie_refclk_p` | 1 | GT Reference | AB6 | 100 MHz 差分正端 |
| `pcie_refclk_n` | 1 | GT Reference | AB5 | 100 MHz 差分负端 |
| `pcie_perst_n` | 1 | 异步 | K22、LVCMOS18、上拉 | 板级 PERST#，低有效 |
| `phy_pclk` | 1 | PIPE | K02 PHY 输出 | Gen1/2/3 分别为 62.5/125/250 MHz |
| `phy_coreclk` | 1 | Core | K02 PHY 输出 | 固定 250 MHz |
| `phy_phystatus_rst` | 1 | 异步置位源 | K02 PHY 输出，高有效 | 只复位 PIPE 域 |

### 输出端口

| 端口 | 位宽 | 所属域 | 复位值 | 契约 |
|---|---:|---|---:|---|
| `phy_gtrefclk` | 1 | GT Reference | 不适用 | `IBUFDS_GTE3.O`，只连接 PHY `phy_gtrefclk` |
| `phy_refclk` | 1 | PHY Fabric Reference | 不适用 | `ODIV2` 经 `BUFG_GT`，连接 PHY `phy_refclk` |
| `phy_rst_n` | 1 | 异步 | 0 | 组合直连 `pcie_perst_n`，不延迟、不滤波 |
| `pipe_rst_n` | 1 | `phy_pclk` | 0 | PERST#/PHY Status 异步置位，本域同步释放 |
| `core_rst_n` | 1 | `phy_coreclk` | 0 | 只由 PERST# 异步置位，本域同步释放 |

## 2. 控制子模块 `kcu105_reset_ctrl`

该子模块不实例化 Xilinx 原语，供 Verilator 随机压力测试。

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `phy_pclk` | 输入 | 1 | PIPE 复位释放时钟 |
| `phy_coreclk` | 输入 | 1 | Core 复位释放时钟 |
| `pcie_perst_n` | 输入 | 1 | 异步低有效总复位 |
| `phy_phystatus_rst` | 输入 | 1 | 异步高有效 PIPE 复位 |
| `phy_rst_n` | 输出 | 1 | 直接等于 `pcie_perst_n` |
| `pipe_rst_n` | 输出 | 1 | PIPE 域低有效复位 |
| `core_rst_n` | 输出 | 1 | Core 域低有效复位 |

## 3. 释放和置位时序

- `phy_rst_n`：PERST# 变化后一个组合传播延迟内变化；
- `core_rst_n`：PERST# 拉高后的第 `RESET_SYNC_STAGES` 个 `phy_coreclk` 上升沿释放；
- `pipe_rst_n`：PERST# 为高且 `phy_phystatus_rst` 为低后的第
  `RESET_SYNC_STAGES` 个 `phy_pclk` 上升沿释放；
- 任一异步置位条件出现时，不等待本域时钟边沿，相关复位立即拉低；
- `phy_phystatus_rst` 不得改变 `phy_rst_n`、`core_rst_n`；
- 输出复位不允许毛刺，也不允许提前释放；时钟停止期间不产生释放进度。

## 4. 参考时钟规则

- `IBUFDS_GTE3` 固定参数：`REFCLK_EN_TX_PATH=0`、
  `REFCLK_HROW_CK_SEL=2'b00`、`REFCLK_ICNTL_RX=2'b00`；
- `CEB` 固定为 0，参考时钟缓冲永久使能；
- `phy_refclk` 的 `BUFG_GT` 固定 `CE=1`、`DIV=0`，不门控、不分频；
- K01 不允许在参考时钟路径加入 MMCM、PLL 或普通逻辑门控。
