# KCU105/KU040 自研 PCIe Endpoint

本工程目标是在 KCU105（`xcku040-ffva1156-2-e`）上实现 PCIe Gen3 x1
Endpoint。Xilinx standalone `pcie_phy v1.0` 只负责 GT/PMA/PCS、Receiver
Detect、速率切换和均衡执行；LTSSM、Ordered Set、DLL、TLP、配置空间和 BAR
均由本工程实现。

文字数据路径固定为：

`PCIe 串行口 → Xilinx standalone pcie_phy → PHY32 → 自研 LTSSM/MAC → 自研 DLL → 异步 Packet FIFO → TLP/配置空间 → BAR-to-AXI4-Lite`

## 当前阶段

- K00：**PASS / K00-v1 已冻结**。
- K01：**PASS / K01-v1 已冻结**。
- K02：**K02-v1.2 条件冻结**；架构/接口、错误Stub、Verilator、XCI指纹、
  Vivado完整实现及VCS真实IP动态仿真均已通过；KCU105 Receiver Detect因当前
  未插板延期。K11-B真实PHY串行回归已补齐非实板动态门禁。
- K03：**K03-v1.1 条件冻结**；架构/接口、错误 Stub、Verilator随机回归、
  KU040 OOC、K02 PHY联合布局布线及VCS真PHY串行Gen1 x1 L0均通过；KCU105
  实板门禁因当前未插板延期。
- K04：**PASS / K04-v1 已冻结**；DLLP CRC16、TLP LCRC32、错误 Stub、
  cocotb Directed/随机、100 万算法向量和 KU040 250 MHz OOC 均通过；K11-B
  真实PHY VCS已编译并运行包含K04～K10的完整生产链路，兼容性延期闭环。
- K05：**PASS / K05-v1 已冻结**；6 Byte DLLP Codec、InitFC1/2、UpdateFC、
  VC0 P/NP/Cpl 信用、错误 Stub、10,000 个 cocotb 随机事件、100 万 Native
  信用事件和 KU040 250 MHz OOC 均通过。
- K06：**PASS / K06-v1 已冻结**；12-bit Sequence、ACK/NAK、LCRC、Replay
  Timer/Buffer、K05集成和两级TX仲裁均已实现；10,000个随机Packet、1,048,576
  个Native事务、256次Sequence回绕及KU040 250 MHz OOC均通过。
- K07：**PASS / K07-TLP-CODEC-v1 已冻结**；Cfg/Mem/Cpl整包解码、严格格式检查、
  UR/错误路径、Completion编码和K06信用事件均已实现；错误Stub、12项cocotb、
  22,000个随机Packet、多位置复位、11个饱和计数器结构审计、严格lint及KU040
  250 MHz OOC均通过。
- K08：**PASS / K08-CFG-SPACE-v1 已冻结**；4 KiB Type-0配置空间、PCIe
  Capability、BDF捕获和4 KiB BAR0已实现；错误Stub、1024×32逐Bit、全部BE、
  100,000随机事务、K07+K08真实TLP级Root Complex枚举和KU040 250 MHz OOC均通过；
  已作为K09配置输入基线。
- K09：**PASS / K09-BAR-AXIL-v1 已冻结**；BAR0命中、1～32 DW Posted Write、
  1～1024 DW Read、128 B Completion拆分和AXI错误转CA均已实现；错误Stub、9项
  单模块回归、10万请求随机反压、K07+K08+K09真实TLP级枚举/MMIO和KU040
  250 MHz OOC均通过。
- K10：**PASS / K10-DEMO-AXIL-v1 已冻结**；4 KiB AXI4-Lite Slave、只读诊断、
  48 DWORD Scratch和960 DWORD RAM已实现；错误Stub、7项单元、10万随机请求、
  全部16种WSTRB、生产K09集成和KU040 250 MHz routed OOC均通过，RAM为1×RAMB36E2。
