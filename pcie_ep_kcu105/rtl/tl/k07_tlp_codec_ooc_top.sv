`timescale 1ns/1ps
`default_nettype none

// K07仅用于KU040 OOC签核的包装层。
// 生产集成中rst_n直接来自K01已经同步释放的core_rst_n；OOC边界看不到该同步链，
// 因此在此补建同等四级链，使CDC报告能够验证真实的复位拓扑。
module k07_tlp_codec_ooc_top (
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

    output wire         cfg_req_valid,
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
    wire codec_rst_n;

    pcie_reset_sync #(.STAGES(4)) u_ooc_reset_sync (
        .clk(clk),
        .async_release_n(rst_n),
        .sync_reset_n(codec_rst_n)
    );

    pcie_tlp_codec u_dut (
        .rst_n(codec_rst_n),
        .*
    );
endmodule

`default_nettype wire
