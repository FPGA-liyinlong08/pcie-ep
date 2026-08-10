# K11-A 离线集成接口冻结

接口版本：`K11A-INTEGRATION-v1`

## 1. 时钟和复位

| 信号 | 域 | 规则 |
|---|---|---|
| `pipe_clk/pipe_rst_n` | PHY链路域 | DLL及MAC Packet接口；复位异步置位、同步释放 |
| `core_clk/core_rst_n` | 250 MHz Core域 | Codec、配置空间、BAR及Demo |
| `hot_reset_pipe` | PIPE域单拍 | 经事件同步后复位配置寄存器，不复位全局时钟域 |

两个FIFO方向都以`pipe_rst_n && core_rst_n`作为公共异步清空条件，避免单侧指针保留。
链路状态与DLL诊断使用原子快照握手进入Core域；这些寄存器是低频诊断视图，不承诺
固定跨域延迟。Hot Reset相邻脉冲至少间隔两个`core_clk`周期。

## 2. MAC Packet接口

沿用K03/K06冻结的16-bit接口：`valid/ready/data[15:0]/keep[1:0]/sop/eop/
is_dllp/error`。线路先出现的Byte位于`data[7:0]`。RX方向MAC无反压能力，DLL内部槽
必须吸收完整Frame；TX方向允许逐拍反压且stall期间全部字段稳定。

## 3. 跨域TLP接口

Packet数据沿用M02 128-bit契约。TX侧额外输入`type[1:0]`和
`data_credits[11:0]`，仅在SOP握手采样；目标侧在同一Packet的所有拍保持该值。
RX信用归还事件为`valid/ready/type[1:0]/data_credits[11:0]`，每个已由K07消费的Packet
严格产生一个事件。

## 4. 配置和BAR

K07～K10的普通端口、字段编码、字节序和响应规则保持不变。Demo AXI-Lite是内部
连接，不暴露板外总线。状态输出至少包含`link_up`、`dll_active`、`ltssm_state`、
`captured_bdf`、`bar0_base`及CDC sticky error。

## 5. 延迟

- Packet在EOP写入后才对目标域可见；CDC延迟不作固定周期保证；
- TX首拍还需等待对应元数据可见；
- RX信用释放允许被事件FIFO反压；
- 不允许跨时钟组合路径或组合`valid-ready-valid`环路。
