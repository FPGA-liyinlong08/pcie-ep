# K09 BAR0-to-AXI4-Lite 接口契约

状态：**PASS / K09-BAR-AXIL-v1 接口已冻结**

本接口已经过单模块、K07+K08+K09真实TLP级集成和KU040 OOC验证；实际结果见
`docs/reports/k09-bar-axil-master.md`。

除低有效异步`rst_n`外，全部端口属于`clk=phy_coreclk`（250 MHz）域，使用普通
SystemVerilog端口。所有valid/ready在上升沿同时为1时握手，反压期间Payload和边带
逐位稳定。

## 1. 时钟、复位与配置输入

| 端口 | 方向 | 位宽 | 复位/规则 |
|---|---:|---:|---|
| `clk` | 输入 | 1 | 250 MHz |
| `rst_n` | 输入 | 1 | 异步低有效；同步释放由K01保证 |
| `hot_reset` | 输入 | 1 | 高时不接收新请求，不取消已握手事务 |
| `bar0_base` | 输入 | 32 | K08真实BAR基址，低12位应为0；握手时锁存 |
| `bar0_probe_active` | 输入 | 1 | 1时禁止命中；握手时锁存 |
| `memory_space_enable` | 输入 | 1 | K08 Command.MSE；握手时锁存 |
| `local_completer_id` | 输入 | 16 | K08捕获BDF；握手时锁存 |

MPS不设输入端口：K08-v1已经固定为128 B，且K07-v1单个Completion最大32 DW。
Endpoint Completer的RCB固定为128 B；K08的`rcb_128b`只用于本Function作为Requester
时接收Completion，本项目不主动发Memory Read，K09不连接该端口。

## 2. K07 Memory Request输入

端口名和语义逐位沿用`K07-TLP-CODEC-v1`：

| 端口 | 方向 | 位宽 |
|---|---:|---:|
| `mem_req_valid/ready` | 输入/输出 | 1 |
| `mem_req_write` | 输入 | 1 |
| `mem_req_64bit` | 输入 | 1 |
| `mem_req_poisoned` | 输入 | 1 |
| `mem_req_address` | 输入 | 64 |
| `mem_req_length_dw` | 输入 | 11 |
| `mem_req_first_be/last_be` | 输入 | 4/4 |
| `mem_req_requester_id` | 输入 | 16 |
| `mem_req_tag` | 输入 | 8 |
| `mem_req_tc/attr` | 输入 | 3/3 |

`mem_req_ready=1`只允许出现在`IDLE && rst_n && !hot_reset`。描述符握手后全部字段
被锁存，调用方可在下一拍改变。`mem_req_64bit`仅记录原Header格式，BAR命中由完整
64-bit地址决定；高32位为0的4DW请求允许访问32-bit BAR0。

Write Payload：

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `mem_w_valid/ready` | 输入/输出 | 1 | 只在已接受Write后传输 |
| `mem_w_data` | 输入 | 128 | 首Payload Byte位于`[7:0]` |
| `mem_w_keep` | 输入 | 16 | 最后一拍从bit0连续，其他拍`ffff` |
| `mem_w_last` | 输入 | 1 | 与最后一拍同时为1 |

K09的`mem_w_ready`允许因AXI顺序执行长时间拉低；Drop/Poison路径仍必须持续Drain到
`mem_w_last`。Payload协议错误后不执行后续AXI写。

## 3. K07通用Completion输出

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `cpl_req_valid/ready` | 输出/输入 | 1 | 每个已经拆分好的Cpl/CplD描述符 |
| `cpl_req_has_data/poisoned` | 输出 | 1/1 | SC Read为1/0；UR/CA为0/0 |
| `cpl_req_status` | 输出 | 3 | `000=SC、001=UR、100=CA` |
| `cpl_req_bcm` | 输出 | 1 | 固定0 |
| `cpl_req_byte_count` | 输出 | 13 | SC为剩余字节跨度1～4096；UR/CA为0 |
| `cpl_req_completer_id` | 输出 | 16 | 锁存的K08 BDF |
| `cpl_req_requester_id` | 输出 | 16 | 原Memory Read字段 |
| `cpl_req_tag` | 输出 | 8 | 原Tag |
| `cpl_req_lower_address` | 输出 | 7 | 首包为首有效Byte；后续包固定0 |
| `cpl_req_length_dw` | 输出 | 6 | SC为1～32；UR/CA为0 |
| `cpl_req_tc/attr` | 输出 | 3/3 | 原请求字段 |

