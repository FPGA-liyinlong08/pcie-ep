# K09 BAR0-to-AXI4-Lite 阶段冻结报告

日期：2026-08-09

状态：**PASS / K09-BAR-AXIL-v1 已冻结**

接口版本：`K09-BAR-AXIL-v1`

## 1. 阶段结论

K09已经实现生产模块`pcie_bar_axil_master`，完成4 KiB BAR0命中、Posted Memory
Write逐DWORD AXI4-Lite访问、Memory Read逐DWORD读取、128 B Completion分段、
Byte Count/Lower Address计算及UR/CA错误转换。

错误Stub自检有效，生产RTL的9项单模块回归全部通过，固定种子
`20260807`的100,000请求随机反压回归通过，生产K07+K08+K09的真实TLP级枚举与MMIO
集成测试通过，Verilator严格lint和13个饱和计数器结构审计通过。KU040 250 MHz OOC
完整综合、布局布线、时序、CDC、DRC及Warning精确白名单门禁通过，并以原子方式发布
最终`summary.txt`；K09七步门禁全部完成。

## 2. 七步门禁执行状态

| 门禁 | 证据 | 状态 |
|---|---|---:|
| 1. 架构冻结 | `docs/architecture/k09-bar-axil-master.md`，冻结职责、状态机、缓冲、错误动作及拆分算法 | PASS |
| 2. 接口冻结 | `docs/interfaces/k09-bar-axil-master-interfaces.md`，冻结K07 Memory、K07 Completion、K08状态和32-bit AXI4-Lite端口 | PASS |
| 3. RTL前仿真计划冻结 | `docs/verification/k09-verification-plan.md`，冻结BFM、参考模型、Stub、directed、随机、断言和验收标准 | PASS |
| 4. 先建立测试平台 | 独立模型、Driver、AXI BFM、Completion Sink、Scoreboard和错误Stub均用于生产RTL门禁 | PASS |
| 5. 编写RTL | `rtl/tl/pcie_bar_axil_master.sv`，范围未提前扩展到K10/DMA/MSI | PASS |
| 6. 模块验证 | Stub、lint、9项单元、100,000随机、计数器审计、TLP集成及KU040 250 MHz routed OOC全部通过 | PASS |
| 7. 模块冻结 | 接口版本、回归结果、OOC时序/资源/CDC/DRC/Warning和已知限制均已保存 | PASS |

该表是冻结状态的唯一判定依据。`run_k09_bar_axil_ooc.sh`只有在全部后置门禁通过后才
把候选摘要原子发布为`summary.txt`；失败运行会删除候选和旧摘要，避免中间DCP被误认
为PASS。最终摘要还使用`K09_REUSE_BUILD=1`独立复验一次，结果一致。

## 3. 交付文件与RTL架构

| 文件 | 职责 |
|---|---|
| `rtl/tl/pcie_bar_axil_master.sv` | 生产BAR命中、AXI访问、Completion拆分及统计 |
| `rtl/tl/k09_bar_axil_ooc_top.sv` | KU040 OOC复位与端口包装 |
| `sim/verilator/k09/k09_model.py` | 独立Byte Count、BE、分段和Completion参考模型 |
| `sim/verilator/k09/test_pcie_bar_axil_master.py` | Driver、AXI BFM、Completion Sink、Scoreboard及9项测试 |
| `sim/verilator/k09/pcie_bar_axil_master_bad_stub.sv` | 地址、WSTRB和Posted Completion故意错误的Stub |
| `sim/verilator/k09/check_counter_saturation.py` | 13个计数器和15条增量路径结构审计 |
| `sim/verilator/k09/run_k09.sh` | Stub、生产JUnit和随机证据门禁 |
| `sim/verilator/k09_integration/k09_tlp_test_top.sv` | 生产K07+K08+K09集成顶层 |
| `sim/verilator/k09_integration/k09_simport_adapter.py` | RootComplex到128-bit TLP Packet Stream适配 |
| `sim/verilator/k09_integration/test_k09_tlp_integration.py` | 枚举、MMIO、分段、UR和CA集成测试 |
| `fpga/kcu105/run_k09_bar_axil_ooc.tcl` | 250 MHz综合、布局布线、时序、CDC、DRC及资源报告 |
| `fpga/kcu105/run_k09_bar_axil_ooc.sh` | OOC产物、Warning和签核字段门禁 |

