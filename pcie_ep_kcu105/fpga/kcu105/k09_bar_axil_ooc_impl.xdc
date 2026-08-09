# 仅用于OOC implementation的上下文约束。与综合约束分离，避免综合器丢弃
# -hold和partition-pin后在propImpl重放时产生不完整约束。

# Core clock在K02/K03完整PHY实现中的实际源为BUFG_GT_X0Y26。该上下文属性让
# OOC timing使用与最终顶层一致的clock insertion/skew估计。
set_property HD.CLK_SRC BUFG_GT_X0Y26 [get_ports clk]

# 虚拟端口无法表达父层launch/capture FF与本模块共享的clock
# insertion。分向datapath-only max-delay排除虚假skew：输入侧的4.00 ns
# requirement包含1.00 ns input delay，因此内部数据路径净预算为3.00 ns；
# 输出侧同样使用4.00 ns requirement，扣除1.00 ns output delay后净预算也为
# 3.00 ns。Vivado 2021.2的set_min_delay不支持-datapath_only；输入侧用
# -1.00 ns显式补偿OOC模型缺失的父层共享BUFG source insertion，输出侧仍为
# 0 ns。`-reset_path`清除datapath-only max-delay隐含的hold false-path，route
# 必须实际检查这些MinDelay路径。-1 ns不是硬件接口负hold预算，K11必须取消
# 该OOC补偿并在真实共享时钟树重检。内部FF-to-FF hold仍严格检查。
set_max_delay 4.000 -datapath_only -from \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}] \
    -to [all_registers]
set_max_delay 4.000 -datapath_only -from [all_registers] -to \
    [get_ports -filter {DIRECTION == OUT}]
set_min_delay -reset_path -1.000 -from \
    [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}] \
    -to [all_registers]
set_min_delay -reset_path 0.000 -from [all_registers] -to \
    [get_ports -filter {DIRECTION == OUT}]

# OOC端口没有封装IOB；K02/K03完整实现中phy_coreclk所在Clock Region X3Y1的
# SLICE范围为X76Y60:X100Y119。把普通数据端口partition pin约束在该真实局部区域，
# route_design会路由接口线段，同时避免使用全芯片范围制造不现实的长边界路径。
# 已被生产逻辑优化掉的契约字段和常量输出不需要partition pin，否则会把
# GLOBAL_LOGIC0/1误报成含未放置pin的routing error。主Tcl在综合网表上筛选
# 真实动态net后施加HD.PARTPIN_RANGE；clk只使用上面的HD.CLK_SRC上下文。