- K11-A：**PASS / K11A-OFFLINE-INTEGRATION-v1 已冻结**；已在K03 MAC Packet
  边界以上连接生产DLL、异步Packet/事件FIFO、TLP/CFG/BAR和Demo，完成DLL Active、
  `1234:e001`配置读取、BAR0分配/MSE、签名MMIO及Hot Reset；KU040离线实现
  `WNS=+0.001 ns`、`WHS=+0.022 ns`。K11-B1真PHY串行L0已冻结。
- K11-B2：**PASS / K11-PHASE-RELEASE-v1 阶段性冻结**。真实PHY路径已完成DLL
  Active、`1234:e001`枚举、4 KiB BAR0和Demo读写；G1修复Receiver Detect后的
  P1→P0握手，G9加入首次Root Port活动等待，G12-B把Configuration状态切换对齐到
  完整Ordered Set边界。无ILA release bit实现`WNS=+0.019 ns`、DRC 0 Error，实板
  reboot后成功枚举并连续5次BAR mmap通过；另有3轮reboot、15次BAR mmap压力通过。
  允许进入K12。严格断电cold boot、20次启动、100次PERST#/重训和长时MMIO保留给
  K14最终发布门，不把阶段性release表述为最终量产冻结。
- K12：**K12-A/B/C/D及K12-E真实PHY影子适配 PASS**；已完成原子跨域、速率切换/
  fallback、Phase 0～3、Preset/Coefficient、TX/RX done超时、CDR loss、TS类型/速率/
  Lane/Link合法性和Ordered Set边界检查；真实PHY VCS下Gen1默认反馈已知且EQ控制为0，
  K11-B2枚举/BAR仍通过。真实Gen3 retrain/EQ生产驱动接线归入K13，K11 release基线不变。
- K13：**控制阶段 PASS，生产顶层接线未完成**；新增可关闭的
  `pcie_k13_production_ctrl`，组合K12 CDC、Recovery.Speed、TS合法性和EQ Phase 0～3，
  已通过Gen3速率/EQ、CDR loss回退和非法TS拒绝三项门禁；`K13_ENABLE=0`保持K11
  Gen1安全值。下一步是把配置空间Retrain、生产LTSSM Ordered Set边界和真实PHY反馈
  接入该控制器，然后再做Gen3真实VCS、Vivado和上板bit验证。
- K00 导入通用 Smoke 验证、CDC 同步器和已冻结的 M02 Packet FIFO；不导入
  KU060 的时钟、GT、PCS 或 PCIe 协议 RTL。
- K01 已实现 PCIe REFCLK 缓冲、PERST# 分发和 PIPE/Core 四级复位同步释放。
- K02 已生成 standalone PHY 封装和 bring-up bitstream；原延期的VCS动态门禁已
  补齐，只剩实板Receiver Detect。K03 已完成软件、静态与VCS串行门禁，K04、K05已
  独立完成并冻结；K06～K10已完成并冻结，K11已形成阶段性release，K12已完成控制与
  影子适配，当前进入K13生产接线。
- 历史工程 `/home/wx/Documents/PCIe/pcie_ep_ku060` 保持原位，不移动、不删除、
  不由本工程脚本写入。

## 目录

| 目录 | 用途 |
|---|---|
| `docs/architecture` | 总体和模块架构冻结文档 |
| `docs/interfaces` | 接口、时钟域、复位和握手契约 |
| `docs/verification` | RTL 前仿真计划和阶段门模板 |
| `docs/reports` | 实际执行结果、已知限制和冻结决定 |
| `docs/archive` | KU060 历史基线位置和状态 |
| `docs/implementation-plan.md` | K00～K14 顺序、阶段门和验收目标 |
| `rtl/common` | 可复用同步器和异步 Packet FIFO |
| `rtl/phy` | K01 时钟/复位、K02 PHY 封装、K03 Gen1 LTSSM/MAC |
| `rtl/dll` | K04 CRC，以及后续 DLLP/FC/Replay 模块 |
| `rtl/tl` | K07 TLP Codec、K08配置空间、K09 BAR Master和K10 Demo AXI Slave |
| `sim/verilator` | cocotb/Verilator 与 Native C++ 回归 |
| `sim/vcs` | VCS/Xilinx 库 Smoke 和 FIFO 回归 |
| `fpga/kcu105` | KU040 约束、Tcl 和阶段构建入口 |

