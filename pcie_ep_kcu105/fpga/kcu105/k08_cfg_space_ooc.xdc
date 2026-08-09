create_clock -name cfg_clk_250 -period 4.000 [get_ports clk]

# K08全部功能端口都属于同一个250 MHz Core域。OOC边界为上游路径预留
# 0.25~1.00 ns（launch寄存器Tco与局部布线），下游预留1.00 ns setup预算；
# 同时覆盖max/min delay，确保输入到寄存器和寄存器到输出路径都参与签核。
set_input_delay -clock cfg_clk_250 -max 1.000 [get_ports {
    rst_n hot_reset link_up link_training dll_active
    link_speed[*] link_width[*]
    cfg_req_valid cfg_req_write cfg_req_dw_addr[*] cfg_req_be[*]
    cfg_req_wdata[*] cfg_req_requester_id[*] cfg_req_tag[*]
    cfg_req_target_bdf[*] cfg_rsp_ready
}]
set_input_delay -clock cfg_clk_250 -min 0.250 [get_ports {
    rst_n hot_reset link_up link_training dll_active
    link_speed[*] link_width[*]
    cfg_req_valid cfg_req_write cfg_req_dw_addr[*] cfg_req_be[*]
    cfg_req_wdata[*] cfg_req_requester_id[*] cfg_req_tag[*]
    cfg_req_target_bdf[*] cfg_rsp_ready
}]
set_output_delay -clock cfg_clk_250 -max 1.000 [all_outputs]
set_output_delay -clock cfg_clk_250 -min 0.000 [all_outputs]

set_false_path -from [get_ports rst_n]
