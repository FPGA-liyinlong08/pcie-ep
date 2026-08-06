# K06 ACK/NAK 与 Replay 接口契约

状态：**K06-REPLAY128-v1 接口与 RTL 已冻结**

除异步低有效 `pipe_rst_n` 外，全部端口属于 `phy_pclk` 域。

## 1. K03 MAC RX：K03 → K06

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `mac_rx_valid` | 输入 | 1 | valid-only，无 ready，必须逐拍接收 |
| `mac_rx_data` | 输入 | 16 | 线路首 Byte 在 `[7:0]` |
| `mac_rx_keep` | 输入 | 2 | `01/11`；独立 EOP 控制拍允许 `00` |
| `mac_rx_sop/eop` | 输入 | 1/1 | K03 已冻结边界 |
| `mac_rx_is_dllp` | 输入 | 1 | 0时由Replay RX消费，1时忽略 |
| `mac_rx_error` | 输入 | 4 | 任一bit使当前TLP无效 |

## 2. K06 TLP TX：K06 → MAC Packet Arbiter

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `mac_tx_valid/ready` | 出/入 | 1 | 标准握手；反压时所有边带稳定 |
| `mac_tx_data` | 输出 | 16 | Sequence、TLP、LCRC 的线路顺序 |
| `mac_tx_keep` | 输出 | 2 | 有效时固定 `11` |
| `mac_tx_sop/eop` | 输出 | 1/1 | Sequence首拍/第二拍LCRC |
| `mac_tx_is_dllp` | 输出 | 1 | 固定0 |
| `mac_tx_bad` | 输出 | 1 | 固定0；K06不发送Nullified TLP |

## 3. TL 128-bit Packet Stream

TX输入和RX输出均使用冻结的 `valid/ready/data[127:0]/keep[15:0]/sop/eop/error[3:0]`。

TX附加首拍元数据：

| 端口 | 位宽 | 规则 |
|---|---:|---|
| `tx_tlp_type` | 2 | `00=P、01=NP、10=Cpl、11=非法`，SOP采样 |
| `tx_tlp_data_credits` | 12 | `ceil(payload_bytes/16)`，SOP采样 |

- TX 原始 TLP 不含 Sequence/LCRC，长度12～144 Byte且按DWORD对齐；
- RX 已去除 Sequence/LCRC，只输出完整、唯一、LCRC正确的 TLP；
- RX `error` 固定0，错误物理 TLP只更新统计并发送NAK；
- 包内允许Backpressure；stall时 valid、data、keep、sop、eop、error全部稳定。

## 4. K05 DLLP 事件与 ACK/NAK Raw DLLP

输入来自 K05 Codec：

| 端口 | 位宽 | 规则 |
|---|---:|---|
| `rx_dllp_valid` | 1 | 每个已检查 DLLP 一拍 |
| `rx_dllp_data` | 32 | 四个内容Byte，不含CRC |
| `rx_dllp_crc_good` | 1 | CRC16正确 |
| `rx_dllp_error` | 4 | 任一bit时忽略ACK/NAK |

ACK/NAK事件先寄存一拍后修改Replay Window；相邻事件按累计顺序处理，不改变Raw
DLLP字段语义。

ACK/NAK输出：`tx_ack_dllp_valid/ready/data[31:0]`。Raw DLLP一次握手传输4 Byte，
不含CRC；K05 Codec负责CRC和16-bit序列化。`data[7:0]`为Type，ACK=`8'h00`、
NAK=`8'h10`；Sequence为`{data[19:16],data[31:24]}`。

## 5. K05 Flow Control 连接

TX信用：

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `tx_fc_check_type/data_credits` | 输出 | 2/12 | 首次待发送队首项 |
| `tx_fc_credit_available` | 输入 | 1 | K05 Header/Data均足够 |
| `tx_fc_consume_valid/type/data_credits` | 输出 | 1/2/12 | Sequence首拍首次握手单拍；Replay不产生 |

`tx_fc_credit_available`在发送器内采样一拍。查询期间队首元数据保持稳定，采样为1
后才启动该TLP；DLL只有一个TLP发送者，不存在其他本地请求抢占该信用。

RX本地信用：`rx_fc_consume_valid/type/data_credits` 在唯一新TLP完成校验时输出一拍。
TL最终释放通过冻结的 K05 `rx_tlp_release_*` 接口直接返回 FC Manager，不经过Replay。

## 6. 状态与错误计数

| 端口 | 位宽 | 含义 |
|---|---:|---|
| `next_tx_seq/next_rx_seq` | 12 | 下一个首次发送/期望接收Sequence |
| `last_acked_seq` | 12 | TX最近累计ACK，初值`fff` |
| `replay_occupancy` | `clog2(REPLAY_DEPTH+1)` | 已发送未ACK项数 |
| `replay_active` | 1 | 正在执行NAK/Timer重放 |
| `replay_fatal` | 1 | 连续Timer Replay超限，离开DLL Active清除 |
| `recovery_req` | 1 | 超限时单拍，K11连接K03 `force_recovery` |
| `tx_tlp_count/rx_tlp_count` | 32 | 首次发送/唯一接收计数 |
| `ack_tx_count/nak_tx_count` | 32 | 已握手ACK/NAK计数 |
| `replay_count` | 32 | 每个重放TLP计数 |
| `lcrc_error_count` | 32 | LCRC/EDB/malformed接收错误 |
| `duplicate_tlp_count` | 32 | 重复且未提交的TLP |
| `sequence_error_count` | 32 | 未来/乱序Sequence |
| `ack_error_count` | 32 | 非法未来/陈旧ACK/NAK |
| `buffer_error_count` | 32 | TX协议、Replay满或RX槽溢出 |

统计达到全1后饱和；`dll_active=0`时数据接口valid均为0、TL TX ready为0。

## 7. 仲裁器接口

- `pcie_dllp_tx_arbiter`：两组`valid/ready/data[31:0]`输入，ACK/NAK高优先级，
  输出一组Raw DLLP；一次4 Byte握手即一个完整DLLP；
- `pcie_dll_mac_tx_arbiter`：DLLP和TLP两组K03 16-bit Packet Stream输入，DLLP在
  空闲边界优先，选择后锁定到EOP握手；
- 仲裁期间不允许中途切换，不允许形成组合valid-ready-valid环路。

任何端口、Byte顺序、Sequence语义、Buffer深度或Timer默认值改变，必须升级
`K06-REPLAY128-v1` 并重跑K04～K06及后续回归。
