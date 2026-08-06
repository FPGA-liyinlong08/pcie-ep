# K05 DLLP 与 Flow Control RTL 前验证计划

状态：**K05-v1 计划已执行；全部当前门禁 PASS**

接口版本：`K05-FC16-v1`

## 1. 参考模型与平台

```text
K03 framed Driver ─→ DLLP Codec ─→ FC Manager
       ↑                  │              │
DLL Partner/CRC注错       └→ Event Monitor └→ Credit Scoreboard
       └──────── MAC TX Monitor ←────────┘
```

参考来源：

1. `cocotbext-pcie 0.2.16` 的 `Dllp.pack_crc()/unpack_crc()`，逐字段比对 9 种 FC DLLP；
2. 独立 Python/C++ 模型维护 Init mask、模计数、无限信用、occupied/allocated；
3. K04 固定 residue `16'h556F`，不从 DUT 内部读取 CRC 状态。

DLL Partner 可丢弃、延迟、重复、破坏 CRC 或修改 VC/Scale；MAC TX Monitor 必须
逐 Byte 重建 6 Byte DLLP，并在随机 ready 反压下检查输出稳定性。

## 2. 测试平台先行与错误 Stub

先提供同顶层端口的错误 Stub：复位后错误地固定 `dll_active=1`、不发送 InitFC、
所有信用永久可用。正常初始化用例必须失败，JUnit 必须包含 failure；外层只有观察到
该失败后才输出：

```text
K05_CHECKER_SELFTEST_PASS
```

## 3. Directed Case

| 编号 | 用例 | 检查点 |
|---|---|---|
| K05-D001 | 复位/link_up下降 | DOWN、无TX、许可为0、会话清空、统计保留 |
| K05-D002 | 9种FC DLLP编解码 | 与 cocotbext 6 Byte结果逐Byte一致 |
| K05-D003 | K03不同拍型 | `2+2+2`、`1+2+2+1`、随机1/2 Byte组合均重组一致 |
| K05-D004 | TX随机反压 | valid期间 data/keep/sop/eop 全部稳定 |
| K05-D005 | 正常InitFC | INIT1收齐三类、INIT2收到任一确认、进入Active |
| K05-D006 | 丢失/延迟/重复 | Init持续重发，重复不破坏已捕获信用 |
| K05-D007 | CRC/长度/framing错误 | 不推进状态，分类计数，后续合法包恢复 |
| K05-D008 | VC/Scale/错误阶段 | 只支持VC0/scale0，非法包忽略并计错 |
| K05-D009 | 远端有限信用 | P/NP/Cpl分别耗尽后gate=0，UpdateFC恢复 |
| K05-D010 | 远端无限信用 | Init字段0时消费不递减，available显示全1 |
| K05-D011 | 本地consume/release | occupied与累计UpdateFC字段逐事件一致 |
| K05-D012 | 上下溢与非法类型 | 不修改合法状态，错误计数饱和递增 |
| K05-D013 | 周期UpdateFC | 无release也周期重发三类最新累计值 |
| K05-D014 | 同拍consume/release | 相同/不同类型净变化正确，不丢dirty |
| K05-D015 | 非FC DLLP旁路 | ACK/NAK事件保持原始32 bit，K05不解释 |

## 4. 百万随机信用事件

- 固定种子 `20260806`，环境变量可覆盖并打印；
- Native Verilator 至少执行 1,000,000 个事件；
- 事件随机选择 P/NP/Cpl、TX check/consume、远端 UpdateFC、本地 consume/release、
  同拍双事件和周期调度；
- Scoreboard 每拍比对六组远端 available、六组本地 occupied、状态、许可和错误计数；
- 周期性强制 8-bit/12-bit 累计计数完整回绕；
- 只生成符合半范围约束的合法累计信用，另设错误事件验证上下溢保护。

## 5. Assertion 与覆盖

必须检查：

- `dll_active` 当且仅当 state=ACTIVE，Active 前 TLP gate 永远为 0；
- TX valid 被反压时所有 Payload/边界信号稳定；
- 坏 CRC/结构错误/VC/Scale 不更新远端 limit 或初始化 mask；
- 有限信用不下溢，occupied 不超过初始分区，非法事件不修改计数；
- release 最终产生含最新累计值的 UpdateFC；
- link_up 下降后一拍不再发送旧会话 DLLP；
- 输出事件与输入 DLLP 一一对应，无静默丢失或重复。

覆盖点包括 9 种 FC Type、P/NP/Cpl、finite/infinite、三种 FC 状态、三种 Header/Data
边界（0/1/max）、CRC/长度/framing/VC/Scale错误、全部合法 RX 拍型、反压、周期更新、
同拍 consume/release 和 8/12-bit 回绕。

## 6. 静态与通过标准

- 错误 Stub 自检 PASS；
- Verilator lint 0 Error，普通 Warning 必须修复或精确登记；
- cocotb Directed/随机全部 PASS，与 cocotbext 逐 Byte 一致；
- Native Verilator 一百万信用事件无 Scoreboard 差异；
- KU040 OOC 在 250 MHz 下 WNS/TNS≥0/0，0 Error、0 Critical Warning、
  0 DRC Error、0 Critical CDC，不使用 BRAM/DSP/PCIe Hard Block；
- VCS 编译因已记录许可证问题延期，最迟 K11 前补测；
- 保存测试摘要、利用率、时序、CDC/DRC、Allowlist 和已知限制后冻结 K05。

K05 未完成第七步前不得开始 K06。

## 7. 执行结果

- 错误 Stub 未执行 InitFC、直接置 Active，被初始化断言检出；
- Verilator/cocotb 5/5 PASS，包含 9 种 FC DLLP、可变 1/2 Byte 拍型、独立控制
  EOP、随机反压、错误注入、有限/无限信用和 10,000 个随机信用事件；
- Native Verilator 完成 1,000,000 个事件：296,162 次 TX consume、300,542 次
  远端 UpdateFC、237,749 次本地 consume、237,728 次本地 release；
- KU040 250 MHz OOC：WNS/TNS=`0.219 ns/0.000 ns`，1,137 CLB LUT、761 FF，
  BRAM/DSP/PCIe Hard Block 均为 0；
- CDC 固定为一组 OOC 四级复位链 `CDC-9 Info`，无 Warning/Critical；
- VCS 编译继续沿用已批准的许可证延期记录，最迟在 K11 前补测。

详细证据见 `docs/reports/k05-dllp-flow-control.md`。K05 已完成第七步冻结，本次不
自动开始 K06。
