# K07 TLP Codec 阶段报告

日期：2026-08-07

状态：**PASS / K07-TLP-CODEC-v1 已冻结**

接口版本：`K07-TLP-CODEC-v1`

## 1. 结论

K07已实现Cfg、Memory和Completion TLP的整包接收、严格格式检查、结构化分派及
Completion编码。模块只在完整EOP提交后产生副作用，支持内部Cfg/UR/CA与外部K09
Completion仲裁，并向K06提供TX信用元数据和逐Packet RX信用释放事件。

本阶段没有实现配置寄存器、BDF/BAR命中、MSE、AXI4-Lite、MPS/RCB拆分、DMA或
主动Memory Request；这些边界保持在K08/K09及后续集成阶段。

## 2. 交付文件

| 文件 | 职责 |
|---|---|
| `rtl/tl/pcie_tlp_codec.sv` | 生产TLP解码、校验、分派、Completion编码和统计 |
| `rtl/tl/k07_tlp_codec_ooc_top.sv` | 仅用于KU040 OOC签核，重建K01四级复位同步链 |
| `sim/verilator/k07/test_pcie_tlp_codec.py` | Driver、BFM、Monitor、Scoreboard及12项测试 |
| `sim/verilator/k07/check_counter_saturation.py` | 审计11个计数器及全部15条饱和增量路径 |
| `sim/verilator/k07/pcie_tlp_codec_bad_stub.sv` | 故意在整包提交前分派Cfg的错误DUT |
| `fpga/kcu105/run_k07_tlp_codec_ooc.tcl` | 250 MHz OOC综合、时序、CDC、DRC和资源检查 |
| `fpga/kcu105/run_k07_tlp_codec_ooc.sh` | 日志、Warning精确Allowlist及报告门禁 |

架构、接口和RTL前验证计划分别保存在`docs/architecture`、`docs/interfaces`和
`docs/verification`目录。

## 3. 架构实现结果

- RX使用一个144 Byte原始整包槽和一个128 Byte对齐Payload槽；EOP前所有结构化
  输出`valid=0`；
- `PARSE`将深组合合法性结果锁存，`DISPATCH`下一拍更新计数和分派，外部只增加
  1个`core_clk`延迟；
- 原始Packet、对齐Payload和TX Packet数据阵列不复位，有效性完全由异步置位、
  同步释放复位覆盖的状态/长度寄存器限定；
- 支持CfgRd0/CfgWr0、MemRd32/64、MemWr32/64、Cpl/CplD；
- 语法完整的Unsupported NP生成一个UR，Unsupported Posted静默丢弃，Malformed
  不生成Completion；
- TX内部Completion优先于外部描述符，Packet开始后锁定到EOP；CplD最大32 DW。

## 4. Checker、Lint与回归

错误Stub在首拍就寄存`cfg_req_valid`，`whole_packet_commit_guard`成功把它记录为
JUnit failure；根目标只有检测到该预期失败才输出：

```text
K07_CHECKER_SELFTEST_PASS
```

生产RTL及OOC包装层均通过Verilator 5.020 `--lint-only -Wall`，结果为0 Error、
0未说明Warning。所有输出`ready`以固定种子独立抽取1～4个反压周期，并在每个stall
周期检查字段稳定。动态验证使用cocotb 1.9.2和cocotbext-pcie 0.2.16：

| 测试 | 主要覆盖 | 结果 |
|---|---|---:|
| `whole_packet_commit_guard` | EOP前无副作用 | PASS |
| `cfg_decode_and_completion_encode` | Cfg字段、SC/UR/CRS/CA和Cpl/CplD | PASS |
| `memory_decode_and_payload` | 3DW/4DW、零BE、地址及Payload | PASS |
| `completion_decode_and_external_encode` | 入站解码与外部编码逐Byte比对 | PASS |
| `malformed_unsupported_and_release` | Poisoned CfgWr→CA、额外Payload、错误优先级及信用释放 | PASS |
| `unsupported_feature_matrix` | Type-1、I/O、Locked、Atomic、AT=01/10、Message、Prefix | PASS |
| `completion_boundary_and_encoder_validation` | Byte Count、Lower Address低2位、长度及drain | PASS |
| `stream_errors_overflow_and_reset` | 短Header、重复SOP、keep、超长包及五类复位点 | PASS |
| `internal_priority_arbitration` | 内部Completion优先、外部请求不丢失 | PASS |
| `randomized_cfg_completion_reference` | 10,000个合法Cfg/Cpl参考对象 | PASS |
| `randomized_raw_malformed_validator` | 5,000合法+5,000非法Raw Packet | PASS |
| `randomized_memory_headers` | 2,000个合法3DW/4DW Memory Packet | PASS |

