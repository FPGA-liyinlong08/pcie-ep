# K11-A Gen1 Endpoint 离线集成报告

状态：**PASS / K11A-OFFLINE-INTEGRATION-v1 已冻结；K11-B未完成**

## 1. 冻结范围

K11-A在K03的16-bit MAC Packet边界以上集成生产K06 DLL、双向异步Packet FIFO、
TX信用元数据、RX信用归还、K07 TLP Codec、K08配置空间、K09 BAR Master和K10 Demo
AXI-Lite Slave。真实standalone `pcie_phy`、K03训练动态行为、VCS串行模型和KCU105
实板均不在本次PASS范围内。

接口版本为`K11A-INTEGRATION-v1`，冻结顶层为可综合的`k11a_offline_top`。

## 2. 实现结果

- 新增`pcie_tlp_async_bridge`，保持M02-v1 Packet接口不变；
- TX Packet与`type/data_credits`使用独立事件FIFO并在PIPE域按Packet原子配对；
- RX信用归还通过反压事件FIFO回到PIPE域；
- PIPE域链路/DLL诊断使用143-bit请求/应答原子快照进入Core域；
- Hot Reset通过toggle事件同步器形成Core域单拍，不触发全局复位；
- 外部冻结`afifo.v`不修改源码，Vivado脚本为其200个Gray同步寄存器补全
  `ASYNC_REG/SHREG_EXTRACT`实现属性。

定向CDC检查最初发现DLL计数器直接跨域读取，已经修正为原子快照；修正后的完整
事务回归和KU040实现重新执行并通过。

## 3. 仿真与门禁

| 门禁 | 结果 | 证据摘要 |
|---|---|---|
| 错误Stub自检 | PASS | 故意破坏TX元数据，checker按预期失败并留下metadata标记 |
| CDC桥生产RTL | PASS | 2/2；100个随机Packet、双向反压、元数据和信用归还一致 |
| K11-A完整离线路径 | PASS | DLL InitFC/Active、Cfg Read、BAR写入、MSE、Demo签名和Hot Reset |
| 严格Verilator lint | PASS | 0 Error，0 Warning |
| K09集成回归 | PASS | 真实TLP级RC枚举与MMIO，`cfg=43`、`cpl=51` |
| K10集成回归 | PASS | 签名、状态、Scratch和RAM |

完整离线路径读取到Vendor/Device `1234:e001`，BAR0设置为`0x80000000`后读取
`0x50434945`签名；Hot Reset后BAR0和Memory Space Enable恢复复位值，DLL保持Active，
CDC sticky error为零。

## 4. KU040实现结果

器件：`xcku040-ffva1156-2-e`。OOC时钟为`pipe_clk=125 MHz`、
`core_clk=250 MHz`。

| 项目 | 结果 |
|---|---:|
| WNS / TNS | `+0.001 ns / 0.000 ns` |
| WHS / THS | `+0.022 ns / 0.000 ns` |
| 未布线/部分布线网络 | `0 / 0` |
| LUT / FF | `9250 / 9650` |
| DRC Error / Critical Warning | `0 / 0` |

WNS虽为正但余量仅1 ps；这是离线OOC结果，不代表带PHY后的K11-B时序已经签核。

## 5. CDC与Warning Allowlist

定向`pipe_clk→core_clk`和`core_clk→pipe_clk`报告均为0 Critical。冻结Allowlist：

- `CDC-6`：每方向6组，均为冻结`afifo.v`的Gray指针多位同步；同步寄存器已设置
  `ASYNC_REG`，Gray码约束由FIFO结构和M02随机/回绕验证保证；
- `CDC-15`：PIPE→Core的143位为握手保护的稳定快照总线；Core→PIPE的20位为异步
  FIFO双口存储器读出结构；
- `Route 35-198`：离线OOC边界未指定`HD.PARTPIN_LOCS`，只影响边界部分布线；
- `CFGBVS-1`：离线协议OOC未设置板级配置电压；
- `RTSTAT-10`：OOC顶层输出没有板外可路由负载。

新增CDC类型、Critical或不属于上述层次的Warning均视为失败。

## 6. 延期与下一步

K11整体尚未冻结。K11-B仍须完成：

1. 把K02 standalone PHY、K03 LTSSM/MAC和本次核心接入真正的KCU105板级顶层；
2. VCS许可证已恢复并通过K02真IP门禁；继续建立K03/K11-B真PHY串行训练平台；
3. KCU105达到Gen1 x1 L0和DLL Active；
4. Linux完成枚举、BAR0访问、20次冷启动和100次PERST#/重训；
5. 对包含PHY共享时钟树的完整设计重新签核时序、CDC和DRC。

在K11-B完成前不得开始K12，也不得把K11标记为PASS。
