create_clock -name tl_clk_250 -period 4.000 [get_ports clk]
set_false_path -from [get_ports rst_n]
