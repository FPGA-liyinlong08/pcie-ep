# K07 TLP Codec 接口契约

状态：**K07-TLP-CODEC-v1 接口冻结**

RTL端口名`clk`连接系统`phy_coreclk`，端口名`rst_n`连接系统`core_rst_n`。除异步
低有效`rst_n`外，所有端口属于`clk`（250 MHz）域，使用普通SystemVerilog端口。
`valid/ready`在时钟上升沿同时为1时完成传输；反压期间所有Payload和边带必须稳定。

## 1. DLL/FIFO Packet Stream

RX输入和TX输出继续使用`128-bit Packet Stream v1`：

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `rx_tlp_valid/ready` | 入/出 | 1 | 包内允许反压 |
| `rx_tlp_data` | 入 | 128 | 首线路Byte在`[7:0]` |
| `rx_tlp_keep` | 入 | 16 | 非末拍`ffff`；末拍从bit0连续 |
| `rx_tlp_sop/eop` | 入 | 1/1 | 第一拍/最后一拍 |
| `rx_tlp_error` | 入 | 4 | 任一bit使整包Malformed |
| `tx_tlp_valid/ready` | 出/入 | 1 | 完整Cpl/CplD，不含Sequence/LCRC |
| `tx_tlp_data` | 出 | 128 | 首线路Byte在`[7:0]` |
| `tx_tlp_keep` | 出 | 16 | 同上 |
| `tx_tlp_sop/eop` | 出 | 1/1 | 同上 |
| `tx_tlp_error` | 出 | 4 | K07固定为0 |

TX首拍附加元数据：

| 端口 | 位宽 | 规则 |
|---|---:|---|
| `tx_tlp_type` | 2 | 固定`2'b10`（Cpl） |
| `tx_tlp_data_credits` | 12 | `ceil(CplD Payload Byte/16)`；Cpl为0 |

元数据在整个Packet期间保持稳定，K11在TX Packet commit时写入独立异步元数据FIFO。

RX信用释放：

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `rx_release_valid/ready` | 出/入 | 1 | 每个完整输入Packet恰好一次，支持反压 |
| `rx_release_type` | 出 | 2 | `00=P、01=NP、10=Cpl` |
| `rx_release_data_credits` | 出 | 12 | 与K06首次RX消耗值完全一致 |

`rx_release_*`是K07 core侧简称；K11 CDC适配器将其映射到K06冻结的
`rx_tlp_release_*`脉冲接口。

## 2. 本地Completer ID

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `local_completer_id` | 入 | 16 | 内部UR/CA使用；K07单测由BFM驱动，K08以后驱动捕获BDF |

## 3. 配置空间请求/响应

请求严格沿用M00冻结契约：

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `cfg_req_valid/ready` | 出/入 | 1 | 最多一个Outstanding |
| `cfg_req_write` | 出 | 1 | 0=CfgRd0，1=CfgWr0 |
| `cfg_req_dw_addr` | 出 | 10 | 配置空间DWORD地址 |
| `cfg_req_be` | 出 | 4 | First BE |
| `cfg_req_wdata` | 出 | 32 | Cfg Write Payload，数值小端 |
| `cfg_req_requester_id` | 出 | 16 | 原请求Requester BDF |
| `cfg_req_tag` | 出 | 8 | 仅8-bit Tag |
| `cfg_req_target_bdf` | 出 | 16 | 原请求目标BDF，不由K07匹配 |

响应：

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `cfg_rsp_valid/ready` | 入/出 | 1 | 仅在等待Cfg响应时接受 |
| `cfg_rsp_status` | 入 | 3 | `000=SC、001=UR、010=CRS、100=CA` |
| `cfg_rsp_rdata` | 入 | 32 | SC Cfg Read返回数据 |
| `cfg_rsp_completer_id` | 入 | 16 | Completion中的Completer ID |

SC Read编码为CplD、Length=1、Byte Count=4、Lower Address=0；SC Write编码为无数据
Cpl。非SC一律编码为无数据Cpl并保持Requester ID、Tag、TC、Attr。

## 4. Memory请求接口

描述符：

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `mem_req_valid/ready` | 出/入 | 1 | 描述符握手先于Write Payload |
| `mem_req_write` | 出 | 1 | 0=Memory Read，1=Memory Write |
| `mem_req_64bit` | 出 | 1 | 原TLP为4DW地址格式 |
| `mem_req_poisoned` | 出 | 1 | 原TLP EP位 |
| `mem_req_address` | 出 | 64 | DWORD对齐地址，低2位0 |
| `mem_req_length_dw` | 出 | 11 | 逻辑1～1024；Wire 0映射1024 |
| `mem_req_first_be/last_be` | 出 | 4/4 | 原样输出 |
| `mem_req_requester_id` | 出 | 16 | Requester BDF |
| `mem_req_tag` | 出 | 8 | Tag |
| `mem_req_tc` | 出 | 3 | Traffic Class |
| `mem_req_attr` | 出 | 3 | `{IDO,RO,NS}`对应原Header三位 |

