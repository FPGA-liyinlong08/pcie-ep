`timescale 1ns/1ps
`default_nettype none

// Checker自检专用错误实现：看到Cfg首Byte就提前产生请求，完全不等待整包EOP。
module pcie_tlp_codec (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rx_tlp_valid,
    output wire         rx_tlp_ready,
    input  wire [127:0] rx_tlp_data,
    input  wire [15:0]  rx_tlp_keep,
    input  wire         rx_tlp_sop,
    input  wire         rx_tlp_eop,
    input  wire [3:0]   rx_tlp_error,
    output wire         tx_tlp_valid,
    input  wire         tx_tlp_ready,
    output wire [127:0] tx_tlp_data,
    output wire [15:0]  tx_tlp_keep,
    output wire         tx_tlp_sop,
    output wire         tx_tlp_eop,
    output wire [3:0]   tx_tlp_error,
    output wire [1:0]   tx_tlp_type,
    output wire [11:0]  tx_tlp_data_credits,
    output wire         rx_release_valid,
    input  wire         rx_release_ready,
    output wire [1:0]   rx_release_type,
    output wire [11:0]  rx_release_data_credits,
    input  wire [15:0]  local_completer_id,
    output reg          cfg_req_valid,
    input  wire         cfg_req_ready,
    output wire         cfg_req_write,
    output wire [9:0]   cfg_req_dw_addr,
    output wire [3:0]   cfg_req_be,
    output wire [31:0]  cfg_req_wdata,
    output wire [15:0]  cfg_req_requester_id,
    output wire [7:0]   cfg_req_tag,
    output wire [15:0]  cfg_req_target_bdf,
    input  wire         cfg_rsp_valid,
    output wire         cfg_rsp_ready,
    input  wire [2:0]   cfg_rsp_status,
    input  wire [31:0]  cfg_rsp_rdata,
    input  wire [15:0]  cfg_rsp_completer_id,
    output wire         mem_req_valid,
    input  wire         mem_req_ready,
    output wire         mem_req_write,
    output wire         mem_req_64bit,
    output wire         mem_req_poisoned,
    output wire [63:0]  mem_req_address,
    output wire [10:0]  mem_req_length_dw,
    output wire [3:0]   mem_req_first_be,
    output wire [3:0]   mem_req_last_be,
    output wire [15:0]  mem_req_requester_id,
    output wire [7:0]   mem_req_tag,
    output wire [2:0]   mem_req_tc,
    output wire [2:0]   mem_req_attr,
    output wire         mem_w_valid,
    input  wire         mem_w_ready,
    output wire [127:0] mem_w_data,
    output wire [15:0]  mem_w_keep,
    output wire         mem_w_last,
    output wire         rx_cpl_valid,
    input  wire         rx_cpl_ready,
    output wire         rx_cpl_has_data,
    output wire         rx_cpl_poisoned,
    output wire [2:0]   rx_cpl_status,
    output wire         rx_cpl_bcm,
    output wire [12:0]  rx_cpl_byte_count,
    output wire [15:0]  rx_cpl_completer_id,
    output wire [15:0]  rx_cpl_requester_id,
    output wire [7:0]   rx_cpl_tag,
    output wire [6:0]   rx_cpl_lower_address,
    output wire [5:0]   rx_cpl_length_dw,
    output wire [2:0]   rx_cpl_tc,
    output wire [2:0]   rx_cpl_attr,
    output wire         rx_cpl_data_valid,
    input  wire         rx_cpl_data_ready,
    output wire [127:0] rx_cpl_data,
    output wire [15:0]  rx_cpl_data_keep,
    output wire         rx_cpl_data_last,
    input  wire         cpl_req_valid,
    output wire         cpl_req_ready,
    input  wire         cpl_req_has_data,
    input  wire         cpl_req_poisoned,
    input  wire [2:0]   cpl_req_status,
    input  wire         cpl_req_bcm,
    input  wire [12:0]  cpl_req_byte_count,
    input  wire [15:0]  cpl_req_completer_id,
    input  wire [15:0]  cpl_req_requester_id,
    input  wire [7:0]   cpl_req_tag,
    input  wire [6:0]   cpl_req_lower_address,
    input  wire [5:0]   cpl_req_length_dw,
    input  wire [2:0]   cpl_req_tc,
    input  wire [2:0]   cpl_req_attr,
    input  wire         cpl_data_valid,
    output wire         cpl_data_ready,
    input  wire [127:0] cpl_data,
    input  wire [15:0]  cpl_data_keep,
    input  wire         cpl_data_last,
    output wire         malformed_pulse,
    output wire         unsupported_pulse,
    output wire         poisoned_pulse,
    output wire         unexpected_cpl_pulse,
    output wire [7:0]   error_fmt_type,
    output wire [15:0]  error_requester_id,
    output wire [7:0]   error_tag,
    output wire [31:0]  rx_packet_count,
    output wire [31:0]  cfg_request_count,
    output wire [31:0]  mem_request_count,
    output wire [31:0]  rx_completion_count,
    output wire [31:0]  tx_completion_count,
    output wire [31:0]  ur_completion_count,
    output wire [31:0]  malformed_count,
    output wire [31:0]  unsupported_count,
    output wire [31:0]  poisoned_count,
    output wire [31:0]  unexpected_completion_count,
    output wire [31:0]  tx_protocol_error_count
);
    assign rx_tlp_ready = rst_n;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cfg_req_valid <= 1'b0;
        else
            cfg_req_valid <= rx_tlp_valid && rx_tlp_ready && rx_tlp_sop &&
                             ((rx_tlp_data[7:0] == 8'h04) ||
                              (rx_tlp_data[7:0] == 8'h44));
    end
    assign cfg_req_write = rx_tlp_data[6];
    assign cfg_req_dw_addr = 10'd0;
    assign cfg_req_be = 4'd0;
    assign cfg_req_wdata = 32'd0;
    assign cfg_req_requester_id = 16'd0;
    assign cfg_req_tag = 8'd0;
    assign cfg_req_target_bdf = 16'd0;
    assign tx_tlp_valid = 1'b0;
    assign tx_tlp_data = 128'd0;
    assign tx_tlp_keep = 16'd0;
    assign tx_tlp_sop = 1'b0;
    assign tx_tlp_eop = 1'b0;
    assign tx_tlp_error = 4'd0;
    assign tx_tlp_type = 2'd2;
    assign tx_tlp_data_credits = 12'd0;
    assign rx_release_valid = 1'b0;
    assign rx_release_type = 2'd0;
    assign rx_release_data_credits = 12'd0;
    assign cfg_rsp_ready = 1'b0;
    assign mem_req_valid = 1'b0;
    assign mem_req_write = 1'b0;
    assign mem_req_64bit = 1'b0;
    assign mem_req_poisoned = 1'b0;
    assign mem_req_address = 64'd0;
    assign mem_req_length_dw = 11'd0;
    assign mem_req_first_be = 4'd0;
    assign mem_req_last_be = 4'd0;
    assign mem_req_requester_id = 16'd0;
    assign mem_req_tag = 8'd0;
    assign mem_req_tc = 3'd0;
    assign mem_req_attr = 3'd0;
    assign mem_w_valid = 1'b0;
    assign mem_w_data = 128'd0;
    assign mem_w_keep = 16'd0;
    assign mem_w_last = 1'b0;
    assign rx_cpl_valid = 1'b0;
    assign rx_cpl_has_data = 1'b0;
    assign rx_cpl_poisoned = 1'b0;
    assign rx_cpl_status = 3'd0;
    assign rx_cpl_bcm = 1'b0;
    assign rx_cpl_byte_count = 13'd0;
    assign rx_cpl_completer_id = 16'd0;
    assign rx_cpl_requester_id = 16'd0;
    assign rx_cpl_tag = 8'd0;
    assign rx_cpl_lower_address = 7'd0;
    assign rx_cpl_length_dw = 6'd0;
    assign rx_cpl_tc = 3'd0;
    assign rx_cpl_attr = 3'd0;
    assign rx_cpl_data_valid = 1'b0;
    assign rx_cpl_data = 128'd0;
    assign rx_cpl_data_keep = 16'd0;
    assign rx_cpl_data_last = 1'b0;
    assign cpl_req_ready = 1'b0;
    assign cpl_data_ready = 1'b0;
    assign malformed_pulse = 1'b0;
    assign unsupported_pulse = 1'b0;
    assign poisoned_pulse = 1'b0;
    assign unexpected_cpl_pulse = 1'b0;
    assign error_fmt_type = 8'd0;
    assign error_requester_id = 16'd0;
    assign error_tag = 8'd0;
    assign rx_packet_count = 32'd0;
    assign cfg_request_count = 32'd0;
    assign mem_request_count = 32'd0;
    assign rx_completion_count = 32'd0;
    assign tx_completion_count = 32'd0;
    assign ur_completion_count = 32'd0;
    assign malformed_count = 32'd0;
    assign unsupported_count = 32'd0;
    assign poisoned_count = 32'd0;
    assign unexpected_completion_count = 32'd0;
    assign tx_protocol_error_count = 32'd0;

    wire _unused = &{1'b0, clk, rx_tlp_keep, rx_tlp_eop, rx_tlp_error,
        tx_tlp_ready, rx_release_ready, local_completer_id, cfg_req_ready,
        cfg_rsp_valid, cfg_rsp_status, cfg_rsp_rdata, cfg_rsp_completer_id,
        mem_req_ready, mem_w_ready, rx_cpl_ready, rx_cpl_data_ready,
        cpl_req_valid, cpl_req_has_data, cpl_req_poisoned, cpl_req_status,
        cpl_req_bcm, cpl_req_byte_count, cpl_req_completer_id,
        cpl_req_requester_id, cpl_req_tag, cpl_req_lower_address,
        cpl_req_length_dw, cpl_req_tc, cpl_req_attr, cpl_data_valid,
        cpl_data, cpl_data_keep, cpl_data_last};
endmodule

`default_nettype wire
