# M01 独立综合使用的时钟和管脚约束。
# GT TX/RXOUTCLK 在 M03 集成前暂作为顶层输入；此处按 Gen1 最慢周期约束。

create_clock -name sys_clk_100          -period 10.000 [get_ports sys_clk_100]
create_clock -name pcie_refclk_100      -period 10.000 [get_ports pcie_refclk_p]
create_clock -name gt_txoutclk_gen1     -period 16.000 [get_ports gt_txoutclk]
create_clock -name gt_rxoutclk_gen1     -period 16.000 [get_ports gt_rxoutclk]

set_property PACKAGE_PIN P6  [get_ports pcie_refclk_p]
set_property PACKAGE_PIN P26 [get_ports sys_clk_100]
set_property PACKAGE_PIN L24 [get_ports pcie_perst_n]
set_property IOSTANDARD LVCMOS18 [get_ports {sys_clk_100 pcie_perst_n}]

# 四个根时钟没有固定相位关系。MMCM 生成的 Core 时钟自动归入 sys_clk_100 组。
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk_100] \
    -group [get_clocks pcie_refclk_100] \
    -group [get_clocks gt_txoutclk_gen1] \
    -group [get_clocks gt_rxoutclk_gen1]

