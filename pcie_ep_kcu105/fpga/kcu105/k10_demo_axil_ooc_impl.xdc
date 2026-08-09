# K02/K03 phy_coreclk实际BUFG_GT位置；K11完整共享时钟树重新签核。
set_property HD.CLK_SRC BUFG_GT_X0Y26 [get_ports clk]
set_max_delay 4.000 -datapath_only -from \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}] \
    -to [all_registers]
set_max_delay 4.000 -datapath_only -from [all_registers] -to \
    [get_ports -filter {DIRECTION == OUT}]
# -1 ns仅补偿OOC缺失的父层共享BUFG source insertion，不是硬件负hold预算。
set_min_delay -reset_path -1.000 -from \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}] \
    -to [all_registers]
set_min_delay -reset_path 0.000 -from [all_registers] -to \
    [get_ports -filter {DIRECTION == OUT}]
