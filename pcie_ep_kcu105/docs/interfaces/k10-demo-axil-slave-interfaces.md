# K10 Demo AXI4-Lite Slave 接口契约

状态：**PASS / K10-DEMO-AXIL-v1 接口已冻结**

除低有效异步`rst_n`外，全部端口属于`clk=phy_coreclk` 250 MHz域。端口使用普通
SystemVerilog信号；valid/ready在上升沿同时为1时完成一次握手。

## 1. AXI4-Lite Slave

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `clk/rst_n` | 输入 | 1/1 | 250 MHz；PERST#异步置位、上游同步释放 |
| `s_axil_awaddr` | 输入 | 32 | Byte地址，合法范围`0x000～0xffc`且DWORD对齐 |
| `s_axil_awvalid/awready` | 输入/输出 | 1 | AW独立握手，内部保存一个地址 |
| `s_axil_wdata/wstrb` | 输入 | 32/4 | 小端DWORD；WSTRB bit0对应最低Byte |
| `s_axil_wvalid/wready` | 输入/输出 | 1 | W独立握手，内部保存一个数据/选通 |
| `s_axil_bresp` | 输出 | 2 | `00=OKAY`、`11=DECERR` |
| `s_axil_bvalid/bready` | 输出/输入 | 1 | 响应反压期间BRESP稳定 |
| `s_axil_araddr` | 输入 | 32 | 与AW地址规则相同 |
| `s_axil_arvalid/arready` | 输入/输出 | 1 | 单Outstanding Read |
| `s_axil_rdata/rresp` | 输出 | 32/2 | 错误读数据固定0；`00=OKAY`、`11=DECERR` |
| `s_axil_rvalid/rready` | 输出/输入 | 1 | 反压期间RDATA/RRESP稳定 |

AW与W允许同拍或相隔任意拍、任意先后到达。模块不得在只收到其中一个通道时产生写
副作用。B握手后下一拍才重新接收新AW/W。AR握手到RVALID允许1～2拍固定实现延迟；
R握手前`arready=0`。

## 2. 状态输入

| 端口 | 位宽 | 映射 |
|---|---:|---|
| `link_up` | 1 | `0x008[0]` |
| `link_speed` | 2 | `0x008[2:1]`，0/1/2表示Gen1/2/3 |
| `ltssm_state` | 6 | `0x008[13:8]` |
| `dll_active` | 1 | `0x00c[0]` |
| `dll_state` | 4 | `0x00c[7:4]` |

状态在AR握手时采样到RDATA，不要求输入跨读事务保持。

## 3. 诊断计数输入

以下输入均为32-bit，只读，按地址依次映射：

| 地址 | 输入端口 |
|---:|---|
| `0x010` | `rx_bad_symbol_count` |
| `0x014` | `ltssm_retrain_count` |
| `0x018` | `dll_lcrc_error_count` |
| `0x01c` | `dll_nak_count` |
| `0x020` | `dll_replay_count` |
| `0x024` | `dll_replay_timeout_count` |
| `0x028` | `tl_malformed_count` |
| `0x02c` | `tl_unsupported_count` |
| `0x030` | `bar_ur_count` |
| `0x034` | `bar_ca_count` |
| `0x038` | `bar_axi_error_count` |
| `0x03c` | `bar_payload_error_count` |

计数由各生产模块维护，K10不复位、不饱和、不做跨时钟同步；K11负责只连接已同步到
`phy_coreclk`的值。

## 4. 复位和字节序

- `rst_n=0`立即撤销AW/W pending、BVALID、RVALID并清零Scratch；
- 测试RAM故意不复位，复位后的内容无定义；
- 签名、版本和只读状态不受WSTRB写入影响；
- AXI最低地址Byte对应`WDATA[7:0]`和`WSTRB[0]`。
