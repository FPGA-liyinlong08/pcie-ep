# M02 异步 Packet FIFO 接口契约

状态：**PASS / M02-v1 已冻结，K00 KU040 复核通过**  
版本：M02-v1

## 1. 参数

| 参数 | 默认值 | 含义 |
|---|---:|---|
| `LGFIFO` | 9 | 数据和描述符 FIFO 深度为 `2^LGFIFO`，合法范围 4～10 |
| `AFIFO_NFF` | 2 | `afifo.v` Gray 指针同步级数，合法范围 2～4 |
| `RESET_SYNC_STAGES` | 2 | Flush/公共复位同步释放级数，合法范围 2～4 |

Packet Stream 的 `data/keep/error` 位宽固定，不允许参数化。

## 2. 写侧端口

| 端口 | 方向 | 位宽 | 时钟域 | 复位值/规则 |
|---|---:|---:|---|---|
| `s_clk` | 输入 | 1 | 写侧 | 上升沿 |
| `s_rst_n` | 输入 | 1 | 异步置位条件 | 低有效；拉低会清空两侧 |
| `s_valid` | 输入 | 1 | `s_clk` | 与 `s_ready` 握手 |
| `s_ready` | 输出 | 1 | `s_clk` | 复位时为 0；不形成 Valid-Ready 组合环路 |
| `s_data` | 输入 | 128 | `s_clk` | 首字节在 `[7:0]`，透明保存 |
| `s_keep` | 输入 | 16 | `s_clk` | 非末拍必须全 1，末拍允许任意非零连续低位掩码 |
| `s_sop` | 输入 | 1 | `s_clk` | 仅 Packet 首 Beat 为 1 |
| `s_eop` | 输入 | 1 | `s_clk` | 仅 Packet 末 Beat 为 1；单 Beat 包同时 SOP/EOP |
| `s_error` | 输入 | 4 | `s_clk` | 透明保存，不在 M02 解码 |
| `s_packet_count` | 输出 | `LGFIFO+1` | `s_clk` | 未 Claim Packet 的写侧保守上界 |
| `s_overflow` | 输出 | 1 | `s_clk` | Sticky；源协议、超长包或内部 Full 保护异常 |

若 `s_valid=1 && s_ready=0`，源必须保持 `s_valid` 以及所有 Packet Beat 信号不变。
模块允许在 Packet 中间撤销 `s_ready`。

## 3. 读侧端口

| 端口 | 方向 | 位宽 | 时钟域 | 复位值/规则 |
|---|---:|---:|---|---|
| `m_clk` | 输入 | 1 | 读侧 | 上升沿 |
| `m_rst_n` | 输入 | 1 | 异步置位条件 | 低有效；拉低会清空两侧 |
| `m_valid` | 输出 | 1 | `m_clk` | 只有完整 Packet 已提交时才为 1 |
| `m_ready` | 输入 | 1 | `m_clk` | 可在包内随机 Backpressure |
| `m_data` | 输出 | 128 | `m_clk` | `m_valid=0` 时值无约束 |
| `m_keep` | 输出 | 16 | `m_clk` | 与输入逐 Beat 一致 |
| `m_sop` | 输出 | 1 | `m_clk` | 与输入逐 Beat 一致 |
| `m_eop` | 输出 | 1 | `m_clk` | 与输入逐 Beat 一致 |
| `m_error` | 输出 | 4 | `m_clk` | 与输入逐 Beat 一致 |
| `m_packet_count` | 输出 | `LGFIFO+1` | `m_clk` | 未 Claim Packet 的读侧保守下界 |
| `m_underflow` | 输出 | 1 | `m_clk` | Sticky；已提交 Packet 的数据/边界不一致 |

`m_valid=1 && m_ready=0` 时，所有输出 Packet Beat 信号必须保持稳定。

## 4. 公共控制

| 端口 | 方向 | 位宽 | 时钟域 | 规则 |
|---|---:|---:|---|---|
| `flush` | 输入 | 1 | 异步公共控制 | 高有效；同时清空两侧，至少保持一个较慢时钟周期 |

任何复位或 Flush 都可以丢弃已提交 Packet，不产生 Drain 保证。释放 Flush 后：

- `s_ready` 最迟在 `RESET_SYNC_STAGES` 个 `s_clk` 后恢复；
- `m_valid` 保持为 0，直到新 Packet 完成 Commit 并经过 CDC；
- 两个 Packet Count 和 Sticky 错误状态回到 0。

## 5. 延迟和顺序

- EOP 写侧握手前，Packet 的任一 Beat均不得出现在读侧；
- Commit 后的首次 `m_valid` 延迟由两级 `afifo` 指针同步和寄存读出组成，允许
  2～5 个 `m_clk` 周期；
- 包内允许任意长度 Backpressure，不允许丢包、重复或乱序；
- Packet 之间保持输入顺序，不支持优先级旁路。
