# M01 时钟复位接口契约

状态：**PASS / M01-v1 已冻结**  
版本：M01-v1

## 1. 顶层模块 `pcie_clk_reset`

### 参数

| 参数 | 默认值 | 含义 |
|---|---:|---|
| `RESET_SYNC_STAGES` | 4 | 各时钟域复位同步级数，合法范围 2～8 |
| `STATUS_SYNC_STAGES` | 2 | 异步状态同步级数，合法范围 2～4 |

### 输入

| 端口 | 位宽 | 时钟域 | 有效方式 | 契约 |
|---|---:|---|---|---|
| `pcie_refclk_p` | 1 | GT Reference | 差分 P | 100 MHz，连接 P6 |
| `pcie_refclk_n` | 1 | GT Reference | 差分 N | 与 P 端互补 |
| `sys_clk_100` | 1 | 本地系统 | 上升沿 | 100 MHz，连接 P26 |
| `pcie_perst_n` | 1 | 异步 | 低有效 | 连接 L24；对所有复位异步置位 |
| `gt_txoutclk` | 1 | GT TX | 上升沿 | M03 GT Channel 的 TXOUTCLK |
| `gt_rxoutclk` | 1 | GT RX | 上升沿 | M03 GT Channel 的 RXOUTCLK |
| `gt_pll_lock` | 1 | 异步状态 | 高有效 | M03 汇总后的当前速率 PLL lock |
| `gt_tx_reset_done` | 1 | 异步状态 | 高有效 | GT TX Datapath 已完成复位 |
| `gt_rx_reset_done` | 1 | 异步状态 | 高有效 | GT RX Datapath 已完成复位 |

### 输出

| 端口 | 位宽 | 时钟域 | 复位值 | 契约 |
|---|---:|---|---:|---|
| `gt_refclk` | 1 | GT Reference | 不适用 | `IBUFDS_GTE3.O`，只能连接 GT Common/Channel 参考时钟输入 |
| `core_clk_250` | 1 | Core | 不适用 | 固定 250 MHz，由 MMCM+BUFG 产生 |
| `core_rst_n` | 1 | Core | 0 | 异步置位，连续四拍同步释放 |
| `gt_txusrclk` | 1 | GT TX User | 不适用 | `gt_txoutclk` 经 BUFG_GT，分频值为 1 |
| `gt_rxusrclk` | 1 | GT RX User | 不适用 | `gt_rxoutclk` 经 BUFG_GT，分频值为 1 |
| `pipe_clk` | 1 | PIPE | 不适用 | 与 `gt_txusrclk` 同源、同相 |
| `pipe_rst_n` | 1 | PIPE | 0 | 异步置位，连续四拍同步释放 |
| `core_mmcm_locked` | 1 | 异步状态 | 0 | MMCM 原始 LOCKED 输出，仅用于调试和复位控制 |
| `clock_ready` | 1 | Core | 0 | Core、PIPE 与 GT 状态均完成同步后为高 |

## 2. 控制子模块 `pcie_clk_reset_ctrl`

该子模块不含 Xilinx 时钟原语，是 Verilator 随机复位测试的 DUT。

### 输入

| 端口 | 位宽 | 时钟域 | 说明 |
|---|---:|---|---|
| `core_clk` | 1 | Core | 已缓冲的 Core Clock |
| `pipe_clk` | 1 | PIPE | 已缓冲的 PIPE Clock |
| `pcie_perst_n` | 1 | 异步 | 主机复位 |
| `core_clock_locked` | 1 | 异步 | Core MMCM lock |
| `gt_pll_lock` | 1 | 异步 | GT PLL lock |
| `gt_tx_reset_done` | 1 | 异步 | GT TX ready |
| `gt_rx_reset_done` | 1 | 异步 | GT RX ready |

### 输出

| 端口 | 位宽 | 时钟域 | 说明 |
|---|---:|---|---|
| `core_rst_n` | 1 | Core | Core 域复位 |
| `pipe_rst_n` | 1 | PIPE | PIPE 域复位 |
| `clock_ready` | 1 | Core | 同步后的综合就绪状态 |

## 3. 时序要求

- `core_rst_n`：释放条件满足后，第 4 个 Core 上升沿之后为高。
- `pipe_rst_n`：释放条件满足后，第 4 个 PIPE 上升沿之后为高。
- 异步条件撤销后，不等待时钟边沿即可置位相应复位。
- `clock_ready` 的拉高必须晚于两个复位的释放；从 PIPE 复位释放到
  `clock_ready` 拉高允许 2～3 个 Core 周期同步延迟。
- 本模块不对 `gt_txoutclk`/`gt_rxoutclk` 的频率做运行时测量。

## 4. 非法配置

`RESET_SYNC_STAGES < 2` 或 `STATUS_SYNC_STAGES < 2` 属于 Elaborate 错误。
RTL 必须通过常量检查拒绝这些参数，不允许静默降级。
