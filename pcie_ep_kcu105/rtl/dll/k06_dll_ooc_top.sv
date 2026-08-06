`timescale 1ns/1ps
`default_nettype none

module k06_dll_ooc_top #(
    parameter integer REPLAY_DEPTH = 16
) (
    input wire clk, input wire rst_n, input wire link_up,
    input wire mac_rx_valid, input wire [15:0] mac_rx_data,
    input wire [1:0] mac_rx_keep, input wire mac_rx_sop, input wire mac_rx_eop,
    input wire mac_rx_is_dllp, input wire [3:0] mac_rx_error,
    output wire mac_tx_valid, input wire mac_tx_ready,
    output wire [15:0] mac_tx_data, output wire [1:0] mac_tx_keep,
    output wire mac_tx_sop, output wire mac_tx_eop,
    output wire mac_tx_is_dllp, output wire mac_tx_bad,
    input wire tx_tlp_valid, output wire tx_tlp_ready,
    input wire [127:0] tx_tlp_data, input wire [15:0] tx_tlp_keep,
    input wire tx_tlp_sop, input wire tx_tlp_eop, input wire [3:0] tx_tlp_error,
    input wire [1:0] tx_tlp_type, input wire [11:0] tx_tlp_data_credits,
    output wire rx_tlp_valid, input wire rx_tlp_ready,
    output wire [127:0] rx_tlp_data, output wire [15:0] rx_tlp_keep,
    output wire rx_tlp_sop, output wire rx_tlp_eop, output wire [3:0] rx_tlp_error,
    input wire rx_tlp_release_valid, input wire [1:0] rx_tlp_release_type,
    input wire [11:0] rx_tlp_release_data_credits,
    output wire dll_active, output wire [1:0] fc_state,
    output wire recovery_req, output wire [11:0] next_tx_seq,
    output wire [11:0] next_rx_seq, output wire [11:0] last_acked_seq,
    output wire [$clog2(REPLAY_DEPTH+1)-1:0] replay_occupancy,
    output wire replay_active, output wire replay_fatal,
    output wire [31:0] malformed_dllp_count,
    output wire [31:0] bad_dllp_crc_count,
    output wire [31:0] fc_protocol_error_count,
    output wire [31:0] tx_fc_count, output wire [31:0] rx_fc_count,
    output wire [31:0] tx_tlp_count, output wire [31:0] rx_tlp_count,
    output wire [31:0] ack_tx_count, output wire [31:0] nak_tx_count,
    output wire [31:0] replay_count, output wire [31:0] lcrc_error_count,
    output wire [31:0] duplicate_tlp_count,
    output wire [31:0] sequence_error_count,
    output wire [31:0] ack_error_count, output wire [31:0] buffer_error_count
);
    wire dll_rst_n;
    pcie_reset_sync #(.STAGES(4)) u_ooc_reset_sync (
        .clk(clk), .async_release_n(rst_n), .sync_reset_n(dll_rst_n)
    );

    pcie_dll #(.REPLAY_DEPTH(REPLAY_DEPTH)) u_dut (
        .rst_n(dll_rst_n), .*
    );
endmodule

`default_nettype wire