Memory Write Payload：

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `mem_w_valid/ready` | 出/入 | 1 | 仅Write存在 |
| `mem_w_data` | 出 | 128 | Payload首Byte在`[7:0]` |
| `mem_w_keep` | 出 | 16 | 末拍连续keep |
| `mem_w_last` | 出 | 1 | 最后一个Payload拍 |

K07不输出BAR号或BAR相对地址，不检查MSE，也不生成Memory Read Completion。

## 5. 入站Completion解码接口

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `rx_cpl_valid/ready` | 出/入 | 1 | Cpl/CplD描述符 |
| `rx_cpl_has_data` | 出 | 1 | 0=Cpl，1=CplD |
| `rx_cpl_poisoned` | 出 | 1 | EP位，仅CplD允许 |
| `rx_cpl_status` | 出 | 3 | SC/UR/CRS/CA |
| `rx_cpl_bcm` | 出 | 1 | Byte Count Modified |
| `rx_cpl_byte_count` | 出 | 13 | 逻辑1～4096；Wire 0映射4096；无数据Cpl可为0 |
| `rx_cpl_completer_id/requester_id` | 出 | 16/16 | Header字段 |
| `rx_cpl_tag` | 出 | 8 | Tag |
| `rx_cpl_lower_address` | 出 | 7 | Lower Address |
| `rx_cpl_length_dw` | 出 | 6 | 无数据为0；CplD为1～32 |
| `rx_cpl_tc/attr` | 出 | 3/3 | 原Header字段 |

Payload使用`rx_cpl_data_valid/ready/data[127:0]/keep[15:0]/last`，语义与Memory
Write Payload相同。K07仍将其标为Unexpected Completion统计，但不自动丢掉解码结果。

CplD必须满足`1 <= Byte Count <= 4096`，并满足：

```text
Byte Count + Lower Address[1:0] + 3 >= 4 * LengthDW
```

无数据Cpl的Wire Length固定0，Byte Count允许0～4096；Wire Byte Count为0时，
`rx_cpl_byte_count`输出0而不是强行解释为4096，非零值原样输出。CplD的Wire 0才按
逻辑4096解释。

## 6. 出站通用Completion接口

供K09提供单个已经拆分好的Completion Packet：

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `cpl_req_valid/ready` | 入/出 | 1 | Completion描述符 |
| `cpl_req_has_data/poisoned` | 入 | 1/1 | Cpl/CplD及EP |
| `cpl_req_status` | 入 | 3 | SC/UR/CRS/CA |
| `cpl_req_bcm` | 入 | 1 | BCM |
| `cpl_req_byte_count` | 入 | 13 | 0～4096；4096在线路编码为0 |
| `cpl_req_completer_id/requester_id` | 入 | 16/16 | Header字段 |
| `cpl_req_tag` | 入 | 8 | Tag |
| `cpl_req_lower_address` | 入 | 7 | Lower Address |
| `cpl_req_length_dw` | 入 | 6 | Cpl=0；CplD=1～32 |
| `cpl_req_tc/attr` | 入 | 3/3 | Header字段 |

Payload输入为`cpl_data_valid/ready/data[127:0]/keep[15:0]/last`。描述符必须先握手；
CplD Payload Byte数必须精确等于`4*length_dw`，Byte Count必须满足上述关系；其
Byte Count只允许1～4096。无数据Cpl允许Byte Count 0～4096。非SC Completion不得
携带Payload。非法有数据描述符被握手后进入drain，必须消费到`cpl_data_last`，只增加
一次`tx_protocol_error_count`且绝不发送半包。

## 7. 诊断和统计

每个错误事件输出一拍脉冲，并附带最近一次可用Header上下文：

| 端口 | 位宽 | 说明 |
|---|---:|---|
| `malformed_pulse` | 1 | 结构/长度/保留字段错误 |
| `unsupported_pulse` | 1 | 格式完整但功能不支持 |
| `poisoned_pulse` | 1 | 收到EP TLP |
| `unexpected_cpl_pulse` | 1 | 收到合法Cpl/CplD |
| `error_fmt_type` | 8 | `{Fmt,Type}`原始首Byte |
| `error_requester_id` | 16 | Header可用时的Requester ID，否则0 |
| `error_tag` | 8 | Header可用时的Tag，否则0 |

饱和32-bit计数为：`rx_packet_count`、`cfg_request_count`、`mem_request_count`、
`rx_completion_count`、`tx_completion_count`、`ur_completion_count`、
`malformed_count`、`unsupported_count`、`poisoned_count`、
`unexpected_completion_count`和`tx_protocol_error_count`。

计数时点冻结为：RX Packet在`PARSE`进入时；Cfg/Memory/RX Cpl在对应描述符握手时；
TX Completion在TX EOP握手时；错误在分类或非法TX描述符握手时。所有计数到全1后
保持全1。

## 8. 复位和时序约束

- `core_rst_n=0`异步撤销全部`valid`、状态、长度和统计，Packet RAM内容无定义；
- `core_rst_n`只能在`phy_coreclk`同步释放（由K01保证）；
- 复位后至少下一上升沿才允许任何输出`valid`；
- 所有反压接口均禁止组合`valid-ready-valid`环路；
- 目标时钟4.000 ns，K07内部无CDC。
