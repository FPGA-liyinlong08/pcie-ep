# K05 DLLP 与 Flow Control 接口契约

状态：**K05-FC16-v1 接口与 RTL 已冻结**

除异步低有效 `pipe_rst_n` 外，全部端口属于 `phy_pclk` 域。线路首 Byte 固定在
最低 8 bit。

## 1. K03 MAC 接口

### RX：K03 → K05

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `mac_rx_valid` | 输入 | 1 | valid-only，无 ready，K05 必须逐拍接收 |
| `mac_rx_data` | 输入 | 16 | Byte0 位于 `[7:0]` |
| `mac_rx_keep` | 输入 | 2 | 合法数据拍为 `01/11`，控制 EOP 可为 `00` |
| `mac_rx_sop/eop` | 输入 | 1/1 | K03 冻结 Packet 边界 |
| `mac_rx_is_dllp` | 输入 | 1 | 1 时由 K05 Codec 消费；0 时忽略 |
| `mac_rx_error` | 输入 | 4 | 任一 bit 为 1 时该 DLLP 无效 |

### TX：K05 → K03

| 端口 | 方向 | 位宽 | 复位值/规则 |
|---|---:|---:|---|
| `mac_tx_valid/ready` | 出/入 | 1 | 标准握手；反压时保持其余端口 |
| `mac_tx_data` | 输出 | 16 | 三拍分别为内容0/1、内容2/3、CRC0/1 |
| `mac_tx_keep` | 输出 | 2 | 有效时固定 `11` |
| `mac_tx_sop/eop` | 输出 | 1/1 | 第一/第三拍为 1 |
| `mac_tx_is_dllp` | 输出 | 1 | 有效时固定 1 |
| `mac_tx_bad` | 输出 | 1 | 固定 0，K05 不生成 EDB |

## 2. 解码 DLLP 事件

Codec 对每个收到的 DLLP 产生一拍事件，供 FC Manager 和未来 K06 并行观察：

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `rx_dllp_valid` | 输出 | 1 | 完成结构/CRC检查后的单拍 |
| `rx_dllp_data` | 输出 | 32 | 4 Byte 内容，不含 CRC |
| `rx_dllp_crc_good` | 输出 | 1 | 固定 residue 匹配且无结构错误 |
| `rx_dllp_error` | 输出 | 4 | bit0=长度，bit1=K03 framing，bit2=CRC，bit3=内部 overrun |

无输出 ready。正常物理 DLLP 最短间隔足以完成两拍 CRC 检查；内部 overrun 仍需
显式计数，绝不能静默覆盖。非 FC DLLP 只旁路，不由 K05 修改或丢弃。

## 3. TLP 发送信用接口

类型编码固定为：`00=P`、`01=NP`、`10=Cpl`、`11=非法`。

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `tx_tlp_check_type` | 输入 | 2 | 当前待发送 TLP 类型 |
| `tx_tlp_check_data_credits` | 输入 | 12 | `ceil(payload_bytes/16)` |
| `tx_tlp_credit_available` | 输出 | 1 | Active且Header/Data均足够 |
| `tx_tlp_consume_valid` | 输入 | 1 | TLP不可撤销进入发送路径时单拍 |
| `tx_tlp_consume_type` | 输入 | 2 | 被发送 TLP 类型 |
| `tx_tlp_consume_data_credits` | 输入 | 12 | 被发送 TLP Data Credit |

调用者必须先观察同类型/数量的 `tx_tlp_credit_available=1`，之后才可产生 consume。
非法 consume 不改变计数并增加 FC 协议错误。

远端可用量状态端口：`tx_ph_available/tx_nph_available/tx_cplh_available[7:0]` 和
`tx_pd_available/tx_npd_available/tx_cpld_available[11:0]`。无限信用分别显示全 1。

## 4. 本地 RX Buffer 信用接口

| 端口 | 方向 | 位宽 | 规则 |
|---|---:|---:|---|
| `rx_tlp_consume_valid` | 输入 | 1 | K06 接受一个唯一新 TLP 时单拍 |
| `rx_tlp_consume_type` | 输入 | 2 | P/NP/Cpl |
| `rx_tlp_consume_data_credits` | 输入 | 12 | 该 TLP 占用的 Data Credit |
| `rx_tlp_release_valid` | 输入 | 1 | TL/FIFO 永久释放同一 TLP 时单拍 |
| `rx_tlp_release_type` | 输入 | 2 | 与原 consume 类型一致 |
| `rx_tlp_release_data_credits` | 输入 | 12 | 与原 consume 数量一致 |

Header 每个事件固定消耗/释放 1。consume 与 release 可同拍且可为不同类型；RTL
必须按净变化检查上下界。本地占用状态端口与远端可用量同宽，命名为
`rx_ph_occupied`、`rx_pd_occupied` 等。

## 5. 状态与计数

| 端口 | 方向 | 位宽 | 复位值/规则 |
|---|---:|---:|---|
| `link_up` | 输入 | 1 | K03 LTSSM=L0；为 0 清除 FC 会话 |
| `dll_active` | 输出 | 1 | `fc_state=ACTIVE` |
| `fc_state` | 输出 | 2 | 0=DOWN、1=INIT1、2=INIT2、3=ACTIVE |
| `malformed_dllp_count` | 输出 | 32 | 长度/framing/overrun 饱和计数 |
| `bad_crc_count` | 输出 | 32 | CRC错误 DLLP 饱和计数 |
| `fc_protocol_error_count` | 输出 | 32 | VC/Scale/状态/信用错误饱和计数 |
| `tx_fc_count/rx_fc_count` | 输出 | 32 | 合法发送/接收 FC DLLP 饱和计数 |

`dll_active=0` 时 `tx_tlp_credit_available=0`。离开 L0 清零 FC state、远端信用、本地
occupied 和 dirty；统计计数仅在 `pipe_rst_n=0` 时清零。

## 6. 原始 Codec/Manager 子接口

- Manager RX：`valid + data[31:0] + crc_good + error[3:0]`，无反压；
- Manager TX：`valid/ready + data[31:0]`；
- Codec TX 输入只计算 CRC、序列化，不解释 DLLP Type；
- 任一端口、类型编码、Byte 顺序、信用宽度、无限信用语义或状态转移变化，必须升级
  `K05-FC16-v1` 并重跑 K05 及所有后续回归。
