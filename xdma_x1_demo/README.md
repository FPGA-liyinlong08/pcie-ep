# KCU105 XDMA Gen3 x1 对照工程

本目录只用于K11上板物理链路A/B验证：

- 器件：`xcku040-ffva1156-2-e`；
- XDMA：Vivado 2021.2 `xdma v4.1`；
- 链路：Gen3 x1；
- PCIe REFCLK：100 MHz；
- GT Quad：225；
- Vendor/Device：`10ee:9031`。

生成物全部位于`build/`，不提交Git。该工程不属于自研Endpoint RTL，也不作为协议
实现基础，只证明KCU105 Lane 0、REFCLK、PERST#、插槽和Root Port能够使用Xilinx官方
Endpoint逻辑建立链路。

执行命令：

- `make xdma-x1-demo`：重新生成、实现并检查官方示例工程；
- `make xdma-x1-hw-program`：通过本机`localhost:3122` JTAG下载x1对照bitstream。

2026-08-10实板结果：Linux枚举到`10ee:9031`，链路为8 GT/s x1，Gen3均衡Phase
1～3全部完成，AER状态全零，XDMA驱动成功绑定。详细证据见
`docs/reports/k11b3-kcu105-hardware.md`。
