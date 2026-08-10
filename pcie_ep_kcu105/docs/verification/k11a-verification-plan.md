# K11-A RTL前仿真计划

## 1. 测试层次

1. CDC桥单元：双异步时钟、随机Packet、随机反压、TX元数据和RX信用事件scoreboard；
2. TLP/Core：复用K08～K10生产链路完成枚举序列、BAR探测/分配和Demo读写；
3. DLL级：Data Link Partner完成InitFC、注入带Sequence/LCRC的Cfg/Memory TLP，检查
   Completion、ACK/NAK和Replay；
4. PHY Partner：复用K03训练模型到Gen1 L0，再连接DLL级事务；
5. Vivado：KU040完整共享时钟树下综合、实现、CDC、DRC、资源和时序检查。

## 2. 测试平台先行

先建立`pcie_tlp_async_bridge_bad_stub`。错误Stub故意把所有TX元数据改成零；测试必须
产生JUnit failure并留下`K11A_NEGATIVE_CHECKER_OBSERVED metadata`证据，随后才允许
编译生产桥。

## 3. Directed与随机项

- 单拍/多拍Packet、SOP/EOP、全部末拍keep和错误字段；
- TX元数据分别覆盖P/NP/Cpl及0～32个Data Credit；
- PIPE/Core时钟62.5/125/250 MHz组合及独立随机反压；
- 元数据先到、Packet先到、FIFO接近满、复位发生在SOP/中间/EOP；
- 配置枚举、BAR全1探测、MSE、签名、Scratch byte strobe、RAM边界；
- 坏LCRC、Duplicate、NAK、ACK丢失、Replay timeout和Hot Reset。

## 4. 断言和通过标准

- EOP前Packet不可跨域提交；
- TX Packet与元数据一一对应，信用释放不丢失、不重复、不乱序；
- stall期间所有输出稳定，无overflow/underflow；
- 生产RTL严格lint通过；现有K02～K10离线回归不退化；
- 完整KU040实现WNS/WHS均不小于0；定向CDC无Critical，Warning必须逐项归入冻结
  Allowlist；DRC无Error/Critical且Warning必须有解释；
- VCS真实串行和实板项明确记为K11-B延期，不伪记PASS。