固定种子为`20260806`，最终结果：

```text
TESTS=12 PASS=12 FAIL=0 SKIP=0
K07_VERILATOR_PASS tests=12 legal_random=10000 raw_random=10000 \
memory_random=2000 seed=20260806
```

Raw混合测试使用不依赖DUT解析结果的模式化独立判定器，预测正常分派、Unsupported
NP的UR、Unsupported Posted丢弃及Malformed丢弃；它不是通用Raw TLP解析器。合法
TLP的可观察字段与`Tlp`对象逐项比较，TX Packet则与`Tlp.pack()`逐Byte比较。

Verilator VPI可观察`force`值，但`release`后不能可靠保留被测寄存器在强制期间的内部
更新，因此没有把该行为记为动态饱和覆盖。最终采用独立可执行结构审计：确认
`sat_inc32=(&value)?value:value+1`，并枚举11个32-bit计数器的全部赋值；每个计数器
只有唯一复位置零或自身`sat_inc32`增量，共核对15条增量路径：

```text
K07_COUNTER_SATURATION_AUDIT_PASS counters=11 increment_paths=15 function=sat_inc32
```

## 5. KU040 OOC签核

目标器件为`xcku040-ffva1156-2-e`，时钟约束4.000 ns。最终综合结果：

| 项目 | 结果 |
|---|---:|
| WNS / TNS / Setup失败端点 | `+0.659 ns / 0.000 ns / 0` |
| WHS / THS | `+0.094 ns / 0.000 ns` |
| CLB LUT / LUT Primitive / FF / CARRY8 | `2117 / 2781 / 3837 / 50` |
| BRAM / DSP / PCIe Hard Block | `0 / 0 / 0` |
| 无时钟寄存器 / 未约束内部端点 | `0 / 0` |
| TX `valid`可达性 | 两个`tx_state`寄存器均为实际扇入，非综合网表常量 |
| CDC | 1×`CDC-9 Info`，0 Warning/Critical |
| DRC | 1×`CFGBVS-1 Warning`，0 Error/Critical |

普通Warning精确限定为`Netlist 29-101`×1、`Synth 8-6779`×1、
`Synth 8-7080`×1和`Timing 38-242`×2；任何数量变化、任何Critical Warning或
Error都使构建失败。`Synth 8-6779`是OOC未布局条件下wire-load采用默认延迟模型，
K11完整实现重新签核。`rx_mem/rx_payload_flat/tx_words`均为无复位数据阵列，最终
日志没有`Synth 8-7137`。

初次OOC暴露的解析公共CE路径为负时序；将Payload改为无条件对齐搬运并加入
`PARSE -> DISPATCH`一级流水后，1184+162个失败端点归零。该结果是综合网表OOC
估算，K11仍必须在完整PHY/Core时钟树下重新布局布线。

## 6. 已知限制与延期

- 单槽、单Outstanding顺序实现，不保证连续每拍接收Packet；
- RX原始TLP最多144 Byte；MemWr和CplD最多32 DW，MemRd最多1024 DW；
- 只支持8-bit Tag、单Function、VC0和冻结支持矩阵；
- Verilator VPI不支持可信的计数器边界回写；饱和行为以独立结构审计签核，后续若
  引入形式验证环境可补充动态/形式证明；
- K11需为K06 Packet与信用元数据增加原子异步适配器，M02-v1接口本阶段不修改；
- VCS编译兼容性继续受`VCSCompiler_Net`许可证影响，经用户批准延期，最迟K11前
  补测；
- K07没有独立实板门禁，当前未插KCU105不阻塞冻结；枚举从K08开始，Gen1整链路
  上板验收属于K11。

## 7. 冻结决定

`K07-TLP-CODEC-v1`的职责边界、普通端口、Byte顺序、支持矩阵、错误动作、单槽深度、
Completion仲裁和信用事件语义全部冻结。K07七步门禁已完成；本次停止在K07，未开始
K08配置空间RTL。