生产RTL采用单Memory Request、单AXI事务顺序架构：

- Write侧以一个128-bit Payload Beat缓存最多4个DWORD；AW和W独立握手，每个DWORD
  等待B响应后才推进；
- Read侧使用`32 × 32-bit`、不复位Chunk Buffer，先完成一个最多128 B Chunk的全部
  AXI读取，再向K07提交该CplD；
- BAR、Probe、MSE、Requester/Tag/TC/Attr和Completer ID在Memory描述符握手时锁存；
- `hot_reset`阻止新描述符，不取消已握手事务；PERST#异步取消全部状态、valid、脉冲
  和统计；
- AXI地址为BAR相对地址，高20位固定0，Payload和AXI数据保持小端Byte顺序；
- 所有输出valid支持无限反压，AW/W不假定同拍Ready，不形成组合
  `valid-ready-valid`环路。

## 4. 接口与协议实现结果

### 4.1 BAR及Memory Write

- BAR0固定4 KiB、32-bit、non-prefetchable；命中要求MSE有效、非Probe、完整请求范围
  位于同一BAR窗口且地址高32位为0；
- 4DW Header但实际地址低于4 GiB的请求允许命中，AXI只看到BAR相对偏移；
- Write支持1～32 DW；Length=1使用FirstBE，多DW首/中/末分别使用
  FirstBE/`4'hf`/LastBE；
- 零长度Write消费Payload但无AXI副作用、无错误、无Completion；
- BAR miss、MSE关闭、Probe、Poisoned、非法范围及Payload错误均进入Drain；
- AXI `SLVERR/DECERR`保留错误前已经完成的Posted副作用，停止后续AXI访问并Drain剩余
  Payload；任何Write路径都不生成PCIe Completion。

### 4.2 Memory Read及Completion

- Read支持1～1024 DW，固定MPS=128 B，每个CplD为1～32 DW；
- Endpoint作为Completer的RCB固定128 B；K08的RCB和MRRS不用于限制入站Memory
  Read；
- 首包可同时覆盖原请求起点并跨过一个RCB；需要拆分时非末包终止于自然128 B边界，
  后续CplD的Lower Address固定0；
- Byte Count按首个有效Byte到最后有效Byte的地址跨度计算，不使用BE popcount；非连续
  BE中间空洞仍计入跨度；
- 首包Lower Address为`RequestAddress + FirstBE最低置位偏移`的低7位；逻辑Byte
  Count 4096交给K07编码为线路值0；
- 首尾BE无效Byte以及非连续BE空洞在Completion Payload中确定性清零；
- 零长度Read不访问AXI，返回一个dummy零DWORD，`Length=1、Byte Count=1`；
- BAR/MSE/Probe/范围失败的Read返回一个无数据UR；Poisoned Read及AXI Read
  `SLVERR/DECERR`返回无数据CA；
- 一个Chunk在全部AXI读成功前不发送SC。若后续Chunk发生错误，已完整发送的前序SC
  保留，随后用一个CA终止剩余请求，不发送失败Chunk的半包。

## 5. 错误Stub、自检与静态审计

错误Stub能完成有限握手，但故意实现三项独立错误：AXI地址偏移`+4`、WSTRB恒为
`4'hf`、Posted Write错误地产生Completion。生产测试中的同一个`checker_guard`
观察到三个具体差异，负向JUnit按预期失败，marker精确为：

```text
K09_NEGATIVE_CHECKER_OBSERVED address be posted
K09_CHECKER_SELFTEST_PASS address=1 be=1 posted=1
```

脚本在生产回归前删除旧marker并显式设置`K09_NEGATIVE_STUB=0`；编译错误、超时、缺少
任一守卫、旧JUnit或空测试均不能冒充自检通过。

当前生产模块和K07+K08+K09集成顶层分别通过Verilator 5.020：

```text
verilator --lint-only -Wall ... pcie_bar_axil_master.sv       : PASS
verilator --lint-only -Wall ... k09_tlp_test_top.sv           : PASS
ERROR=0 WARNING=0
```

