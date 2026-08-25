# Phase E1：Gen3 32-bit PIPE Block接口契约

## 1. RX PIPE输入

| 信号 | 宽度 | 契约 |
|---|---:|---|
| `in_valid` | 1 | 高电平时消费当前word；低电平整拍忽略，可出现在block内部 |
| `start_block` | 1 | 当前有效word为128-bit block的byte 0；Gen3只能从`in_data[0]`开始 |
| `sync_header` | 2 | 仅在`start_block=1`的有效拍锁存；`01=Ordered Set`、`10=Data Stream`，其余非法 |
| `in_data` | 32 | 按word 0、1、2、3顺序拼成`block_data[127:0]` |

`start_block`不得在同一未完成block中重复；若重复，旧block丢弃、产生
`boundary_error`，并以当前word重启组装。

## 2. RX语义输出

| 信号 | 类型 | 契约 |
|---|---|---|
| `block_locked` | 状态 | 收到精确EIEOS后置1；disable、非法header或boundary error清零 |
| `lock_acquired` | 单拍 | `block_locked`从0经EIEOS变1 |
| `lock_lost` | 单拍 | 已锁定状态因结构错误清零 |
| `eieos_valid` | 单拍 | 完整`FF00FF00`×4、SH=`01`的EIEOS |
| `sds_valid` | 单拍 | 已锁定后识别12个`AA`和`E1`标识；末3 byte不固定比较 |
| `ts1_valid/ts2_valid` | 单拍 | 已锁定、完整解扰且字段标识合法的TS |
| `malformed` | 单拍 | 非法header、boundary error或已锁定后的坏/不支持OS |
| `idle_valid` | 单拍 | E1仅保留完整SH=`10`全零block的逻辑idle占位；E5替换为正式framing decoder |

任何TS脉冲都不得在`block_locked=0`时出现。

## 3. TX PIPE输出

| 信号 | 宽度 | 契约 |
|---|---:|---|
| `out_valid` | 1 | 当前32-bit word有效 |
| `start_block` | 1 | 每个4-word block仅word 0为1 |
| `sync_header` | 2 | word 0为`01`，其余拍置0；PHY只在StartBlock拍采样 |
| `out_data` | 32 | EIEOS明文；TS按lane scrambler输出 |
| `os_complete` | 1 | TS的word 3拍，不对EIEOS产生完成脉冲 |

`mode=1/2`分别选择TS1/TS2，`mode=0`关闭发送。E1不为SDS增加TX mode，避免在
Recovery中误发Data Stream边界。

## 4. 复位与切速

- `rst_n=0`或`enable=0`清除RX组装、block lock和LFSR上下文；
- Gen1→Gen3 rate transaction提交后，Gen3 parser从未锁定状态等待新EIEOS；
- Gen3→Gen1 fallback先禁用Gen3 parser，再启用Gen1 parser；两者不得同拍消费；
- `RxDataValid=0`不是错误、timeout或CDR loss证据。
