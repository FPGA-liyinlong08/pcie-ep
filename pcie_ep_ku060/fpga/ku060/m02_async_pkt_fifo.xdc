# M02 独立 OOC 综合约束：以 RX Gen1（写 62.5 MHz、读 250 MHz）为代表。
create_clock -name m02_s_clk -period 16.000 [get_ports s_clk]
create_clock -name m02_m_clk -period 4.000  [get_ports m_clk]

set_clock_groups -asynchronous \
    -group [get_clocks m02_s_clk] \
    -group [get_clocks m02_m_clk]

