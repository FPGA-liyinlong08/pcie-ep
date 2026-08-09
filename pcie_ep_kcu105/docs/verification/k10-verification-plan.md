# K10 Demo AXI4-Lite Slave RTL前仿真计划

状态：**PASS / K10-DEMO-AXIL-v1 仿真计划已执行并冻结**

## 1. 测试平台

- cocotb AXI4-Lite Master Driver：AW/W独立发送并随机改变先后关系；
- Monitor：记录所有握手、响应稳定性和写副作用；
- 独立Python Byte模型：实现地址表、WSTRB、Scratch复位及RAM先写后读语义；
- Scoreboard：逐次比较RDATA/RRESP/BRESP和完整Scratch/RAM镜像；
- 错误Stub：故意交换签名、忽略WSTRB并把越界访问错误返回OKAY；
- K09+K10集成：生产K09接生产K10，结构化Memory请求完成签名、Scratch和RAM访问。

## 2. Stub自检

在生产RTL回归前，对同一组checker运行错误Stub。必须得到预期失败JUnit，并同时记录：

```text
K10_NEGATIVE_CHECKER_OBSERVED signature strobe decerr
```

少一个守卫、测试意外PASS、旧marker残留或JUnit缺失均使门禁失败。

## 3. Directed测试

1. 读签名、版本、链路/LTSSM/DLL状态和12个计数器；
2. 对全部48个Scratch执行全WSTRB、16种WSTRB、walking-one及只读写保护；
3. 对960个RAM DWORD先写后读，执行walking-one、地址数据和随机数据；
4. AW先、W先、同拍，AW/W间隔及B反压；
5. AR/R反压，RVALID期间改变ARADDR和状态输入，验证响应稳定；
6. 未对齐和4 KiB外读写DECERR且无副作用；保留区读0/写忽略返回OKAY；
7. 在AW pending、W pending、BVALID、RVALID时随机PERST；验证事务取消和Scratch清零；
8. RAM复位后不读取旧值，只证明重新写入后数据正确且阵列没有复位网。

## 4. 随机、断言与覆盖

- 固定seed `20260810`，至少100,000个混合读写；地址覆盖RO、Scratch、RAM、保留、
  未对齐和越界；AW/W顺序及0～5拍延迟随机；BREADY/RREADY随机反压；
- 每1,000事务全量比较48个Scratch和960个已初始化RAM位置；
- 断言valid反压稳定、每组AW+W恰有一个B、每个AR恰有一个R、只读/错误写无副作用、
  WSTRB=0无副作用、无组合valid-ready-valid环；
- 覆盖16种WSTRB、全部1008个可写DWORD、四种复位中断状态、两个DECERR方向。

## 5. 静态和实现签核

- Verilator 5.020 `--lint-only -Wall`零Warning；Python `py_compile`通过；
- Vivado 2021.2对`xcku040-ffva1156-2-e`执行250 MHz OOC综合和布局布线；
- 测试RAM必须推断至少一个RAMB primitive，DSP和PCIe Hard Block必须为0；
- `check_timing`无未约束/partial端口，setup/hold非负，routing error=0；
- 单时钟设计CDC必须安全；普通Warning按K10精确Allowlist，Critical/Error为0。

## 6. 通过标准

错误Stub、全部Directed、100,000随机事务、生产K09+K10集成、严格lint、计数/覆盖检查
及KU040 OOC全部PASS后，才能形成`K10-DEMO-AXIL-v1`冻结报告。VCS串行和实板访问
属于K11，不作为K10单模块冻结的替代条件。
