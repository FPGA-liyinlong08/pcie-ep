# K04 PCIe CRC RTL 前验证计划

状态：**K04-v1 计划已执行；全部当前门禁 PASS**

接口版本：`K04-CRC32S-v1`

## 1. 参考模型与平台

```text
Python Packet/Beat Driver
        ↓ start/data/keep/last/valid
pcie_crc16_dllp 或 pcie_crc32_lcrc DUT
        ↓ crc_result/crc_match/error
逐 bit Reference + Residue Checker + Scoreboard
```

采用三个互相独立的参考来源：

1. Python 逐 bit 右移模型，CRC16 使用 `D008`、CRC32 使用 `EDB88320`；
2. DLLP CRC16 与 `cocotbext-pcie 0.2.16` 的 `crc16()` 和 `Dllp.pack_crc()` 比对；
3. LCRC32 与 Python 标准库 `zlib.crc32()` 比对，并检查反射 residue
   `DEBB20E3` 的 bit-reverse 等于现有 PLDA 网表常量 `C704DD7B`。

Driver 随机插入 valid 空拍；Monitor 只在 `valid&&ready` 时重建 Byte 流；
Scoreboard 由重建后的 Byte 独立计算期望值，不读取 DUT 内部状态。

## 2. 测试平台先行与错误 Stub

先提供与正式模块同端口的 `pcie_crc_bad_stub`，对所有输入错误地固定返回 0。
`known_vectors` 必须失败，JUnit 必须包含 failure；外层脚本仅在观察到该失败后输出：

```text
K04_CHECKER_SELFTEST_PASS
```

这证明 Checker 会逐值比较 CRC，而不是只等待 `crc_valid`。

## 3. Directed Case

| 编号 | 用例 | 检查点 |
|---|---|---|
| K04-D001 | 复位与中途复位 | ready/busy/result 安全值；进行中 Packet 被丢弃 |
| K04-D002 | `123456789` | CRC16/CRC32 与固定已知值、cocotbext/zlib 一致 |
| K04-D003 | 全 0、全 1 | 长度 1、2、3、4、16、128、4096 Byte |
| K04-D004 | 全部末拍 keep | 15 个非零 mask，按有效 lane 升序计算 |
| K04-D005 | 单拍/多拍/连续 Packet | start/last 和结果延迟正确，无串包 |
| K04-D006 | 随机 valid 空拍 | CRC 不在无握手时推进 |
| K04-D007 | DLLP 交叉模型 | 多种 ACK/NAK/InitFC/UpdateFC 4 Byte 内容与 `pack_crc()` 一致 |
| K04-D008 | CRC residue | data+正确 CRC match=1；错误 CRC match=0 |
| K04-D009 | 单 bit 错误 | 数据区和 CRC 区每个选择位置翻转，必须 match=0 |
| K04-D010 | 协议错误 | 缺 start、嵌套 start、keep=0、非末拍 partial keep |
| K04-D011 | 错误恢复 | 错误后一拍重新 start，新 Packet 结果正确 |
| K04-D012 | 结果连续性 | 前一包 crc_valid 同拍接受下一包首拍 |

## 4. 约束随机与百万向量

- 固定随机种子 `20260806`，允许环境变量覆盖并打印；
- cocotb 至少完成 10,000 个 Packet，长度在 1～4096 Byte 分层抽样；
- Native Verilator Sign-off 至少完成 1,000,000 个随机向量：CRC16/CRC32 各
  500,000 个；短包高权重，周期性加入 128/256/512/1024/2048/4096 Byte；
- 每个向量随机数据、末拍 keep、单拍/多拍和相邻 Packet；
- 至少 100,000 个向量追加正确 CRC 做 residue 检查，并对其注入一个随机 bit 错误；
- 保存向量数、总 Byte 数、seed 和失败向量内容。

## 5. Assertion 与覆盖点

必须检查：

- 复位时 `ready=0`、`busy/crc_valid/protocol_error=0`；
- `crc_valid` 和 `protocol_error` 互斥且均为单拍；
- `busy=0` 时只有 `start=1` 的握手才合法；
- `busy=1` 时不允许新的 start；非末拍只允许 `keep=1111`；
- 无握手时 CRC 上下文不变化；
- 每个结果严格对应一个已接受末拍，错误 Packet 不产生结果；
- CRC 结果 Byte 顺序、keep 稀疏 mask 顺序及 residue 全部匹配参考模型。

覆盖点：两个 CRC 宽度、1/2/3/4/16/128/4096 Byte、15 种末拍 keep、单拍和
多拍、有效空拍、连续 Packet、四类协议错误、正常 residue、数据/CRC 单 bit 错误。

## 6. 静态检查与通过标准

- 错误 Stub 自检必须 PASS；
- Verilator lint：0 Error，普通 Warning 必须修复或加入精确说明；
- cocotb Directed/随机：全部 PASS；
- Native Verilator：一百万随机向量全部与逐 bit 模型一致；
- KU040 OOC：250 MHz 约束下 WNS/TNS≥0/0，0 Error、0 Critical Warning、
  0 DRC Error、0 Critical CDC，不使用 BRAM/DSP/Xilinx PCIe Hard Block；
- VCS 因当前许可证不可用只登记延期，不阻塞纯 RTL 的 K04 冻结；许可证恢复后补做
  编译兼容性检查；
- 保存 JUnit、Native 摘要、利用率/时序/DRC/CDC 和已知限制后才允许冻结 K04。

K04 未完成第七步前不得开始 K05。

## 7. 执行结果

- 错误 Stub 被已知向量用例检出，`K04_CHECKER_SELFTEST_PASS`；
- Verilator/cocotb：5/5 用例通过，随机 Packet 数 10,000，种子 `20260806`；
- Native Verilator：1,000,000 个算法向量、100,000 个正确 residue 向量和
  100,000 个单 bit 错误向量通过，总计处理 23,475,661 Byte；
- KU040 OOC：250 MHz 下 WNS/TNS=`0.574 ns/0.000 ns`，428 LUT、108 FF，
  BRAM/DSP/PCIe Hard Block 均为 0；
- CDC 仅有一组四级异步复位同步链 `CDC-9 Info`，无 Warning/Critical；
- DRC 仅有无板级顶层 OOC 的 `CFGBVS-1` 固定 Warning，无 Error/Critical；
- VCS 编译兼容性按已批准的许可证延期记录保留，最迟在 K11 前补测。

详细证据与限制见 `docs/reports/k04-pcie-crc.md`。K04 已完成第七步冻结，本次不
自动开始 K05。
