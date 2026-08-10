# K08 Type-0 配置空间 RTL 前验证计划

状态：**K08-CFG-SPACE-v1 验证计划已执行并冻结**

本文在生产 RTL 编写前冻结。验证对象为`pcie_cfg_space`，以及生产版
`pcie_tlp_codec + pcie_cfg_space`的 TLP 级集成路径。完整 LTSSM、DLL、PHY、VCS 串行
链路和 Linux/实板枚举仍属于 K11，不作为 K08 的完成条件。

## 1. 参考模型与通过原则

Python 参考模型维护独立的 1024-DWORD 配置空间规则表。每项记录复位值、只读掩码、
普通可写掩码、动态掩码和 BAR 特殊行为；模型不得复制 RTL 的`case`表达式或调用 DUT
内部信号。固定随机种子为`20260807`，失败时报告种子、BDF、DWORD地址、BE、写数据、
预期值和实测值。

所有用例必须满足：

- 每个接受的请求恰好产生一个响应；PERST#取消事务，Hot Reset不取消已有响应；
- SC、UR、读数据、Completer ID和全部状态输出与模型逐拍一致；
- 响应反压时字段稳定，不丢请求、不重复响应、无组合Ready/Valid环；
- 生产回归0 failure、0 error、0 skip；错误Stub回归必须产生指定断言失败而非超时。

## 2. 测试平台分层

### 2.1 K08单模块平台

结构化配置 BFM 直接驱动 K07 已冻结的`cfg_req_*`接口，响应Monitor和Scoreboard检查
`cfg_rsp_*`及所有状态输出。Driver随机化请求间隔，Monitor独立随机化`cfg_rsp_ready`。

该层负责逐位寄存器、所有Byte Enable、BDF、BAR探测、复位、反压和十万事务随机回归，
不依赖`cocotbext-pcie`对寄存器位属性的实现。

### 2.2 K07+K08集成平台

测试顶层只实例化生产版`pcie_tlp_codec`和`pcie_cfg_space`：

```text
RootComplex RootPort
  <-> cocotb测试用SimPort适配器
  <-> 128-bit TLP Packet Stream
  <-> pcie_tlp_codec
  <-> pcie_cfg_space
```

Root Complex必须通过`rc.make_port()`建立Root Port。下行Type-1请求由Root Port按拓扑转换
为Type-0后，适配器以`Tlp.pack()`送入K07；K07生成的Completion经`Tlp.unpack()`送回
SimPort。禁止创建Python`Device/Function`替代RTL配置空间。

此层证明真实TLP级配置发现、Capability遍历和BAR分配，明确不声称完成K03～K06链路
或串行PHY验证。

## 3. 错误Stub自检

先建立与生产模块同端口的`pcie_cfg_space_bad_stub`，它及时完成握手但故意：

1. Vendor/Device ID返回错误值；
2. BAR0写全1后返回`ffff_ffff`而不是`ffff_f000`；
3. 忽略Byte Enable，执行全DWORD写入。

专用`identity_and_bar_probe_guard`用例必须在正常时限内因值比较失败，并在独立JUnit中
产生`<failure>`。运行脚本只有识别到该指定失败才打印`K08_CHECKER_SELFTEST_PASS`；
超时、编译失败或测试未执行均视为门禁失败。生产RTL运行同一用例必须通过。

## 4. Directed用例

### 4.1 复位和完整镜像

- 对PERST#进行异步置位、同步释放后读取全部1024个DWORD；
- 固定头、PCIe Capability与冻结表逐位一致；
- `0x074～0xfff`及其他未实现区域全部读0，写入后仍为0；
- 检查BDF、Command、BAR0、Device/Link Control及全部输出复位值。

### 4.2 逐位属性和Byte Enable

- 1024个DWORD分别执行one-hot/one-cold写读；实现寄存器的每一位都被0和1写入；
- Command、Device Control、Link Control、Link Control 2和BAR0遍历16种BE；
- 只读位、保留位和相邻DWORD不得受写操作污染；
- `be=0`写返回SC且无副作用；配置读的BE不改变完整DWORD返回值；MPS字段写入后仍为0，
  MRRS仅接受0～5，写入6/7保持旧值。

### 4.3 BDF和Completion路由

- 首个Function 0请求捕获完整BDF并返回SC，Device Number必须覆盖非零值；Requester ID
  变化不得改变本地BDF；
- 捕获后分别改变Bus、Device和Function，均返回UR且写请求无副作用；
- 首次Function非0请求返回UR且不捕获，随后任意Device的Function 0仍可捕获；
- 每类响应检查`cfg_rsp_completer_id`和`local_completer_id`；
- PERST#、Hot Reset后可重新捕获，普通Retrain/Recovery不得改变BDF。

### 4.4 BAR0

- 保存原基址，完整写全1，确认读回`ffff_f000`且真实`bar0_base`不变；
- 写入多组对齐/非对齐地址，确认低12位永远为0并退出探测；
- 部分BE写按字节合并，未选Byte保持；重复probe/恢复/重新分配；
- BAR1～5和Expansion ROM写全1仍读0；
- BAR探测与MSE交叉，确认`bar0_probe_active`和真实基址独立。

