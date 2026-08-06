# 接口冻结契约

状态：**M00 基线，版本 1**

所有可综合模块边界均使用独立的 SystemVerilog 端口。RTL 契约中不使用
SystemVerilog `interface`、class 或 DPI。

## 全局约定

- 低有效复位以 `_rst_n` 结尾；异步置位，在所属时钟域上升沿同步释放。
- Ready/Valid 传输只在同一上升沿二者同时为高时发生。
- 当 `valid=1` 且 `ready=0` 时，发送方必须保持数据和所有 Sideband 信号稳定。
- PCIe 线路上的第 0 个字节位于 `data[7:0]`，后续字节占据递增的位位置。
- 保留输入固定为零；输出不得产生保留编码。
- 除非模块架构另有规定，状态计数器达到最大值后饱和，不允许回绕。

## FPGA 顶层接口

| 端口 | 方向 | 位宽 | 时钟/复位 | 契约 |
|---|---:|---:|---|---|
| `pcie_refclk_p/n` | 输入 | 1 | 异步 | 100 MHz PCIe 差分参考时钟 |
| `pcie_perst_n` | 输入 | 1 | 异步 | 主机 PERST#，低有效 |
| `sys_clk_100` | 输入 | 1 | 异步 | 本地 100 MHz 晶振 |
| `pcie_rxp/n` | 输入 | 1 | 串行 | 物理 lane 0 接收端 |
| `pcie_txp/n` | 输出 | 1 | 串行 | 物理 lane 0 发送端 |
| `m_axil_aclk` | 输出 | 1 | 时钟 | 固定 250 MHz 用户时钟 |
| `m_axil_aresetn` | 输出 | 1 | `m_axil_aclk` | AXI 复位，同步释放 |
| `m_axil_awaddr` | 输出 | 32 | AXI | BAR 相对字节地址，只实现 bit 11:0 |
| `m_axil_awprot` | 输出 | 3 | AXI | 本版本固定为 `3'b000` |
| `m_axil_awvalid/ready` | 输出/输入 | 1 | AXI | 标准 AXI4-Lite 写地址握手 |
| `m_axil_wdata` | 输出 | 32 | AXI | 小端写数据 |
| `m_axil_wstrb` | 输出 | 4 | AXI | 每字节一个写使能 |
| `m_axil_wvalid/ready` | 输出/输入 | 1 | AXI | 标准 AXI4-Lite 写数据握手 |
| `m_axil_bresp` | 输入 | 2 | AXI | 接受 OKAY/SLVERR/DECERR |
| `m_axil_bvalid/ready` | 输入/输出 | 1 | AXI | 标准 AXI4-Lite 写响应握手 |
| `m_axil_araddr` | 输出 | 32 | AXI | BAR 相对字节地址 |
| `m_axil_arprot` | 输出 | 3 | AXI | 固定为 `3'b000` |
| `m_axil_arvalid/ready` | 输出/输入 | 1 | AXI | 标准 AXI4-Lite 读地址握手 |
| `m_axil_rdata/rresp` | 输入 | 32/2 | AXI | 读数据和读响应 |
| `m_axil_rvalid/ready` | 输入/输出 | 1 | AXI | 标准 AXI4-Lite 读数据握手 |
| `link_up` | 输出 | 1 | Core | 仅当 LTSSM=L0 且 DLL Active 时为高 |
| `link_speed` | 输出 | 2 | Core | `00` Gen1、`01` Gen2、`10` Gen3 |

AXI Master 支持一个未完成读事务和一个未完成写事务。AW 与 W 允许独立握手；
在收到 B 响应前，Master 必须保存二者状态。由于 PCIe Memory Write 是
Posted Request，AXI 写错误只记录到 Sticky 诊断状态。AXI 读错误转换为
Completer Abort Completion。

## PIPE32 功能子集

### MAC 到 PHY

| 信号 | 位宽 | 含义 |
|---|---:|---|
| `pipe_tx_data` | 32 | 四个按线路顺序排列的字节 |
| `pipe_tx_datak` | 4 | Gen1/2 控制字符标志；Gen3 时为零 |
| `pipe_tx_start_block` | 1 | Gen3 Block 起始 |
| `pipe_tx_sync_header` | 2 | Gen3 Sync Header |
| `pipe_tx_elec_idle` | 1 | 请求进入 Electrical Idle |
| `pipe_tx_detect_rx` | 1 | 发起 Receiver Detect |
| `pipe_loopback` | 1 | 请求 PHY Loopback |
| `pipe_power_down` | 2 | PIPE 电源状态请求 |
| `pipe_rate` | 2 | `00` Gen1、`01` Gen2、`10` Gen3 |
| `pipe_rx_polarity` | 1 | 接收极性翻转 |
| `pipe_tx_eq_valid` | 1 | 均衡命令有效 |
| `pipe_tx_eq_mode` | 2 | Preset、Coefficient、Evaluation、保留 |
| `pipe_tx_eq_preset` | 4 | PCIe Preset 编号 |
| `pipe_tx_eq_pre/main/post` | 6/7/6 | 由 M15 定义的均衡系数字段 |

