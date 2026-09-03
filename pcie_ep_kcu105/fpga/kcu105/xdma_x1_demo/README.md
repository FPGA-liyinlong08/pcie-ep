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
- `make xdma-x1-svt-vcs`：将官方 XDMA EP 的 PCIe serial lane 0 接到
  Synopsys SVT Root Port，执行 Gen3 x1 链路训练并要求
  `XDMA_SVT_GEN3_L0_PASS` 与跨 8192 PIPE 周期的
  `XDMA_SVT_L0_STABLE_PASS`；默认生成统一 `PHY_FORENSICS` 取证行（可用
  `XDMA_X1_SVT_FORENSICS=0` 关闭）；
- `make xdma-x1-hw-program`：通过本机`localhost:3122` JTAG下载x1对照bitstream。

SVT testbench 位于 `sim/vcs_svt/xdma_x1_svt_*`。它复用 `build/example/xdma_x1_ex`
中的官方 GT、XDMA 和 `xilinx_dma_pcie_ep.sv`，只在仿真顶层替换 Root Port；生成的
VCS/VIP 临时文件写入 `sim/vcs_svt/build_xdma_x1/`，不进入 Git。运行前需配置
Synopsys VCS/SVT license 与 Vivado VCS simlib。

Golden/K15 的取证日志可用
`python3 sim/vcs_svt/analyze_phy_forensics.py <simulate.log>` 做同格式统计，
根因 A/B 记录见 `docs/reports/xdma-svt-k15-ab-root-cause-20260903.md`。

2026-08-10实板结果：Linux枚举到`10ee:9031`，链路为8 GT/s x1，Gen3均衡Phase
1～3全部完成，AER状态全零，XDMA驱动成功绑定。详细证据见
`docs/reports/k11b3-kcu105-hardware.md`。
