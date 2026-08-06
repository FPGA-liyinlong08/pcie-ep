# K01 的 KCU105 板级管脚与时钟约束。
set_property PACKAGE_PIN AB6 [get_ports pcie_refclk_p]
set_property PACKAGE_PIN AB5 [get_ports pcie_refclk_n]
set_property PACKAGE_PIN K22 [get_ports pcie_perst_n]

set_property IOSTANDARD LVCMOS18 [get_ports pcie_perst_n]
set_property PULLUP true [get_ports pcie_perst_n]

set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]

create_clock -name pcie_refclk_100 -period 10.000 [get_ports pcie_refclk_p]
create_clock -name phy_pclk_gen3   -period 4.000  [get_ports phy_pclk]
create_clock -name phy_coreclk_250 -period 4.000  [get_ports phy_coreclk]

set_clock_groups -asynchronous \
    -group [get_clocks pcie_refclk_100] \
    -group [get_clocks phy_pclk_gen3] \
    -group [get_clocks phy_coreclk_250]

# 两个输入是异步复位源；同步释放由 ASYNC_REG 移位链保证。
set_false_path -from [get_ports pcie_perst_n]
set_false_path -from [get_ports phy_phystatus_rst]
set_false_path -to [get_ports {pipe_rst_n core_rst_n}]
