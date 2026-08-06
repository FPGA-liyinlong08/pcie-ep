# K00 对复用 M02 FIFO 执行 KU040 OOC 综合时的代表性约束：
# 写侧采用 Gen1 phy_pclk（62.5 MHz），读侧采用 phy_coreclk（250 MHz）。
create_clock -name k00_m02_s_clk -period 16.000 [get_ports s_clk]
create_clock -name k00_m02_m_clk -period 4.000  [get_ports m_clk]

set_clock_groups -asynchronous \
    -group [get_clocks k00_m02_s_clk] \
    -group [get_clocks k00_m02_m_clk]