## K00 命令

完整回归：

```bash
make k00
```

可独立运行：

```bash
make k00-baseline
make k00-m02-checker-selftest
make k00-m02-lint
make k00-m02-verilator
make k00-m02-verilator-signoff
make k00-m02-vcs
make k00-m02-vivado
```

`k00-m02-verilator-signoff` 对六组时钟组合各发送 1,000,000 个 Packet；
`k00-m02-vivado` 以 KU040 进行 OOC 综合、BRAM/CDC/DRC 检查。

外部 FIFO 依赖固定为：

`/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v`

构建前会核对 SHA-256；该文件不复制、不修改。

## K01 命令

完整回归：

```bash
make k01
```

可独立运行：

```bash
make k01-checker-selftest
make k01-lint
make k01-verilator
make k01-vcs
make k01-vivado
```

`k01-verilator` 覆盖 Gen1/2/3 三种 `phy_pclk`，共执行 3,000 组 PERST# 和
750 组 PHY Status 随机复位；`k01-vcs` 使用 Vivado 2021.2 原语库；
`k01-vivado` 对 KU040 执行 OOC 综合、管脚/原语/CDC/DRC/时序检查。

## K02 命令

自动回归入口：

```bash
make k02
```

可独立运行：

```bash
make k02-checker-selftest
make k02-lint
make k02-verilator
make k02-ip
make k02-vcs
make k02-vivado
make k02-hw-probe
make k02-hw-program
```

`k02-vcs` 使用真实 Xilinx PHY/GTHE3 仿真模型；可通过
`VCS_LICENSE_TIMEOUT=<秒数>` 设置许可证等待上限；仅重试许可证时可同时设置
`K02_SKIP_IP_GENERATION=1` 复用刚验证过的生成目录。上板验收需确认 J74 为 x1，
先执行：

```bash
/home/Xilinx/Vivado/2021.2/bin/hw_server -d -p0 -I60 -stcp::3122
```

随后可用后两个目标探测/下载 bitstream，再观察 Receiver Detect LED。

## K03 命令

完整软件与静态回归：

```bash
make k03
```

可独立运行：

```bash
make k03-checker-selftest
make k03-lint
make k03-verilator
make k03-vivado
```

`k03-verilator` 执行 Directed、错误注入、100 次随机训练以及 2,000 个
1～160 Byte 随机 TLP/DLLP 成帧测试。`k03-vivado` 同时执行 K03 OOC 和
K02 PHY+K03 顶层完整布局布线；完成一次构建后，可用
`K03_REUSE_BUILD=1 make k03-vivado` 快速复核所有报告门禁。VCS 真 PHY 串行与
上板 Gen1 L0 按阶段报告登记为延期，不包含在当前自动 `make k03` 中。

## K04 命令

完整回归：

```bash
make k04
```

可独立运行：

```bash
make k04-checker-selftest
make k04-lint
make k04-verilator
make k04-verilator-signoff
make k04-vivado
```

`k04-verilator` 执行已知向量、全部 15 种末拍 `keep`、DLLP 交叉模型、residue、
单 bit 错误、协议错误恢复和 10,000 个随机 Packet。`k04-verilator-signoff`
执行 1,000,000 个算法向量以及各 100,000 个 residue/单 bit 错误向量；
`k04-vivado` 对 KU040 执行 250 MHz OOC 综合、时序、资源、CDC 和 DRC 门禁。

## K05 命令

完整回归：

```bash
make k05
```

可独立运行：

```bash
make k05-checker-selftest
make k05-lint
make k05-verilator
make k05-verilator-signoff
make k05-vivado
```

