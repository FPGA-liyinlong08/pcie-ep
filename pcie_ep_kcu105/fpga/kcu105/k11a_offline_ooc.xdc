create_clock -name pipe_clk -period 8.000 [get_ports pipe_clk]
create_clock -name core_clk -period 4.000 [get_ports core_clk]
set_clock_groups -asynchronous -group [get_clocks pipe_clk] -group [get_clocks core_clk]
set_property HD.CLK_SRC BUFG_GT_X0Y25 [get_ports pipe_clk]
set_property HD.CLK_SRC BUFG_GT_X0Y26 [get_ports core_clk]

# K11-A顶层边界在K03 MAC Packet接口，最终实现中两侧使用同一个phy_pclk；配置状态
# 同样来自共享phy_coreclk域。OOC若把这些partition pin当成封装I/O，会人为制造不存在的
# clock-insertion setup/hold路径。因此本阶段只签核内部reg-to-reg与FIFO CDC，真实边界随
# K02/K03/PHY共享时钟树在K11-B签核。
set nonclock_inputs [get_ports -filter {DIRECTION == IN && NAME != pipe_clk && NAME != core_clk}]
set data_outputs [get_ports -filter {DIRECTION == OUT}]
set_false_path -from $nonclock_inputs
set_false_path -to $data_outputs
