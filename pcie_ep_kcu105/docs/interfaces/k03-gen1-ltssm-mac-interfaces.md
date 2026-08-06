# K03 Gen1 x1 LTSSM/MAC 接口契约

状态：**K03-MAC16-v1 接口与 RTL 已冻结**

时钟域：除异步低有效 `pipe_rst_n` 外，全部信号属于 `phy_pclk` 域。

## 1. PHY 接收与发送

| 端口 | 方向 | 位宽 | 复位值/规则 |
|---|---:|---:|---|
| `phy_pclk` | 输入 | 1 | Gen1 固定 125 MHz |
| `pipe_rst_n` | 输入 | 1 | 低有效，异步置位、同步释放 |
| `phy_rxdata` | 输入 | 32 | Gen1 只采样低 16 bit |
| `phy_rxdatak` | 输入 | 2 | 对应低、次低两个字节 |
| `phy_rxdata_valid` | 输入 | 1 | 为 1 时 RX data/datk 有效 |
| `phy_rxvalid` | 输入 | 1 | CDR 数据有效；接收条件为两者同时为 1 |
| `phy_phystatus` | 输入 | 1 | Detect/Power 操作完成脉冲 |
| `phy_rxelecidle` | 输入 | 1 | RX Electrical Idle |
| `phy_rxstatus` | 输入 | 3 | Detect 成功编码 `3'b011` |
| `phy_txdata` | 输出 | 32 | Gen1 高 16 bit 固定 0，先上线字节在 `[7:0]` |
| `phy_txdatak` | 输出 | 2 | 每个低 16 bit 字节的 K-code 标记 |
| `phy_txdata_valid` | 输出 | 1 | 有效 Symbol 期间为 1 |
| `phy_txstart_block` | 输出 | 1 | Gen1 固定 0 |
| `phy_txsync_header` | 输出 | 2 | Gen1 固定 0 |

### MAC → PHY 控制

| 端口 | 位宽 | 复位值 | K03 规则 |
|---|---:|---:|---|
| `phy_txdetectrx` | 1 | 0 | 只在 Detect.Active 为 1 |
| `phy_txelecidle` | 1 | 1 | Detect/HotReset 为 1，训练与 L0 为 0 |
| `phy_txcompliance` | 1 | 0 | 固定 0 |
| `phy_rxpolarity` | 1 | 0 | 固定 0 |
| `phy_powerdown` | 2 | `2'b10` | Detect/HotReset=P1，其余=P0 |
| `phy_rate` | 2 | `2'b00` | K03 永久 Gen1 |
| `phy_txmargin` | 3 | 0 | 固定 0 |
| `phy_txswing` | 1 | 0 | 固定 0 |
| `phy_txdeemph` | 1 | 0 | 固定 0 |
| `phy_txeq_ctrl/preset/coeff` | 2/4/6 | 0 | 固定 0，K12 实现 |
| `phy_rxeq_ctrl/txpreset` | 2/4 | 0 | 固定 0，K12 实现 |
| `as_mac_in_detect` | 1 | 1 | Detect.Quiet/Active 为 1 |
| `as_cdr_hold_req` | 1 | 0 | 固定 0 |

## 2. DLL → MAC TX Packet Stream

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `tx_pkt_valid` | 输入 | 1 | 与 ready 握手；valid 必须保持到握手 |
| `tx_pkt_ready` | 输出 | 1 | L0 且 TX Packet Buffer 有空间时为 1 |
| `tx_pkt_data` | 输入 | 16 | 线路先到字节位于 `[7:0]` |
| `tx_pkt_keep` | 输入 | 2 | 非末拍必须 `11`；末拍为 `01` 或 `11` |
| `tx_pkt_sop` | 输入 | 1 | 第一拍且仅第一拍为 1 |
| `tx_pkt_eop` | 输入 | 1 | 最后一拍且仅最后一拍为 1 |
| `tx_pkt_is_dllp` | 输入 | 1 | SOP 采样；0=TLP/STP，1=DLLP/SDP |
| `tx_pkt_bad` | 输入 | 1 | EOP 采样；1 使用 EDB，0 使用 END |

