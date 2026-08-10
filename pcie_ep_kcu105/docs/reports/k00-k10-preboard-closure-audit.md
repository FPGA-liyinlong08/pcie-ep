# K00～K10 非实板门禁收口审计

日期：2026-08-10

状态：**PASS；除KCU105实板项目外，无K11之前的遗留验证项**

## 1. 审计结论

K00～K01已经正式冻结；K04～K10全部正式冻结。K02、K03仍写作“条件冻结”，条件仅
对应当前无法执行的KCU105实板门禁，不包含软件、RTL、VCS、Vivado、CDC、DRC或时序
遗留项。

早期K04～K09报告中保留了“VCS许可证延期，最迟K11补测”的阶段历史。当时记录属实，
现在已由K11-B真实standalone PHY + Xilinx Root Port串行仿真闭环：VCS成功编译K04
CRC、K05 FC、K06 Replay、K07 TLP、K08配置空间、K09 BAR和K10 Demo的完整生产链路，
并完成枚举、BAR、随机MMIO及错误恢复。历史报告不回写成当时已经PASS，以免丢失过程
可追溯性；本审计作为延期关闭记录。

## 2. 分阶段状态

| 阶段 | 非实板状态 | 主要闭环证据 | 剩余项 |
|---|---|---|---|
| K00 | PASS/冻结 | Verilator、PCIe模型、VCS基线；M02六组时钟600万Packet；KU040 OOC/CDC/DRC | 无 |
| K01 | PASS/冻结 | 1000组复位、原语VCS、约束、KU040 CDC/DRC | 无 |
| K02 | 非实板PASS/条件冻结 | XCI指纹、PHY封装、VCS真实IP复位/Detect/速率、完整实现 | KCU105 Receiver Detect |
| K03 | 非实板PASS/条件冻结 | Partner/随机、KU040实现、K11-B1真实PHY Gen1 x1 L0 | KCU105 Gen1 x1 L0 |
| K04 | PASS/冻结 | CRC参考模型、100万向量、250 MHz OOC、K11-B VCS集成 | 无 |
| K05 | PASS/冻结 | InitFC/UpdateFC、100万信用事件、250 MHz OOC、K11-B DLL Active | 无 |
| K06 | PASS/冻结 | Sequence回绕、Replay/NAK/ACK注错、250 MHz OOC、K11-B串行重放 | 无 |
| K07 | PASS/冻结 | 12项回归、22000随机Packet、错误/UR、250 MHz OOC、K11-B枚举 | 无 |
| K08 | PASS/冻结 | 4 KiB逐Bit/BE、10万事务、RC枚举、250 MHz OOC、K11-B Type-0 | 无 |
| K09 | PASS/冻结 | 10万随机请求、拆分/CA、TLP级MMIO、250 MHz OOC、K11-B BAR | 无 |
| K10 | PASS/冻结 | 10万AXI请求、全地址/WSTRB、routed OOC、K11-B Demo读写 | 无 |

## 3. 当前仅存硬件门禁

以下项目都需要插入KCU105，不能由现有仿真替代：

1. K02：真实插槽上的Receiver Detect；
2. K03：KCU105进入Gen1 x1 L0；
3. K11：Linux枚举`1234:e001`、4 KiB BAR0和MMIO；
4. K11：20次冷启动及100次PERST#/链路重训。

其中K02/K03硬件项可在K11整板流程中一次完成和记录，不需要分开重复插拔或构建。
在这些硬件门禁完成前，K11整体不标记最终冻结；但K11之前没有额外的非实板任务。

## 4. 对后续阶段的影响

从技术依赖看，K12的架构、接口和RTL前仿真计划可以先行准备；严格遵循当前七步门禁
时，K11实板最终冻结前不开始K12生产RTL。如需在板卡仍不可用时提前进入K12，必须另行
记录一次阶段门例外，不能把实板延期误记为PASS。