`k05-verilator` 与 `cocotbext-pcie Dllp` 逐 Byte 交叉比对，覆盖 InitFC/UpdateFC、
可变 K03 拍型、CRC/长度/framing 错误、随机反压、有限/无限信用和 10,000 个随机
事件。`k05-verilator-signoff` 执行 1,000,000 个独立信用事件；`k05-vivado` 执行
KU040 250 MHz OOC 综合、时序、资源、CDC 和 DRC 门禁。

## K06 命令

完整回归：

```bash
make k06
```

可独立运行：

```bash
make k06-checker-selftest
make k06-lint
make k06-verilator
make k06-verilator-signoff
make k06-vivado
```

`k06-verilator`覆盖Sequence/LCRC、累计ACK、NAK、ACK丢失、Timer Replay、重复/
未来/坏包、最大144 Byte RX、随机反压、10,000随机Packet及两个TX仲裁器；
`k06-verilator-signoff`执行1,048,576个独立TX/ACK事务和256次完整Sequence回绕；
`k06-vivado`对完整K05+K06 `pcie_dll`执行KU040 250 MHz OOC、CDC、DRC、资源及
Warning精确白名单门禁。已有构建可用`K06_REUSE_BUILD=1 make k06-vivado`复核。

## K07 命令

完整回归：

```bash
make k07
```

可独立运行：

```bash
make k07-checker-selftest
make k07-lint
make k07-verilator
make k07-vivado
```

`k07-checker-selftest`要求故意提前分派Cfg的错误Stub被检出；`k07-verilator`执行
12项Directed/随机测试，包括10,000个Cfg/Cpl、5,000合法+5,000非法Raw Packet及
2,000个Memory Packet，固定种子`20260806`；`k07-lint`还审计11个饱和计数器的
15条增量路径。`k07-vivado`对KU040执行250 MHz OOC、TX状态可达性、CDC、DRC、
资源和Warning精确白名单门禁；已有构建可用
`K07_REUSE_BUILD=1 make k07-vivado`复核。

## K08 命令

完整回归：

```bash
make k08
```

可独立运行：

```bash
make k08-checker-selftest
make k08-lint
make k08-verilator
make k08-vivado
```

`k08-checker-selftest`要求错误Stub的身份、BAR尺寸和Byte Enable三个守卫同时命中；
`k08-verilator`执行6项单模块测试、1024×32逐Bit、全部16种BE、100,000个固定种子
随机事务，以及生产K07+K08路径上的2项Root Complex测试。枚举识别`1234:e001`、
PCIe Capability和4 KiB BAR0，但不包含K09 MMIO。`k08-vivado`对KU040执行250 MHz
OOC、动态扇入、CDC、DRC、资源和Warning精确门禁；已有构建可用
`K08_REUSE_BUILD=1 make k08-vivado`复核。

## K09 命令

完整回归：

```bash
make k09
```

可独立运行：

```bash
make k09-checker-selftest
make k09-lint
make k09-verilator
make k09-integration
make k09-vivado
```

`k09-checker-selftest`要求错误Stub的AXI地址、WSTRB和Posted Completion三个守卫
同时命中；`k09-verilator`执行9项单模块测试及固定种子`20260807`的100,000请求
随机反压回归；`k09-integration`让`cocotbext-pcie RootComplex`通过生产K07/K08/K09
完成枚举、8/16/32-bit与多DWORD MMIO、128 B边界拆分、UR和CA；`k09-vivado`
对KU040执行250 MHz OOC、I/O delay、时序、CDC、DRC、资源和Warning严格门禁。

## K10 命令

```bash
make k10
```

可分别运行`make k10-checker-selftest`、`make k10-lint`、`make k10-verilator`、
`make k10-integration`和`make k10-vivado`。随机门禁固定100,000请求并覆盖全部1008个
可写DWORD和16种WSTRB；集成门禁连接生产K09与K10；Vivado门禁要求RAMB36E2非零、
LUTRAM为0、250 MHz setup/hold通过。已有实现可用
`K10_REUSE_BUILD=1 make k10-vivado`复核。
