create_clock -name demo_clk_250 -period 4.000 [get_ports clk]

# 1 ns相邻逻辑预算，K10获得3 ns净数据路径预算。
set_input_delay -clock demo_clk_250 -max 1.000 \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}]
set_input_delay -clock demo_clk_250 -min 0.250 \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}]
set_input_delay -clock demo_clk_250 -max 1.000 [get_ports rst_n]
set_input_delay -clock demo_clk_250 -min 0.250 [get_ports rst_n]
set_output_delay -clock demo_clk_250 -max 1.000 [all_outputs]
set_output_delay -clock demo_clk_250 -min 0.000 [all_outputs]
set_false_path -from [get_ports rst_n]
