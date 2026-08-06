# KCU105 Endpoint 固定接口契约

状态：**K00-v1 冻结**

本文冻结跨模块边界。K02 生成 XCI 后还必须对生成 Stub 与第 2 节逐端口比对；
IP 版本导致的端口变化必须先升级本文版本，不能在 Wrapper 中静默猜测。

## 1. 板级接口

| 端口 | 方向 | 位宽 | 电气/管脚 | 规则 |
|---|---:|---:|---|---|
| `pcie_refclk_p/n` | 输入 | 1 | AB6/AB5，MGTREFCLK | 100 MHz 差分 |
| `pcie_perst_n` | 输入 | 1 | K22，LVCMOS18 | 异步有效、低有效 |
| `pcie_rxp/n` | 输入 | 1 | AB2/AB1 | PCIe Lane 0 |
| `pcie_txp/n` | 输出 | 1 | AC4/AC3 | PCIe Lane 0 |

不暴露 300 MHz 板载时钟端口，不暴露 GT DRP，不允许上层直接访问 GTHE3。

## 2. standalone PHY 原生接口

方向以自研 MAC 为观察点：“输出”表示 MAC 驱动 PHY，“输入”表示 MAC 接收 PHY。
所有数据和控制均属于 `phy_pclk` 域，复位期间发送控制取安全空闲值。

### 2.1 数据与 Gen3 Block

| 信号 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `phy_txdata` | 输出 | 32 | 线路最先字节位于 `[7:0]` |
| `phy_txdatak` | 输出 | 2 | Gen1/2 控制字符标记，语义以 PHY v1.0 为准 |
| `phy_txdata_valid` | 输出 | 1 | TX 数据有效 |
| `phy_txstart_block` | 输出 | 1 | Gen3 Block 起点 |
| `phy_txsync_header` | 输出 | 2 | Gen3 Sync Header |
| `phy_rxdata` | 输入 | 32 | 线路最先字节位于 `[7:0]` |
| `phy_rxdatak` | 输入 | 2 | Gen1/2 控制字符标记 |
| `phy_rxdata_valid` | 输入 | 1 | RX 数据有效 |
| `phy_rxstart_block` | 输入 | 1 | Gen3 Block 起点 |
| `phy_rxsync_header` | 输入 | 2 | Gen3 Sync Header |

不增加 32/64/128-bit 宽度转换器。`datak` 的 2-bit 宽度是生成 IP 的原生契约，
不得沿用 KU060 计划中的 `datak[3:0]` 假设。

### 2.2 链路控制和状态

| 信号 | 方向 | 位宽 |
|---|---:|---:|
| `phy_txdetectrx` | 输出 | 1 |
| `phy_txelecidle`、`phy_txcompliance`、`phy_rxpolarity` | 输出 | 各 1 |
| `phy_powerdown`、`phy_rate` | 输出 | 各 2 |
| `phy_txmargin` | 输出 | 3 |
| `phy_txswing`、`phy_txdeemph` | 输出 | 各 1 |
| `as_mac_in_detect`、`as_cdr_hold_req` | 输出 | 各 1 |
| `phy_rxvalid`、`phy_phystatus`、`phy_rxelecidle` | 输入 | 各 1 |
| `phy_phystatus_rst` | 输入 | 1 |
| `phy_rxstatus` | 输入 | 3 |

`phy_phystatus` 是 Receiver Detect、Power State 或 Rate 操作的完成握手，具体
请求/完成时序在 K02 的 PHY Partner 与 VCS 测试计划中逐项冻结。

### 2.3 Gen3 均衡

| 信号 | 方向 | 位宽 |
|---|---:|---:|
| `phy_txeq_ctrl` | 输出 | 2 |
| `phy_txeq_preset` | 输出 | 4 |
| `phy_txeq_coeff` | 输出 | 6 |
| `phy_rxeq_ctrl` | 输出 | 2 |
| `phy_rxeq_txpreset` | 输出 | 4 |
| `phy_txeq_fs`、`phy_txeq_lf` | 输入 | 各 6 |
| `phy_txeq_new_coeff` | 输入 | 18 |
| `phy_txeq_done` | 输入 | 1 |
| `phy_rxeq_preset_sel` | 输入 | 1 |
| `phy_rxeq_new_txcoeff` | 输入 | 18 |
| `phy_rxeq_adapt_done`、`phy_rxeq_done` | 输入 | 各 1 |

## 3. 时钟与复位接口

| 信号 | 来源/方向 | 规则 |
|---|---|---|
| `phy_gtrefclk` | `IBUFDS_GTE3.O → PHY` | GT 100 MHz 参考时钟 |
| `phy_refclk` | `IBUFDS_GTE3.ODIV2 → PHY` | PHY fabric 参考时钟 |
| `phy_rst_n` | PERST# → PHY | 直接低有效复位 |
| `phy_pclk` | PHY → Link | 供 LTSSM/MAC/DLL |
| `phy_coreclk` | PHY → Core | 固定 250 MHz |
| `phy_userclk` | PHY 输出 | 保留，第一阶段不用 |
| `pipe_rst_n` | K01 输出 | 异步置位、`phy_pclk` 同步释放 |
| `core_rst_n` | K01 输出 | 异步置位、`phy_coreclk` 同步释放 |

## 4. 128-bit TLP Packet Stream

DLL/TL 两侧均使用普通 SystemVerilog 端口：`valid`、`ready`、`data[127:0]`、
`keep[15:0]`、`sop`、`eop`、`error[3:0]`。

- 首字节在 `data[7:0]`；除末拍外 `keep=16'hffff`；
- SOP/EOP 必须与首/末 Beat 同拍；单 Beat 包同时置位；
- `valid && !ready` 时数据和边带稳定；允许包内 Backpressure；
- 不允许组合 `valid-ready-valid` 环路；
- RX 已去除 Sequence Number/LCRC，TX 由 DLL 添加。

M02 的完整端口、延迟和 Flush 规则见
`docs/interfaces/02-pcie-async-pkt-fifo-interfaces.md`。

## 5. 配置空间请求接口

请求：`cfg_req_valid/ready`、`cfg_req_write`、`cfg_req_dw_addr[9:0]`、
`cfg_req_be[3:0]`、`cfg_req_wdata[31:0]`、`cfg_req_requester_id[15:0]`、
`cfg_req_tag[7:0]`、`cfg_req_target_bdf[15:0]`。

响应：`cfg_rsp_valid/ready`、`cfg_rsp_status[2:0]`、`cfg_rsp_rdata[31:0]`、
`cfg_rsp_completer_id[15:0]`。

接口位于 `phy_coreclk` 域；请求和响应各自按 Ready/Valid 传输，Stall 时保持稳定。

## 6. BAR0 与 AXI4-Lite

- BAR 相对地址 `bar_addr[11:0]`，BAR0 固定 4 KiB；
- Memory Write 支持 1～32 DW，Posted Write 不返回 Completion；
- Memory Read 支持 1～1024 DW，Completion 受 128 B MPS、RCB 和 4 KiB 边界约束；
- AXI4-Lite 为 32-bit 单事务顺序访问；`WSTRB` 来自 First/Last BE；
- AXI `SLVERR/DECERR` 转换为 CA，未命中或未支持请求进入 UR 路径。
