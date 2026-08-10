# K08 Type-0 配置空间阶段报告

日期：2026-08-07

状态：**PASS / K08-CFG-SPACE-v1 已冻结**

接口版本：`K08-CFG-SPACE-v1`

## 1. 结论

K08已实现4 KiB、单Function Type-0配置空间、PCIe Capability、BDF捕获、4 KiB
BAR0探测/分配和K09所需配置状态输出。生产模块与K07 TLP Codec组合后，
`cocotbext-pcie 0.2.16` Root Complex已经通过真实Type-0 TLP路径完成枚举。

本阶段没有实现Memory TLP的BAR命中、AXI4-Lite访问、Read Completion拆分或错误转换；
这些内容严格保留给K09。当前结果也不等同于K03～K06完整链路、VCS串行或实板/Linux
枚举。

## 2. 交付文件

| 文件 | 职责 |
|---|---|
| `rtl/tl/pcie_cfg_space.sv` | 生产配置空间、BDF、BAR0和响应槽 |
| `rtl/tl/k08_cfg_space_ooc_top.sv` | KU040 OOC复位包装 |
| `sim/verilator/k08/k08_cfg_model.py` | 独立1024-DWORD事务参考模型 |
| `sim/verilator/k08/test_pcie_cfg_space.py` | 结构化Cfg BFM、Monitor、Scoreboard及6项测试 |
| `sim/verilator/k08/pcie_cfg_space_bad_stub.sv` | 身份、BAR尺寸和BE均故意错误的Stub |
| `sim/verilator/k08/k08_cfg_tlp_test_top.sv` | 生产K07+K08 TLP级集成顶层 |
| `sim/verilator/k08/k08_simport_adapter.py` | Root Port SimPort到128-bit Packet Stream的测试适配 |
| `sim/verilator/k08/test_k08_tlp_integration.py` | 配置冒烟和真实Root Complex枚举 |
| `fpga/kcu105/run_k08_cfg_space_ooc.tcl` | 250 MHz OOC综合、时序、CDC、DRC和资源检查 |
| `fpga/kcu105/run_k08_cfg_space_ooc.sh` | 报告与Warning精确门禁 |

架构、接口和RTL前验证计划分别保存在`docs/architecture`、`docs/interfaces`和
`docs/verification`目录。

## 3. 实现结果

- 单响应槽：请求握手后一拍产生SC/UR，响应反压期间全部字段稳定；
- 首次Function 0请求捕获完整BDF，Device Number允许由Root Port分配为非零；捕获后
  精确匹配，错配访问返回UR；
- PERST#取消待响应并复位配置；Hot Reset清可写状态/BDF但保持已产生响应到握手；
- Vendor/Device=`1234:e001`，Class=`ff0000`，Revision=`01`；
- PCIe Capability位于`0x40`，报告Gen3 x1、MPS 128 B、无ASPM/FLR；
- BAR0为4 KiB、32-bit、non-prefetchable；全1探测不破坏真实工作基址；
- Command、Device Control、Link Control和Target Speed逐Byte Enable更新；
- MRRS只接受线路编码0～5，6/7保持旧值；配置读忽略BE并返回完整DWORD；
- Link Status实时映射Gen1/2/3、x1/Down、Training和DLL Active；
- 输出BAR0基址、probe状态、MSE/BME、MPS/MRRS、RCB、Link Disable、Retrain脉冲
  和Target Speed。K09只使用BAR/Probe/MSE/BDF；RCB是本Function作为Requester时的
  接收边界，保留给未来主动Requester，不控制Endpoint Completer的出站Completion。

## 4. Checker、Lint与单模块回归

错误Stub在正常114 ns内完成请求，并被同一个生产守卫同时检出三项具体错误：

```text
Identity: e0011235 != e0011234
BAR0 mask: ffffffff != fffff000
Byte Enable: 00100000 != 00100100
K08_CHECKER_SELFTEST_PASS identity=1 bar=1 be=1
```

门禁要求独立marker精确包含`identity bar be`；编译失败、超时或任意其他JUnit failure
均不能冒充Checker通过。生产RTL和两个集成顶层通过Verilator 5.020严格`-Wall`，
0 Error、0 Warning。

固定种子`20260807`的正式回归结果：

| 测试 | 主要覆盖 | 结果 |
|---|---|---:|
| `identity_and_bar_probe_guard` | 身份、BAR尺寸、BE隔离 | PASS |
| `reset_image_and_read_byte_enables` | 全部1024 DW、读BE 0～15 | PASS |
| `all_dwords_all_bits_and_byte_enables` | 1024×32 one-hot/one-cold、可写DW全部BE | PASS |
| `bdf_bar_and_control_directed` | BDF、SC/UR、BAR、Command、MRRS、Target Speed | PASS |
| `link_status_retrain_and_reset_timing` | 动态Link、Retrain、Hot Reset pending、PERST | PASS |
| `randomized_100k_reference` | 独立模型逐事务比对、反压与复位 | PASS |

