create_clock -name bar_clk_250 -period 4.000 [get_ports clk]

# K09全部功能端口均属于250 MHz Core域。OOC边界用max 1.00 ns表示
# 相邻模块的launch/capture寄存器、Tco/setup和局部布线预算；在4.00 ns
# 周期下，自然为K09保留约3.00 ns数据路径预算。实现XDC另用
# datapath-only max-delay排除OOC边界虚假clock skew：输入总预算4.00 ns，
# 输出总预算4.00 ns；两向均再扣除1.00 ns I/O delay而得到3.00 ns净数据
# 路径预算。HD.CLK_SRC只知道本模块capture clock的位置，不知道父层launch FF
# 与本模块共享的约1 ns BUFG插入延迟；implementation XDC对输入侧施加-1 ns
# 显式OOC补偿、输出侧施加0 ns min-delay，并清除隐式hold false-path。-1 ns
# 不是硬件接口允许的负hold预算。最终K11完整集成必须取消该OOC补偿，在真实
# 共享时钟树上重新检查；内部FF-to-FF setup/hold始终严格检查。
set_input_delay -clock bar_clk_250 -max 1.000 \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}]
set_input_delay -clock bar_clk_250 -min 0.250 \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}]
set_input_delay -clock bar_clk_250 -max 1.000 [get_ports rst_n]
set_input_delay -clock bar_clk_250 -min 0.250 [get_ports rst_n]
set_output_delay -clock bar_clk_250 -max 1.000 [all_outputs]
set_output_delay -clock bar_clk_250 -min 0.000 [all_outputs]

# rst_n仅作为异步置位入口；同步释放路径由包装层四级ASYNC_REG链检查。
set_false_path -from [get_ports rst_n]
