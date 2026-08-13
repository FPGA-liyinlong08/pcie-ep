# KCU105/KU040 standalone PCIe PHY Endpoint 实施顺序

状态：**计划 v1 已冻结；K00～K11 PASS；K11-PHASE-RELEASE-v1 已冻结；K12启动**

## 1. 阶段门

每个阶段严格按以下顺序执行：

1. 架构冻结：职责、非职责、状态机、缓冲、时钟/复位和错误处理；
2. 接口冻结：方向、宽度、时钟域、复位值、握手、字节序和延迟；
3. RTL 前仿真计划冻结：模型、Directed、随机、注错、断言、覆盖和标准；
4. 测试平台先行：Driver、Monitor、Scoreboard 和故意错误 Stub 自检；
5. RTL：只实现本阶段冻结范围；
6. 验证：Directed、随机、Lint，以及适用的 VCS、CDC、DRC、综合/实现；
7. 冻结：保存报告、覆盖、限制和接口版本，并汇报 PASS/FAIL。

当前阶段未完成第 7 步，不得开始下一阶段。每阶段提供 `make kNN` 入口。

## 2. K00～K14

| 阶段 | 实施内容 | 主要验收与进入下一阶段的条件 |
|---|---|---|
| K00 | 新工程、中文基线文档、M00 通用验证和 M02 Packet FIFO 的 KU040 再签核 | Verilator/VCS 通过；六组共 600 万 Packet；KU040 OOC、BRAM、CDC、DRC 通过 |
| K01 | `kcu105_refclk_reset`：REFCLK 缓冲、PERST# 分发、PIPE/Core 复位 | 1,000 组随机复位；VCS 原语；AB6/AB5、K22 约束；KU040 CDC/DRC |
| K02 | Tcl 确定生成并封装 `pcie_phy_x1_gen3`，冻结原生端口/XCI | 指纹稳定；OOC/实现；GT 位置；VCS Detect/速率切换；上板检测到对端；第一可行性门 |
| K03 | Gen1 x1 LTSSM/MAC：Detect、Polling、Configuration、Recovery、L0、扰码、Ordered Set、成帧 | 软件/静态门禁与VCS真PHY串行L0 PASS；KCU105实板延期 |
| K04 | DLLP CRC16 与 TLP LCRC32 | PASS；逐 Bit/交叉模型、1～4096 Byte、全部末拍、100 万算法向量、250 MHz OOC 均通过 |
| K05 | DLLP、InitFC1/2、UpdateFC、VC0 P/NP/Cpl 信用 | PASS；9种FC DLLP、初始化/周期更新、100万信用事件、250 MHz OOC均通过 |
| K06 | 12-bit Sequence、ACK/NAK、Replay Timer/Buffer | PASS；10,000随机Packet、1,048,576 Native事务、256次回绕、250 MHz OOC均通过 |
| K07 | Cfg/Mem/Completion TLP Codec | PASS；12项回归、22,000随机Packet、多位置复位、11个计数器结构审计、错误/UR路径、严格lint和250 MHz OOC均通过 |
| K08 | 4 KiB Type-0 配置空间和 PCIe Capability | PASS；`1234:e001`、4 KiB BAR0、1024×32逐Bit、10万随机事务、真实TLP级RC枚举、250 MHz OOC |
| K09 | BAR0 命中、写拆分、读执行和 Completion | PASS；9项单模块回归、10万请求随机反压、K07+K08+K09真实TLP级枚举/MMIO、128 B/4 KiB拆分、错误转CA及250 MHz OOC均通过 |
| K10 | 4 KiB Demo AXI4-Lite Slave | PASS；7项回归、10万随机请求、全部1008可写DWORD、16种WSTRB、K09集成、1×RAMB36E2及250 MHz routed OOC |
| K11-A | Gen1离线全集成（MAC Packet边界以上） | PASS；DLL Active、Cfg、BAR、Demo、Hot Reset、双向CDC、KU040 routed OOC和定向CDC均通过 |
| K11-B | Gen1真PHY/实板全集成 | PASS / 阶段性release；真实PHY InitFC/枚举/BAR、随机MMIO、LCRC/ACK注错、PERST#恢复、无ILA正式时序及KCU105 reboot/MMIO通过；最终压力门保留K14 |
| K12 | Recovery.Speed 与 EQ Phase 0～3 | K12-A/B/C独立控制器及行为PHY Partner集成 PASS；真实TS、CDR、VCS真实PHY、生产接线和实板仍待实现 |
| K13 | Gen3 全集成 | VCS Gen1→Gen3；KCU105 Gen3 x1；枚举和 10 万 BAR 随机操作 |
| K14 | 最终加固和发布冻结 | Hot Reset、remove/rescan、长时 MMIO、CDC/DRC/时序和 Linux 最终验收 |

## 3. 固定验证分层

- Verilator：全部自研 RTL；K02 使用行为 PHY Stub；
- cocotb：PHY Partner、DLL Partner、TLP 参考模型、AXI-Lite BFM、Scoreboard；
- VCS：Xilinx `pcie_phy`/GTHE3 模型与现有 Root Port 串行环境；
- Vivado：各阶段 KU040 综合、CDC、DRC；K02/K03/K11/K13 完整布局布线；
- 上板：K02 Detect，K03 Gen1 L0，K11 Gen1 枚举，K13 Gen3 枚举。

Vivado Warning 使用阶段固定 Allowlist。新增 Warning、任何 Critical Warning 或
Error 均失败。最终目标为 Gen3 x1、`1234:e001`、4 KiB BAR0、10 万次随机
8/16/32-bit MMIO、20 次冷启动、100 次重训，且相关时钟路径 WNS 不小于 0。