约束：一个 Packet 最多 160 Byte、至少 1 Byte；只允许单 Packet 排队。输入端可以在
Packet 内产生空拍，因为 MAC 在完整接收 EOP 后才开始发送。协议错或超长 Packet
整包丢弃并增加 `frame_error_count`。从 EOP 握手到第一个 delimiter 的允许延迟为
1～2 个 `phy_pclk`。

## 3. MAC → DLL RX Framed Stream

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `rx_pkt_valid` | 输出 | 1 | 有数据或控制结束事件时为 1，无 ready |
| `rx_pkt_data` | 输出 | 16 | 去除 delimiter 后的线路字节序 |
| `rx_pkt_keep` | 输出 | 2 | `00/01/11`；`00` 只允许用于独立 EOP 控制拍 |
| `rx_pkt_sop` | 输出 | 1 | STP/SDP 后第一个输出拍 |
| `rx_pkt_eop` | 输出 | 1 | END/EDB 所在输出拍；可与 `keep=00` 同时出现 |
| `rx_pkt_is_dllp` | 输出 | 1 | 从 Start 到 End 保持 Packet 类型 |
| `rx_pkt_error` | 输出 | 4 | bit0=EDB，bit1=非法 K，bit2=嵌套 Start，bit3=链路离开 L0 |

RX 物理接口不可反压，后续 DLL 必须接受每个 `rx_pkt_valid` 拍。一个开始 marker 位于
Symbol 0 时，同拍 Symbol 1 的首数据字节以 `keep=01,sop=1` 输出；END 位于 Symbol 0
时输出 `keep=00,eop=1`。这是 MAC↔DLL 专用契约，不是 128-bit TLP Packet Stream。

## 4. 控制与状态

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `link_disable` | 输入 | 1 | 高电平使链路回 Detect.Quiet |
| `hot_reset_req` | 输入 | 1 | 单拍/电平均可，进入 HotReset 后自动消费 |
| `force_recovery` | 输入 | 1 | L0 时进入 Recovery.RcvrLock |
| `ltssm_state` | 输出 | 6 | 编码见下表 |
| `link_up` | 输出 | 1 | 仅 LTSSM=L0；不表示 DLL Active |
| `negotiated_width` | 输出 | 3 | L0/Recovery 固定 1，否则 0 |
| `negotiated_speed` | 输出 | 2 | 固定 `00`=Gen1 |
| `link_number` | 输出 | 8 | Configuration 捕获，复位为 PAD=`F7` |
| `rx_ts_count` | 输出 | 5 | 当前状态连续有效 TS/Idle 计数，状态变化清零 |
| `training_error_count` | 输出 | 32 | 饱和计数 |
| `timeout_count` | 输出 | 32 | 饱和计数 |
| `frame_error_count` | 输出 | 32 | 饱和计数 |
| `hot_reset_seen` | 输出 | 1 | 进入 HotReset 的单拍脉冲 |

状态编码：

| 值 | 状态 |
|---:|---|
| 0 | Detect.Quiet |
| 1 | Detect.Active |
| 2 | Polling.Active |
| 3 | Polling.Configuration |
| 4 | Configuration.Linkwidth.Start |
| 5 | Configuration.Linkwidth.Accept |
| 6 | Configuration.Lanenum.Wait |
| 7 | Configuration.Lanenum.Accept |
| 8 | Configuration.Complete |
| 9 | Configuration.Idle |
| 10 | L0 |
| 11 | Recovery.RcvrLock |
| 12 | Recovery.RcvrCfg |
| 13 | Recovery.Idle |
| 14 | HotReset |

所有状态输出和 Packet 输出均为寄存器或只依赖寄存状态的组合逻辑；禁止形成
`valid-ready-valid` 组合环路。计数器达到全 1 后饱和，不回绕。