```text
TESTS=6 PASS=6 FAIL=0 SKIP=0
RANDOM_TRANSACTIONS=100000
K08_VERILATOR_PASS unit_tests=6 integration_tests=2 random=100000 seed=20260807
```

随机测试覆盖1024个地址、16种BE、匹配/Bus错/Device错/Function错BDF、0～3拍请求
空闲、1～64拍响应反压、Hot Reset、PERST和动态链路状态。全部输出在每个事务后与
独立Python状态模型比较。逐bit测试额外读取其他DWORD哨兵，检查写入没有跨寄存器污染；
独立周期Monitor检查固定响应延迟、无请求不响应、一次请求一次响应及反压稳定性。

## 5. K07+K08真实TLP级枚举

测试没有创建Python Endpoint Function。Root Complex通过Root Port把配置访问转换成
Type-0 TLP，再经SimPort适配器、生产K07解码、生产K08响应、生产K07编码Completion
返回Root Complex。

| 项目 | 结果 |
|---|---:|
| 配置读/部分BE写/读回 | PASS，3个请求/3个Completion |
| `RootComplex.enumerate()` | PASS |
| 发现设备 | `01:00.0` |
| Vendor/Device/Class | `1234:e001 / ff0000` |
| PCIe Capability | `0x40`、Gen3 x1、MPS 128 B |
| BAR0 | 探测4 KiB，分配`0xc0000000` |
| MSE | `enable_device()`后为1 |
| K07逐包计数 | 45个Type-0请求、45个Completion，完全相等 |
| K07错误计数 | malformed/unsupported/protocol error均0 |

这项结果称为“K07+K08 TLP级枚举PASS”。完整LTSSM/DLL/PHY/VCS/Linux枚举仍按K11
及已有延期记录执行。

## 6. KU040 OOC签核

目标器件`xcku040-ffva1156-2-e`，时钟4.000 ns。所有同步输入明确约束为
`0.25～1.00 ns`边界延迟，所有输出给下游保留`1.00 ns`setup预算；这是K11集成时
必须保持的层次接口时序契约。最终结果：

| 项目 | 结果 |
|---|---:|
| WNS / TNS | `+1.288 ns / 0.000 ns` |
| WHS / THS | `+0.014 ns / 0.000 ns` |
| 失败端点 / 未约束内部端点 | `0 / 0` |
| 无Input Delay / 无Output Delay | `0 / 0` |
| 部分Input Delay / 部分Output Delay | `0 / 0` |
| CLB LUT / FF | `157 / 113` |
| BRAM / DSP / PCIe Hard Block | `0 / 0 / 0` |
| 动态扇入 | Response 1、BDF 16、BAR0 20、MSE 1个寄存器起点 |
| CDC | `All paths are Safely Timed`，0 Warning/Critical |
| DRC | 1×`CFGBVS-1 Warning`，0 Error/Critical |

普通Warning精确限定为：

- `Synth 8-3917`×3：`max_payload_size[2:0]`按接口固定为0；
- `Synth 8-7080`×1：小型OOC设计不满足并行综合门限；
- `Synth 8-7129`×48：Requester ID和Tag按K07契约保留，但K08不参与Completion上下文；
  在生产模块与OOC顶层各报告一次；
- `Timing 38-242`×2：OOC边界没有最终Clock Buffer位置，K11完整实现重新签核。

任何数量变化、新Warning、Critical Warning或Error均使构建失败。

## 7. 已知限制与延期

- 单Function、单响应槽、VC0，不支持连续每拍配置访问；
- 只有Function 0可首次捕获，Bus号和Device号均通过首个合法请求取得；
- 无PM、MSI/MSI-X、AER、ASPM、FLR、SR-IOV和扩展Capability；
- K07-v1固定为配置读返回1 DW/4 Byte，K08因此忽略CfgRd BE；
- Gen3能力已经报告，但Gen3 EQ与完整集成分别属于K12/K13；
- VCS许可证与当前未插KCU105的延期继续保留，最迟K11/K13对应门禁补齐；
- 当前没有实现BAR Memory访问；K09完成前Root Complex只能枚举和配置BAR，不能MMIO。

## 8. 冻结决定

`K08-CFG-SPACE-v1`的配置映射、逐位属性、BDF规则、BAR0大小、复位语义、普通端口和
响应时序全部冻结。K08七步门禁已完成，可以严格按顺序开始K09。