### PHY 到 MAC

| 信号 | 位宽 | 含义 |
|---|---:|---|
| `pipe_clk` | 1 | 随链路速率变化的时钟 |
| `pipe_rx_data` | 32 | 四个按线路顺序排列的字节 |
| `pipe_rx_datak` | 4 | Gen1/2 控制字符标志 |
| `pipe_rx_valid` | 1 | RX 数据和 Sideband 有效 |
| `pipe_rx_status` | 3 | PIPE 接收及 Receiver Detect 状态 |
| `pipe_rx_elec_idle` | 1 | Electrical Idle 指示 |
| `pipe_rx_start_block` | 1 | Gen3 Block 起始 |
| `pipe_rx_sync_header` | 2 | Gen3 接收 Sync Header |
| `pipe_rx_data_valid` | 2 | Gen3 子 Block 有效指示 |
| `pipe_phy_status` | 1 | 请求的 PHY 操作完成 |
| `pipe_rx_eq_done` | 1 | 均衡命令完成 |
| `pipe_rx_eq_preset` | 4 | 评估结果或当前 Preset |
| `pipe_pll_lock` | 1 | 所需 PLL 均已锁定 |
| `pipe_tx_reset_done` | 1 | TX Datapath 已就绪 |
| `pipe_rx_reset_done` | 1 | RX Datapath 已就绪 |

M03 可以在本边界之下增加 GT 私有端口，但不得修改上述端口的功能语义和
位宽。商业 PIPE BFM 通过独立的仿真 Adapter 连接到该功能子集。

## TLP Packet Stream

| 信号 | 相对发送方方向 | 位宽 | 契约 |
|---|---:|---:|---|
| `valid` | 输出 | 1 | 当前 Beat 可用 |
| `ready` | 输入 | 1 | 接收方可以接收当前 Beat |
| `data` | 输出 | 128 | 十六个按 PCIe 线路顺序排列的字节 |
| `keep` | 输出 | 16 | 字节有效标志；除最后一拍外必须全为 1 |
| `sop` | 输出 | 1 | Packet 第一拍 |
| `eop` | 输出 | 1 | Packet 最后一拍 |
| `error` | 输出 | 4 | bit0 Malformed、bit1 Poisoned、bit2 Unsupported、bit3 Internal |

最后一拍的 `keep` 必须从 bit0 开始连续。零长度 Beat、嵌套 SOP、Packet 外
出现数据、没有 EOP 的终止均属于接口协议错误。DLL 到 TL 的 Packet 只包含
TLP Header 和 Payload，Sequence Number 与 LCRC 已被移除。TL 到 DLL 的
Packet 不包含 Sequence Number 与 LCRC，由 DLL 负责添加。

## 配置空间请求/响应

当 `cfg_req_valid && !cfg_req_ready` 时，请求数据必须保持稳定：

- `cfg_req_write`
- `cfg_req_dw_addr[9:0]`
- `cfg_req_be[3:0]`
- `cfg_req_wdata[31:0]`
- `cfg_req_requester_id[15:0]`
- `cfg_req_tag[7:0]`
- `cfg_req_target_bdf[15:0]`

当 `cfg_rsp_valid && !cfg_rsp_ready` 时，响应数据必须保持稳定：

- `cfg_rsp_status[2:0]`：`000` Successful、`001` UR、`100` CA
- `cfg_rsp_rdata[31:0]`
- `cfg_rsp_completer_id[15:0]`
- Requester ID 和 Tag 保存在 TLP Codec 的事务记录中并原样返回

配置访问固定为一个 DWORD，并支持全部四个 Byte Enable。

## BAR0 请求契约

- `bar_addr[11:0]` 是 BAR 相对字节地址。
- Memory Write 支持 1～32 DWORD，对应协商后的 128 Byte MPS。
- Memory Read 支持 1～1024 DWORD；Completion 拆分必须满足 MPS、RCB、
  Byte Count、Lower Address 和 4 KiB 边界要求。
- BAR0 未命中，或 Memory Space Enable 未置位时收到 Memory Request，均进入
  Unsupported Request 路径。
- Posted Write 不产生 PCIe Completion。
- AXI 读侧出现 `SLVERR` 或 `DECERR` 时产生 Completer Abort。

