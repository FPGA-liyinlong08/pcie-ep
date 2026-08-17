# K02 KCU105 standalone PCIe PHY x1 板级约束。
set_property PACKAGE_PIN AB6 [get_ports pcie_refclk_p]
set_property PACKAGE_PIN AB5 [get_ports pcie_refclk_n]
set_property PACKAGE_PIN K22 [get_ports pcie_perst_n]

set_property PACKAGE_PIN AB2 [get_ports pcie_rxp]
set_property PACKAGE_PIN AB1 [get_ports pcie_rxn]
set_property PACKAGE_PIN AC4 [get_ports pcie_txp]
set_property PACKAGE_PIN AC3 [get_ports pcie_txn]

set_property PACKAGE_PIN AP8 [get_ports {led[0]}]
set_property PACKAGE_PIN H23 [get_ports {led[1]}]
set_property PACKAGE_PIN P20 [get_ports {led[2]}]
set_property PACKAGE_PIN P21 [get_ports {led[3]}]
set_property PACKAGE_PIN N22 [get_ports {led[4]}]
set_property PACKAGE_PIN M22 [get_ports {led[5]}]
set_property PACKAGE_PIN R23 [get_ports {led[6]}]
set_property PACKAGE_PIN P23 [get_ports {led[7]}]

set_property IOSTANDARD LVCMOS18 [get_ports pcie_perst_n]
set_property PULLUP true [get_ports pcie_perst_n]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]

set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]

create_clock -name pcie_refclk_100 -period 10.000 [get_ports pcie_refclk_p]

# PERST# 是异步复位源；同步释放由 K01 四级同步链完成。
set_false_path -from [get_ports pcie_perst_n]
set_false_path -to [get_ports {led[*]}]