由于Verilator VPI不适合作为计数器临界值回写证明，采用可执行结构审计枚举所有赋值。
13个32-bit计数器只能由异步复位置零或由统一`sat_inc32`对自身饱和加一，共核对15条
增量路径：

```text
K09_COUNTER_SATURATION_AUDIT_PASS counters=13 increment_paths=15
```

## 6. 九项单模块回归

正式回归生成的JUnit为`sim/verilator/k09/results.xml`（不纳入版本管理），随机种子
`20260807`，9项全部PASS，无failure、error或skip：

| 测试 | 主要覆盖 | 结果 |
|---|---|---:|
| `checker_guard` | 生产RTL地址、部分BE及Posted无Completion守卫 | PASS |
| `reference_model_exhaustive` | 1DW全部16种BE、2DW 15×15 BE跨度及关键分段 | PASS |
| `zero_length_and_bar_error_paths` | 零长度读写、BAR/MSE/Probe/high64/范围UR、BAR上下界 | PASS |
| `directed_memory_writes` | 1/2/5/32 DW、WSTRB、AW/W反压、EXOKAY、B错误及Drain | PASS |
| `directed_memory_reads_and_splits` | 非连续BE、33/40/1024 DW、MPS/RCB/4 KiB、BC/Lower | PASS |
| `axi_read_errors_hot_reset_and_snapshot` | R错误首/中/末、前序SC后CA、Hot Reset与配置快照 | PASS |
| `payload_protocol_error_is_contained` | keep/last错误、旧副作用保留、错误Beat后无新访问 | PASS |
| `perst_cancels_all_inflight_states` | IDLE、Write、AW/W/B、AR/R、Cpl描述符/Payload异步复位 | PASS |
| `randomized_100k_reference` | 独立模型、随机反压、错误注入和100,000请求 | PASS |

最后一项仿真时间为`5,577,170.001 ns`，JUnit墙钟约`299.855 s`。生产脚本同时检查
测试数必须等于9、必须存在100k测试、JUnit不得失败、negative marker不得残留且随机
证据必须匹配固定种子和规模。

## 7. 100,000请求随机签核

回归生成证据`sim/verilator/k09/k09_random_evidence.txt`（不纳入版本管理）的原文为：

```text
K09_RANDOM_SIGNOFF seed=20260807 requests=100000 random_ready=1 max_delay=3 ur=10155 ca=684 axi_reads=131764 axi_writes=107430 axi_write_errors=770 poisoned_writes=1341
```

因此正式签核数字为：

| 项目 | 数量 |
|---|---:|
| Memory Request | 100,000 |
| Read / Write | 45,991 / 54,009 |
| BAR地址命中 / miss | 81,928 / 18,072 |
| 4DW格式请求 / 高32位非零miss | 28,640 / 4,637 |
| Probe / MSE关闭 | 2,085 / 2,076 |
| 零长度Read / Write | 1,475 / 1,816 |
| Poisoned Write | 1,341 |
| UR / CA | 10,155 / 684 |
| AXI Read / Write响应 | 131,764 / 107,430 |
| AXI Write Error | 770 |

其中请求类型及场景数量由与正式测试相同的固定seed生成序列复核；UR、CA、AXI访问、
AXI写错误和Poisoned数量同时由证据文件及DUT计数器断言确认。随机BFM对AWREADY、
WREADY、ARREADY、BVALID、RVALID以及Completion描述符/Payload Ready独立施加反压，
响应延迟范围为0～3拍。

长包不是仅由Directed覆盖。随机回归还断言长度桶15、16、17、31、32、33、255、
256、1023及1024 DW均至少命中一次；每1,000个事务把AXI BFM完整4 KiB内存与独立
Byte模型比较，结束时再次全空间比较，并检查无多余AXI访问或Completion。

## 8. K07+K08+K09真实TLP级集成

集成平台实例化生产K07、生产K08和生产K09，不创建Python Endpoint Function。
`cocotbext-pcie 0.2.16` RootComplex经SimPort发送真实Cfg/Mem TLP，K07解码请求，K08
完成枚举与BAR配置，K09执行AXI访问，再由K07编码Completion返回RootComplex。

