# K03 Gen1 x1 LTSSM/MAC RTL 前验证计划

状态：**K03-v1 计划已执行；软件/静态门禁 PASS，动态硬件门禁延期**

接口版本：`K03-MAC16-v1`

## 1. 参考模型和平台拓扑

```text
cocotb PHY Partner/注错器
        ⇅ PHY32 Gen1 两 Symbol/拍
pcie_ltssm_mac_gen1 DUT
        ⇅ MAC16 Packet Stream
Packet Driver + Framing Scoreboard
```

- Python Ordered Set 模型逐 Symbol 生成/解析 TS1、TS2、PAD、Idle；
- PHY Partner 响应 Receiver Detect，并按 DUT 状态发送相应训练序列；
- TX Monitor 检查每个 DUT TS 的 16 个 Symbol、K 属性、Link/Lane/N_FTS/Rate/Control；
- Packet Scoreboard 检查 STP/SDP/END/EDB 插入/删除、字节顺序和 Packet 类型；
- 超时参数在仿真中缩短，硬件默认值由静态测试检查不被覆盖。

## 2. 测试平台先行和错误 Stub

先实现与正式 DUT 同端口的错误 Stub：Receiver Detect 成功后直接从 Detect.Active
跳到 L0，且不发送八个 TS1/TS2。运行 `normal_training` 必须失败，JUnit 必须包含
failure；外层脚本只有观察到该失败后才输出 `K03_CHECKER_SELFTEST_PASS`。

这证明 Checker 不是只看最终 `link_up`，而是会检查合法状态顺序和 Ordered Set。

## 3. Directed Case

| 编号 | 用例 | 检查点 |
|---|---|---|
| K03-D001 | 复位安全值 | P1/Electrical Idle、Gen1、无 Packet、状态 Detect.Quiet |
| K03-D002 | Receiver Detect 成功/失败/超时 | 仅 011 前进；失败或超时返回 Quiet并计数 |
| K03-D003 | 正常完整训练 | 所有 15 个状态按冻结顺序，最终稳定 L0 |
| K03-D004 | 错 TS identifier | 连续计数清零、错误计数增加、不非法跳转 |
| K03-D005 | Link/Lane 错误 | PAD、错误 Link、Lane!=0 均不被接受 |
| K03-D006 | Polling/Configuration 超时 | 返回 Detect，timeout 饱和规则正确 |
| K03-D007 | Recovery | force、RX Electrical Idle 后完成 TS1/TS2/Idle 回 L0 |
| K03-D008 | Hot Reset/PERST# | 返回 Detect；`hot_reset_seen` 单拍；Core 不在本模块 |
| K03-D009 | TX TLP/DLLP framing | 1～160 Byte、奇偶长度、END/EDB、随机输入空拍 |
| K03-D010 | RX TLP/DLLP framing | Start/End 两种 Symbol 位置、keep、sop/eop、字节序 |
| K03-D011 | Framing 错误 | 嵌套 Start、非法 K、无 Start End、超长 TX 全被观察 |
| K03-D012 | L0 前禁止 Packet | `tx_pkt_ready=0`，PHY 只发训练/Idle |

## 4. 约束随机和错误注入

- 固定种子 `20260806`，环境变量可覆盖并写入 JUnit；
- 至少 100 次完整训练/重训，每轮随机 Partner 延迟 0～31 拍；
- 每轮随机注入 0～8 个 bad TS、错误 Link/Lane、短 Electrical Idle 或空拍；
- 至少 2,000 个随机 Packet，长度 1～160 Byte，TLP/DLLP、奇偶长度、END/EDB、
  输入空拍随机；
- 训练计数覆盖 0、阈值-1、阈值、超时-1 和超时；
- 对计数器使用小宽度形式检查饱和，正式顶层固定 32 bit。

## 5. 断言与覆盖

必须检查：

- 复位或 Detect 时 `txelecidle=1`，K03 永不请求非 Gen1 rate；
- 状态只能沿冻结有向边跳转；L0 前 `link_up=0`、`tx_pkt_ready=0`；
- TS 的 COM/PAD K-code 与十个 identifier 的 Data-code 属性正确；
- 一个 TS 正好 8 拍；完整 Packet 上线后 Symbol 之间无空洞；
- 高 16 bit 永远为 0，Gen3 block/header 永远为 0；
- RX `sop/eop` 只在 valid 时出现，`keep=00` 仅和 eop 同时出现；
- Packet 字节不丢失、不重复、不乱序；计数器不回绕。

覆盖点：所有 LTSSM 状态、所有正常边、Detect失败/超时、三类主动重启、TS1/TS2、
PAD/分配 Link/Lane、TLP/DLLP、奇偶 Packet、END/EDB、marker 位于两个 Symbol 位置。

## 6. 静态检查与通过标准

- Verilator lint：0 Error；普通 Warning 必须解释或修正；
- cocotb directed/random：全部 PASS；100 次连续训练/重训无失败；
- Vivado KU040 OOC synth：0 Error、0 Critical Warning；OOC `report_cdc` 只允许
  `pipe_rst_n` 产生的 CDC-7，因为单模块边界看不到 K01 同步释放链；完整集成时该项
  必须降为 CDC-9 Info，且不得有 Critical；
- K03+K02 集成 synth/route：不得增加 PCIe Hard Block，DRC 0、WNS/TNS≥0/0；
- VCS 真 IP 串行和 KCU105 Gen1 L0：因许可证/板卡不可用记为延期，最迟 K11 补齐；
- 保存 JUnit、测试摘要、利用率/时序/DRC 报告和已知限制后才可冻结 K03。

K03 失败时只修复本阶段 RTL/测试/文档，不开始 K04 CRC。
