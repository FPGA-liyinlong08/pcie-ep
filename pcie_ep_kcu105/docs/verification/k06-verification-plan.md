# K06 ACK/NAK 与 Replay RTL 前验证计划

状态：**K06-v1 计划已执行；全部当前门禁 PASS**

接口版本：`K06-REPLAY128-v1`

## 1. 参考模型与平台

```text
TL TX Driver → Replay DUT → MAC TLP Monitor → Link Partner
                    ↑              │              │
Credit Model ───────┘              └── ACK/NAK/LCRC注错
TL RX Scoreboard ← RX Frame Driver ←──────────────┘
```

参考来源：

1. Python `zlib.crc32()`逐Byte计算 Sequence+TLP LCRC；
2. `cocotbext-pcie 0.2.16 Dllp.pack_crc()/unpack_crc()`检查ACK/NAK；
3. 独立Python/C++模型维护12-bit Sequence、累计ACK、Ring Window和Timer；
4. K04固定LCRC residue `32'hDEBB20E3`，不读取DUT内部CRC状态。

MAC Monitor重建 Sequence/TLP/LCRC，随机化 `ready` 并检查stall稳定。Link Partner可
丢ACK、发NAK、重复TLP、改变Sequence、破坏单bit LCRC或用EDB结束。

## 2. 测试平台先行与错误 Stub

先提供同顶层端口的错误 Stub：TX始终使用Sequence 0、收到任意ACK立即清空全部
Replay项、RX不检查LCRC。连续发送两个TLP并只ACK第一个的用例必须失败，JUnit必须
包含failure；外层确认失败后才输出：

```text
K06_CHECKER_SELFTEST_PASS
```

## 3. Directed Case

| 编号 | 用例 | 检查点 |
|---|---|---|
| K06-D001 | 复位/DLL下降 | 清空会话和Window，统计保留，接口valid/ready正确 |
| K06-D002 | TX单包 | Sequence Byte顺序、TLP透明、LCRC与zlib一致、消费一次信用 |
| K06-D003 | TX多包与反压 | 递增Sequence，完整锁包，stall期间输出稳定 |
| K06-D004 | 累计ACK | 只释放ACK Sequence及以前项，不释放未ACK项 |
| K06-D005 | 重复/未来/陈旧ACK | 重复无副作用，非法值忽略并计错 |
| K06-D006 | NAK Replay | 从NAK累计点之后开始，Byte串完全一致，不重复消费信用 |
| K06-D007 | ACK丢失/Timer | 超时重放全部Outstanding，ACK后停止 |
| K06-D008 | Replay超限 | fatal置位并产生单拍recovery_req，link下降清除 |
| K06-D009 | RX正常 | 去除Sequence/LCRC，唯一提交，信用消费一次，延迟累计ACK |
| K06-D010 | RX重复 | 不重复提交/消费，立即ACK最新累计Sequence |
| K06-D011 | RX未来Sequence | 不提交，NAK `expected-1`，合法后续可恢复 |
| K06-D012 | 坏LCRC/EDB/malformed | 不提交、不推进Sequence，NAK并分类计数 |
| K06-D013 | RX槽并发 | 接收写入与CRC/TL反压并行，顺序不变，槽满显式计错 |
| K06-D014 | ACK合并和NAK优先 | Timer内多个包仅发最新ACK，NAK不被ACK覆盖 |
| K06-D015 | DLLP Raw仲裁 | ACK/NAK优先于FC且不丢请求 |
| K06-D016 | MAC Packet仲裁 | 只在边界选择，Packet内不切换 |
| K06-D017 | 最小FC分类 | P/NP/Cpl及0/1/8个Data Credit正确 |
| K06-D018 | Sequence完整回绕 | `ffe、fff、000、001`及全部4096值无歧义 |

## 4. 随机与百万事件

- cocotb固定种子`20260806`，至少10,000个随机Packet/ACK/NAK/错误事件；
- Packet长度覆盖12～144 Byte、所有合法末拍keep和随机MAC/TL反压；
- Native Verilator执行至少1,048,576个独立TX/ACK事务，逐包比对Sequence、TLP、
  LCRC、Occupancy和累计ACK，并周期插入NAK重放；
- cocotb Directed负责累计多项Window、Timer Replay、ACK丢失、错误恢复和反压；
- 强制至少256次完整12-bit回绕，并覆盖Window跨物理末端；
- Scoreboard保证TL只收到一次有效TLP，Replay线上Byte与首次发送逐Byte一致。

## 5. Assertion 与覆盖

必须检查：

- Outstanding永不超过`REPLAY_DEPTH`，Window项不被未覆盖ACK释放；
- Replay不产生FC consume，首次发送恰好产生一次；
- `next_tx_seq-next_rx_seq`等12-bit计数只在合法事件变化；
- 坏LCRC、重复和未来TLP均不提交TL；
- ACK/NAK数据与期望累计Sequence一致；
- RX/TX Packet Stream stall稳定，SOP/EOP/keep合法；
- link下降后不发送旧会话Packet或DLLP；
- Buffer满和协议错误必须显式计数，不得静默覆盖。

覆盖点包括ACK/NAK、首次/NAK/Timer Replay、P/NP/Cpl、有限信用stall、全部Sequence
边界、Window首尾回绕、LCRC单bit错误、重复/未来序列、ACK合并、NAK优先、TL/MAC
反压、RX槽满和Replay fatal/recovery。

## 6. 静态与通过标准

- 错误Stub自检PASS；
- Verilator lint 0 Error，普通Warning必须修复或精确登记；
- cocotb Directed/随机全部PASS，ACK/NAK与cocotbext逐Byte一致；
- 全部4096个Sequence值和至少1,048,576个独立TX/ACK事务通过；
- KU040 OOC 250 MHz WNS/TNS≥0/0，0 Error、0 Critical Warning、0 DRC Error、
  0 Critical CDC，不使用DSP或PCIe Hard Block；
- VCS编译因已记录许可证问题延期，最迟K11前补测；
- 保存测试、资源、时序、CDC/DRC、Allowlist和已知限制后冻结K06。

K06未完成第七步前不得开始K07。

## 7. 执行结果

- 错误 Stub接受TL Packet但不产生Sequence/LCRC，被首个TX Checker超时检出；
- Verilator/cocotb Replay Core 5/5 PASS，固定种子`20260806`完成10,000个随机
  Packet和完整12-bit Sequence回绕；最大144 Byte RX、坏LCRC、MAC错误、重复、
  未来Sequence、累计ACK、NAK和Timer Replay均通过；
- 两个仲裁器2/2 PASS，覆盖ACK/NAK优先、随机反压和Packet边界锁定；
- Native签核执行1,048,576个TX/ACK事务，覆盖256次完整Sequence回绕；
- KU040 250 MHz OOC：WNS/TNS=`+0.400 ns/0.000 ns`，5,403 CLB LUT、2,225 FF，
  BRAM/DSP/PCIe Hard Block均为0；CDC无Warning/Critical，DRC只含固定
  `CFGBVS-1`；
- VCS继续沿用已批准的许可证延期记录，最迟在K11前补测。

详细证据见`docs/reports/k06-dll-replay.md`。K06已完成第七步冻结，本次不自动
开始K07。