Payload：

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `cpl_data_valid/ready` | 输出/输入 | 1 | 描述符握手后开始 |
| `cpl_data` | 输出 | 128 | 首DWORD位于`[31:0]` |
| `cpl_data_keep` | 输出 | 16 | 末拍`000f/00ff/0fff/ffff` |
| `cpl_data_last` | 输出 | 1 | 每个CplD最后一拍 |

Read Request可产生多个Completion，严格先完整发送当前CplD再开始下一Chunk。Posted
Write从不产生描述符或Payload。K09不与K07内部Cfg/UR仲裁；K07冻结的仲裁器负责反压
本接口。

## 4. 32-bit AXI4-Lite Master

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `m_axil_awaddr` | 输出 | 32 | BAR相对DWORD地址，高20位0 |
| `m_axil_awvalid/awready` | 输出/输入 | 1 | AW独立握手 |
| `m_axil_wdata` | 输出 | 32 | PCIe Payload DWORD，不交换Byte |
| `m_axil_wstrb` | 输出 | 4 | First/Last BE或`f` |
| `m_axil_wvalid/wready` | 输出/输入 | 1 | W独立握手 |
| `m_axil_bresp` | 输入 | 2 | `00/01`成功，`10/11`错误 |
| `m_axil_bvalid/bready` | 输入/输出 | 1 | AW/W均握手后接收一次B |
| `m_axil_araddr` | 输出 | 32 | BAR相对DWORD地址，高20位0 |
| `m_axil_arvalid/arready` | 输出/输入 | 1 | 单次Read地址 |
| `m_axil_rdata/rresp` | 输入 | 32/2 | `00/01`成功，`10/11`错误 |
| `m_axil_rvalid/rready` | 输入/输出 | 1 | 每个AR恰好一个R |

K09不发窄传输以外的AXI边带，不允许新的AW/AR覆盖尚未完成的事务。AWADDR/WDATA/
WSTRB可在AW/W分别握手后独立改变，但实现第一版保持到B响应，便于监视器检查。

## 5. 状态与诊断

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `busy` | 输出 | 1 | 非IDLE |
| `ur_pulse` | 输出 | 1 | UR描述符握手事件 |
| `ca_pulse` | 输出 | 1 | CA描述符握手事件 |
| `posted_drop_pulse` | 输出 | 1 | Posted请求确定丢弃事件 |
| `axi_error_pulse` | 输出 | 1 | AXI R/B错误响应事件 |
| `payload_error_pulse` | 输出 | 1 | keep/last与Length不一致 |

饱和32-bit计数端口固定为：

`mem_request_count`、`mem_read_count`、`mem_write_count`、`axi_read_count`、
`axi_write_count`、`sc_completion_count`、`ur_completion_count`、
`ca_completion_count`、`posted_drop_count`、`poisoned_write_count`、
`axi_read_error_count`、`axi_write_error_count`和`payload_protocol_error_count`。

## 6. 复位、反压与延迟

- `rst_n=0`异步将全部valid、ready资格、状态、脉冲和计数清零；缓存数据无定义；
- 复位释放后至少下一上升沿才允许`mem_req_ready=1`；
- Hot Reset不清计数或取消已握手事务，只在高电平期间阻止新的描述符握手；
- 所有输出valid反压期间字段稳定；不存在`valid-ready-valid`组合环；
- 不承诺固定响应拍数；允许AXI与K07无限反压；
- 目标4.000 ns，K09内部无CDC。