### 4.5 PCIe Capability和动态状态

- Capability Pointer=`0x40`，PCIe Capability链终止，Version 2/Endpoint；
- MPSS=128 B、最大速率Gen3、最大宽度x1，无ASPM/FLR/MSI/MSI-X；
- 遍历Link Down、Gen1/2/3、width 0/1、Training和DLL Active组合；
- Link Control持久位按掩码保存；写Retrain bit只产生一拍脉冲；
- Target Link Speed仅接受线路编码1/2/3并映射为内部0/1/2。

### 4.6 握手、复位和错误时序

- 请求间隔与响应Ready独立随机，响应可反压1～64拍；
- 响应stall期间检查`valid/status/rdata/completer_id`逐位稳定；
- PERST#分别在空闲、请求前后和响应stall期间注入，旧响应与副作用均不得泄漏；
- Hot Reset在空闲时清配置并阻止请求；在响应stall时保持旧响应到握手，同时配置状态
  立即复位；Hot Reset与`cfg_rsp_ready=1`同拍时，既有响应正常完成一次握手；
- 普通Link Down、Recovery等价状态和速率变化不得清除配置；
- 非法`link_speed=3`只按Gen1报告，不破坏配置状态。

## 5. 随机测试与错误注入

生产回归至少执行100,000个随机配置事务，地址覆盖0～1023，BE覆盖0～15，并加权访问
Command、BAR0、PCIe Capability和未实现区域。随机维度包括读写、数据、BDF匹配关系、
请求空闲周期、响应反压、Hot Reset、PERST#和链路状态变化。

Scoreboard同时维护寄存器模型、BDF状态和响应队列，检查无丢失、重复、乱序或意外副作用。
错误注入至少覆盖：Function非0、Bus/Device错配、BAR非对齐写、无效Target Speed、复位中
请求和响应stall期间Hot Reset。

## 6. Root Complex枚举用例

使用本机`cocotbext-pcie 0.2.16`实际执行`RootComplex.enumerate()`，验收：

- 通过Root Port发现典型`01:00.0`单Function Type-0 Endpoint；
- Vendor/Device为`1234:e001`，Class为`ff0000`；
- PCIe Capability位于`0x40`，报告Gen3 x1和MPS 128 B；
- BAR0探测尺寸为4 KiB，分配地址4 KiB对齐；BAR1～5和ROM未实现；
- 分配结束后RTL的`bar0_base`等于RC配置值，探测状态已退出；
- `enumerate()`后显式执行`enable_device()`或配置Command.MSE，再检查
  `memory_space_enable=1`。

Root Complex模型自身的配置空间不得进入响应路径。该用例通过仅称为“K07+K08 TLP级
枚举通过”，不得记为Linux、VCS串行或实板枚举。

## 7. 断言与覆盖

断言至少包括：

- `valid && !ready`时接口字段稳定；
- 每次请求握手有且仅有一次响应，响应不得凭空出现；
- `bdf_valid`置位后除PERST#/Hot Reset外保持，UR不得改变配置状态；
- BAR0低12位恒0，probe读值精确，MSE只由Command bit1改变；
- RO/保留位不变，普通链路变化不清配置；
- Hot Reset期间`cfg_req_ready=0`，已存在响应保持；只有PERST#后要求`cfg_rsp_valid=0`。

覆盖必须闭合：1024个DWORD、每DWORD 32个bit、BE 0～15、RO/RW/动态/特殊类型、
BAR reset/base/probe/restore/assigned与MSE交叉、BDF未捕获/匹配/Bus错/Device错/Function错、
PERST#/Hot Reset与idle/request/response-stall交叉，以及RC发现、Capability遍历、BAR探测、
恢复、分配和MSE使能各阶段。

## 8. 静态检查、综合和完成标准

- Verilator 5.020严格lint：0 Error，Warning必须解释或修复；
- KU040 OOC器件固定`xcku040-ffva1156-2-e`，时钟4.000 ns；
- 同步输入明确约束为`0.25～1.00 ns`，同步输出预留`1.00 ns`setup预算；
- WNS/WHS不小于0，TNS/THS为0，无失败端点、无未约束内部端点；
- `no_input_delay/no_output_delay/partial_input_delay/partial_output_delay`全部为0；
- K08无内部CDC、BRAM、DSP和PCIe Hard Block；OOC包装的复位同步链只允许已解释CDC；
- Vivado为0 Error、0 Critical Warning；普通Warning按ID和数量建立精确allowlist；
- 错误Stub自检、全部directed、100,000随机事务、K07+K08 TLP级枚举全部通过；
- 保存JUnit、覆盖统计、Vivado时序/资源/CDC/DRC及阶段报告后才冻结K08。

VCS许可证和实板验证继续按延期记录处理，不阻塞K08。K08冻结前不得创建任何K09
BAR Memory、Completion拆分或AXI4-Lite生产RTL。
