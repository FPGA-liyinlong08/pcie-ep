# K09 BAR0-to-AXI4-Lite RTL 前验证计划

状态：**PASS / K09-BAR-AXIL-v1 验证计划已执行并冻结**

错误Stub、单模块BFM/Scoreboard、10万请求随机反压、K07+K08+K09真实TLP级集成和
KU040 OOC均已执行；证据汇总见`docs/reports/k09-bar-axil-master.md`。

## 1. 验证目标

在不依赖K10 Demo Slave和完整PHY/DLL的条件下证明：BAR范围/MSE判断、每DWORD AXI
访问、BE/WSTRB、Completion拆分、Byte Count/Lower Address、错误转换、Posted语义和
所有反压行为符合冻结架构。生产RTL必须在错误Stub自检成功后才能创建。

## 2. 测试平台

### 2.1 单模块平台

- `MemRequestDriver`：先发结构化描述符，再按K07规则发送128-bit Write Payload；
- `AxiLiteSlaveBfm`：AWREADY/WREADY独立随机，随机B/R延迟，维护4 KiB逐Byte内存，
  可按地址或事务序号注入SLVERR/DECERR；
- `CompletionSink`：独立随机描述符和Payload反压，重组每个Cpl/CplD；
- `K09ReferenceModel`：只根据请求、BAR/Probe/MSE和初始内存计算期望AXI访问及Completion；
- `CycleMonitor`：逐周期检查valid稳定、AW/W配对、AR/R配对、一请求的完成/Drain边界；
- `Scoreboard`：逐Byte比对AXI副作用、WSTRB、Completion字段与Payload。

参考模型不得读取DUT内部状态，也不得调用RTL辅助函数。随机种子固定为`20260807`，
失败日志必须打印请求地址、Length、BE、BAR、RCB、分段号和AXI握手历史。

### 2.2 K07+K08+K09 TLP级平台

复用K08 SimPort适配方式，Root Port发真实MemRd/MemWr TLP，经生产K07解码、生产K09
AXI访问和生产K07 Completion编码返回。K08生产配置空间先完成BAR探测/分配/MSE使能；
AXI端仍接测试BFM，不实例化K10。该平台至少完成8/16/32-bit和多DWORDMMIO、128 B边界
读及UR/CA。K11之前不宣称PHY/DLL/Linux完整集成。

## 3. 错误Stub自检

`pcie_bar_axil_master_bad_stub.sv`必须能完成有限握手，但故意包含三项独立错误：

1. AXI地址固定偏移`+4`；
2. 所有Write的WSTRB错误固定为`4'hf`；
3. Posted Write错误地产生Completion。

先运行`checker_guard`：一项部分BE Write必须同时观察到`address/be/posted`三项具体
错误，JUnit必须为预期FAIL；脚本只在marker精确包含三项且不是编译失败/超时后打印
`K09_CHECKER_SELFTEST_PASS address=1 be=1 posted=1`。随后删除marker并切回生产顶层；
旧结果、任意其他failure或空测试不得冒充通过。

## 4. Directed测试

### 4.1 BAR与Posted Write

- BAR基址0、非0和接近32-bit顶部；Probe/MSE开/关；32-bit及高32位为0的4DW地址；
- 首地址命中但末地址越过BAR、首地址在BAR前后、Length 0/越界防御输入；
- Write Length 1～32 DW；Length=1遍历FirstBE 0～15；多DW遍历First/LastBE组合；
- AW先、W先、同拍、各自1～64拍反压；B响应延迟和OKAY/EXOKAY；
- 零长度Write必须Drain且无AXI/Completion/错误；BAR miss、Probe、MSE关闭和Poisoned
  必须Drain且无AXI或Completion；Payload keep/last错误保留错误发现前已经完成的AXI
  副作用，错误Beat及之后不得再访问，并且仍不得产生Completion；
- 中间DWORD注入SLVERR/DECERR，之前副作用保留，之后不再访问，剩余PayloadDrain；
- 全部Write路径断言`cpl_req_valid`从不因该请求出现。

### 4.2 Read与Completion

