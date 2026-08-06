# K07 TLP Codec RTL前验证计划

状态：**仿真计划已冻结，先于生产RTL建立**

固定随机种子：`20260806`。主要参考模型为本机`cocotbext-pcie 0.2.16`的
`Tlp.pack()/unpack()`；其`Tlp.check()`存在已确认的Length、Cfg集合判断缺陷，
`get_lower_address()`也存在运算优先级问题，因此只用于合法包的字段/Byte参考。
非法包按生成模式由本项目独立Python判定器给出期望动作；它不依赖DUT解析结果，
但不是面向任意Byte串的通用TLP解析器。

## 1. Testbench结构

```text
Tlp对象/Raw非法包生成器 -> RX Packet Driver -> DUT
                                  |              |-> Cfg BFM
                                  |              |-> Memory Scoreboard
                                  |              |-> RX Completion Scoreboard
Cfg响应 / Completion BFM --------+--------------|-> TX Packet Monitor
                                                 `-> FC/错误/统计Checker
```

- Driver随机化包间空闲、每拍`valid`和复位；
- 各`ready`独立随机反压，Monitor检查stall稳定；
- TX Monitor按`keep`还原Byte串，再由`Tlp.unpack()`逐字段检查；
- 每个RX Packet维护唯一流水号，Scoreboard检查恰好一个release和唯一分派动作；
- 测试结果输出JUnit，超时必须是FAIL而非SKIP。

## 2. 错误Stub自检

在生产RTL前建立同端口`pcie_tlp_codec`坏Stub。Stub在Cfg SOP握手后寄存输出
`cfg_req_valid`，不等待EOP，也不正确解码字段。测试向其发送完整Cfg首拍后在末拍
注入错误，Checker必须发现“整包提交前产生配置副作用”或字段不匹配并生成JUnit
failure。根Makefile只有确认`<failure>`存在时才打印：

```text
K07_CHECKER_SELFTEST_PASS
```

这一步证明测试平台能发现本阶段最关键的提前分派错误。

## 3. Directed用例

### 3.1 Cfg

- CfgRd0/CfgWr0，全部16种First BE，Requester/Target BDF、Tag、TC、Attr逐字段；
- SC Read生成CplD且数据逐Byte正确，SC Write生成Cpl；
- UR、CRS、CA响应状态保持，无Payload；
- Cfg响应延迟和TX反压；第二个Cfg不得越过第一个；
- Length非1、LastBE非0、地址保留位、短/长Payload和Poisoned Cfg Write。

### 3.2 Memory

- 3DW/4DW Read：1、2、32、1024 DW；Wire Length=0映射1024；
- 3DW/4DW Write：1、2、31、32 DW，Header/Payload跨128-bit拍；
- First/Last BE、零长度BE访问、非连续BE逐位透明；
- `0xffc + 1DW`合法，`0xffc + 2DW`非法；1024 DW仅页内偏移0合法；
- 33 DW Write、Payload少/多1 DW、地址低位、Descriptor/Payload反压；
- Poisoned Write必须置标志和计数。

### 3.3 Completion解码与编码

- Cpl以及1、2、31、32 DW CplD；SC/UR/CRS/CA和BCM；
- Byte Count=1、4、128、4096，Lower Address所有边界；
- 外部Completion编码逐Byte匹配`Tlp.pack()`；
- CplD非SC、保留Status、Payload长度不匹配、无数据却EP；
- Cfg内部Completion与外部Completion同时到达时验证内部优先且不打断Packet。

### 3.4 Unsupported与错误注入

- Cfg Type-1、I/O、Locked、Atomic合法NP均生成一个UR；
- Message和其他Posted Unsupported只丢弃，不生成Completion；
- TD、TH、AT=01/10、Prefix进入Unsupported；AT=11和Tag[9:8]进入Malformed；
- 未知Fmt/Type、短Header、重复SOP、非法keep、上游`error`、超过144 Byte；
- SOP、中间拍、EOP、Cfg等待和Completion Payload期间复位，复位后无旧事务；
- Malformed+Poisoned组合只按Malformed动作，禁止Cfg/Memory副作用。

## 4. 随机回归

- 10,000个合法Cfg/Cpl Packet：字段与`Tlp`对象逐项相等；
- 2,000个合法3DW/4DW Memory Packet：描述符和Payload逐项相等；
- 10,000个语法合法/非法各5,000的Raw Packet：模式化独立判定器预测正常分派、
  Unsupported NP的UR、Unsupported Posted丢弃或Malformed丢弃；
- 长度重点采样Wire 0、1、2、31、32、33和1024；
- 三类下游反压、TX反压、Cfg响应延迟及Payload节拍独立随机；
- 所有随机测试保存seed，失败必须可用单条命令复现。

若cocotb运行时间不适合更大规模，额外Native C++测试扩展到100,000个Header；
Native只能补充吞吐签核，不能替代cocotb接口回归。

## 5. 断言与Checker

必须检查：

- `valid&&!ready`期间所有字段稳定；
- EOP提交前Cfg/Memory/Cpl `valid=0`；
- Descriptor握手先于对应Payload；
- 配置空间最多一个Outstanding；
- TX非末拍`keep=ffff`，末拍keep连续，SOP/EOP唯一；
- TX Packet Byte数与Header Length一致，元数据与Packet一一对应；
- 每个完整RX Packet恰好一个release，类型/credits逐位匹配K06算法；
- Malformed不产生Cfg/Memory/UR，Unsupported Posted不产生Completion；
- UR只针对语法完整、Requester/Tag可信的NP请求；
- 计数器不回绕，复位后valid和统计均为0。

若Verilator VPI不能可信地把计数器预置到`32'hffff_fffe`并保留强制期间的内部更新，
不得把`force/release`记为动态覆盖；必须由可执行结构审计逐一枚举所有计数器赋值，
证明除复位置零外全部调用同一个饱和加一函数，且没有遗漏或旁路增量路径。

## 6. 覆盖点

- Fmt/Type × 3DW/4DW × Data/NoData；
- Length边界 × First/Last BE × 4 KiB边界；
- Cpl Status × Byte Count编码0/非0 × Lower Address；
- Cfg/Memory/Cpl × 无反压/描述符反压/Payload反压/TX反压；
- Malformed/Unsupported/Poisoned/Unexpected四类错误；
- 12/16 Byte Header、Header/Payload跨拍、140/144 Byte最大包；
- 内部/外部Completion仲裁和复位清空路径。

## 7. 工具签核和通过标准

1. 错误Stub必须被Checker检出；
2. Verilator 5.020 `--lint-only -Wall`为0 Error、0未说明Warning；
3. cocotb全部directed和随机测试PASS，JUnit无failure；
4. `cocotbext-pcie`合法包逐字段及TX逐Byte一致；
5. KU040 OOC目标`xcku040-ffva1156-2-e`、4.000 ns，WNS不小于0、TNS为0；
6. Vivado 0 Error、0 Critical Warning；普通Warning按ID/数量精确Allowlist；
7. CDC无Warning/Critical，不使用DSP和PCIe Hard Block；
8. 保存测试、覆盖、资源、时序、已知限制和延期记录。

VCS仍沿用已批准的`VCSCompiler_Net`许可证延期，最迟K11前补测。K07不是上板门禁，
不因当前未插KCU105而阻塞；本阶段不得开始K08 RTL。