回归生成的`sim/verilator/k09_integration/results_k09_integration.xml`（不纳入版本管理）
结果为1/1 PASS：

| 项目 | 结果 |
|---|---|
| 枚举 | 发现`01:00.0`，Vendor/Device=`1234:e001` |
| BAR0 | 探测为4 KiB，分配地址4 KiB对齐，`enable_device()`后MSE=1 |
| MMIO Write/Read | 8/16/32-bit及20 Byte多DWORD访问逐Byte读回一致 |
| 128 B边界Read | 地址偏移`0x07c`、33 DW拆为`1+32 DW` |
| Split字段 | Byte Count=`132,128`，Lower Address=`0x7c,0`，均为SC |
| BAR miss | 一个无数据UR，且AXI Read计数不增加 |
| AXI Read错误 | 一个无数据CA |
| AXI计数 | Write=8，Read=42 |
| K07错误 | malformed、unsupported、TX protocol error均为0 |

集成JUnit仿真时间为`5,356.001 ns`，墙钟约`0.403 s`。这证明结构化Memory接口、BAR
配置状态和通用Completion接口在生产模块间逐字段兼容；它不替代K11的DLL/PHY/VCS
串行链路和Linux实板测试。

## 9. KU040 Vivado OOC签核

目标器件固定为`xcku040-ffva1156-2-e`，目标时钟4.000 ns。同步接口I/O delay max
为1.000 ns；另用4.000 ns datapath-only max约束排除OOC虚假时钟偏差，因此输入和
输出两向留给K09的净数据路径预算均为3.000 ns。以下数字全部来自同一次最终routed
运行及其原子发布摘要，没有拼接中间或失败运行数据。

| 项目 | 最终结果 |
|---|---:|
| OOC脚本最终标记 | `K09_VIVADO_PASS` |
| Implementation状态 | `ROUTED`；routing error=0 |
| WNS / TNS | `+0.140 ns / 0.000 ns` |
| WHS / THS | `+0.044 ns / 0.000 ns` |
| 接口Input / Output Setup Slack | `+0.140 / +0.244 ns` |
| 接口Input / Output最大数据路径 | `2.812 / 2.756 ns` |
| 接口Input / Output Hold Slack | `+0.306 / +0.534 ns` |
| 接口Input / Output最小数据路径 | `0.183 / 0.164 ns` |
| 内部FF-to-FF WNS / WHS | `+0.152 / +0.044 ns` |
| Setup / Hold失败端点 | `0 / 0` |
| no_clock / unconstrained internal | `0 / 0` |
| no/partial Input Delay | `0 / 0` |
| no/partial Output Delay | `0 / 0` |
| LUT Primitive / FF / BRAM | `1191 / 1873 / 0` |
| DSP / PCIe Hard Block | `0 / 0` |
| 动态Partition Pin端口 | `1062`；常量/未连接端口不施加虚假Partition Pin |
| 关键输出动态扇入 | busy=`4`、AWVALID=`1`、ARVALID=`1`、Cpl desc/data valid=`5/5` |
| CDC | `All paths are Safely Timed.`；0 Warning/Critical |
| DRC | 仅`CFGBVS-1 ×1`；0 Error/Critical，K11板级属性消除 |
| Vivado普通Warning Allowlist | `Netlist 29-101 ×1`、`Synth 8-6779 ×1`、`Synth 8-7080 ×1` |

输入侧显式`MinDelay=-1.000 ns`只补偿OOC虚拟输入端缺失的父层共享BUFG source
insertion（最终报告中的DCD约0.984 ns）；输出侧`MinDelay=0.000 ns`。两向报告的Timing
Exception均为`MinDelay Path`，不存在`False Path`。这里的`-1 ns`不是硬件接口允许的
真实负hold预算；K11使用完整共享时钟树时必须移除这项OOC补偿并重新检查setup/hold。

构建脚本对普通Warning的ID和数量做精确比较。新增Warning、数量变化、任何Critical
Warning或Error、负Slack、未约束/partial端口、routing error或关键输出被裁常量，都会
删除候选/最终摘要并使门禁失败，不能通过放宽已知限制绕过。