- Length 1、2、3、4、15、16、17、31、32、33、1023、1024 DW；
- 起始地址覆盖RCB前1 DW、RCB对齐、64/128 B中点、BAR最后DWORD；
- 固定Endpoint RCB=128 B，覆盖首包也是末包可跨RCB，以及多包只能在自然128 B边界
  分段；同时覆盖MPS=128边界及4 KiB最后Chunk；
- Length=1遍历FirstBE 0～15；零长度Read必须为BC=1/Length=1/dummy零DWORD且不访问
  AXI；多DW遍历首尾BE，包括非连续BE的确定性零填充；
- 每个Chunk核对Length、剩余Byte Count、Lower Address、Requester/Tag/TC/Attr；
- AR和R分别1～64拍反压；Completion descriptor/payload分别1～64拍反压；
- 任意Chunk首/中/末DWORD注入SLVERR/DECERR，只产生一个无数据CA且不发送SC半包；
- BAR miss/Probe/MSE关闭/范围错误只产生一个无数据UR且不访问AXI。

### 4.3 复位与配置变化

- PERST#分别在IDLE、描述符、Write Beat、AW/W部分握手、B等待、AR等待、R等待、
  Completion descriptor和payload位置注入；释放后无旧valid或旧Completion；
- Hot Reset在IDLE阻止请求；在已握手事务中改变BAR/Probe/MSE/BDF，当前事务仍使用快照，
  下一请求使用复位后的配置；
- 反压期间逐位检查所有输出稳定。

## 5. 随机与错误注入

- 正式随机回归至少100,000个Memory Request，Read/Write、32/64-bit Header、BAR hit/
  miss、Probe、MSE、First/LastBE、地址和Length交叉随机；
- 为控制运行时间，随机Length采用分层分布：大多数1～8 DW，边界桶覆盖15/16/17、
  31/32/33和255/256/1023/1024；大长度完整数据路径由Directed保证；
- 每个AXI和Completion通道独立随机反压；至少1%事务注入R/B错误，至少1%为Poison；
- Scoreboard最终要求AXI内存逐Byte一致、无多余/遗漏访问、无多余/遗漏Completion；
- 追加多种固定seed冒烟；正式冻结数字以seed`20260807`为准。

## 6. 断言与覆盖

断言至少包括：

- `mem_req`、`mem_w`、Completion和五个AXI通道反压稳定；
- AW和W各握手一次后才接受一个B，AR握手一次后才接受一个R；
- AXI地址DWORD对齐且高20位0，WSTRB不为0；
- SC CplD Length为1～32、keep连续、Payload DW数精确；UR/CA无Payload；
- 非首末Split只能在自然128 B RCB分段；Completion不超过MPS且不跨4 KiB；Byte Count
  按地址跨度单调递减，SC头部不得为0，内部remaining在末包后归零；
- Posted Write永不产生Completion；Drop/Poison不产生AXI副作用；
- 复位后valid清零；计数饱和不回绕。

覆盖必须闭合：Read/Write×hit/miss/MSE、Length桶、15种FirstBE、15种LastBE、
128 B RCB×起始对齐类型、1/多Completion、AW/W先后关系、所有B/R响应、错误所在
Chunk/位置、PERST位置、Hot Reset快照及每类诊断脉冲。

## 7. 静态检查、综合与通过标准

- Verilator 5.020严格`-Wall`：0 Error，Warning必须修复或解释；
- KU040 OOC目标4.000 ns，所有同步边界端口显式max/min delay；
- WNS/WHS不小于0，TNS/THS为0；无失败端点、无未约束/无delay/partial delay端口；
- K09无CDC、DSP和PCIe Hard Block；Read缓存综合成FF/LUTRAM/BRAM均允许，但报告冻结；
- Vivado 0 Error、0 Critical Warning；普通Warning按ID和数量精确Allowlist；
- 错误Stub、全部Directed、100,000随机、K07+K08+K09 TLP级测试全部通过；
- 保存JUnit、随机统计、时序/CDC/DRC/资源报告和已知限制后才能冻结K09。

VCS许可证与当前未插KCU105的延期继续保留，不阻塞K09单模块/TLP级冻结；K09冻结前
不得创建K10 Demo AXI4-Lite Slave生产RTL。