## 10. 实施中闭合的问题

1. **RCB职责纠偏**：原阶段描述容易把K08 Link Control.RCB直接用于Endpoint出站
   Completion。冻结架构改为Endpoint Completer固定128 B，后续Lower Address固定0；
   K08 RCB和MRRS保留给未来主动Requester，不进入K09接口。
2. **Byte Count语义**：明确从BE popcount改为有效地址跨度，并用1DW全部16种及2DW
   15×15组合穷举，覆盖非连续BE空洞与零长度Read。
3. **Write推进修正**：一个128-bit Beat内各DWORD已经在每个B响应后逐个推进；Beat结束
   只再推进最后一个DWORD，避免地址/索引重复增加整拍DWORD数。
4. **Read错误原子性**：一个Chunk全部AXI读成功后才允许SC描述符，消除同一Chunk先发
   半包再遇错误的路径；跨Chunk时保留已完成SC并以CA结束后续部分。
5. **Payload错误收敛**：keep/last错误Beat不产生AXI副作用，之前正确Beat的Posted
   副作用保留，随后Drain到last，且全程禁止Completion。
6. **复位覆盖补强**：逐一覆盖AW未握手、仅AW、仅W、等待B、等待AR/R、Completion
   描述符和Payload等状态，证明异步PERST立即取消全部可见事务与计数。
7. **无复位Read Buffer**：数据阵列写口从异步复位主状态机分离，避免综合成大规模复位
   网络；状态、长度和valid保证复位后的旧内容永远不可见。
8. **门禁证据防污染**：错误Stub marker、JUnit测试数量和100k证据均由脚本精确检查，
   生产运行显式清除负向环境，防止旧结果或短回归冒充冻结签核。
9. **OOC接口时序建模**：动态端口才分配局部Partition Pin，避免常量网络产生routing
   error；显式输入`-1 ns`MinDelay透明补偿缺失共享时钟插入延迟，清除max-delay隐含
   hold false-path，并把取消补偿后的真实共享时钟复验固定为K11门禁。
10. **摘要原子发布**：Tcl只写`summary_candidate.txt`，Shell完成产物、时序、CDC、
    DRC、路由及Warning全部检查后才重命名；任何失败均删除候选和旧摘要。

## 11. 已知限制与延期

- 单Memory Request、单AXI事务顺序执行，不支持乱序、多Outstanding或连续每拍吞吐；
- 只有4 KiB、32-bit BAR0和32-bit AXI4-Lite；Read最多1024 DW，Write最多32 DW；
- MPS固定128 B，Endpoint Completion RCB固定128 B；不支持运行时增大MPS；
- Read Payload中的BE无效Byte确定性清零；AXI每次仍只执行完整32-bit Read；
- Posted Write错误没有PCIe Completion；在错误响应前已完成的DWORD副作用不可回滚；
- Hot Reset不取消已接受事务，集成层必须保证链路级复位/Flush策略与本快照语义协调；
- 不实现DMA、MSI/MSI-X、AER、ASPM、SR-IOV、原子操作或主动Memory Request；
- TLP级集成没有经过K03～K06的PHY/MAC/DLL，因此不等同于Gen1/Gen3串行链路验收；
- VCS仍受`VCSCompiler_Net`许可证延期影响；当前未插KCU105，串行仿真和实板验证按
  已批准记录延期至K11/K13对应门禁；
- 本阶段的`-1 ns`输入MinDelay仅是OOC建模补偿，K11完整集成不得继承；必须使用真实
  `phy_coreclk`共享时钟树重检接口setup/hold。

## 12. 冻结决定

`K09-BAR-AXIL-v1`的RTL架构、普通端口、BAR相对地址、BE/WSTRB、单Outstanding、
128 B拆分、Byte Count/Lower Address、Posted/UR/CA动作和复位快照语义已经完成代码与
动态验证，可以保持接口冻结。

第1～7步全部通过，`K09-BAR-AXIL-v1`正式冻结。K10仍未开始；进入K10时继续执行同一
七步门禁，不修改本阶段已冻结接口。VCS串行和实板项目仍按既有批准记录在K11/K13
对应集成门禁补齐。
