`timescale 1ns/1ps
`default_nettype none

// 故意错误：接受TL Packet，却不添加Sequence/LCRC，也不产生MAC输出。
// K06 Checker必须在首个TX用例中检出超时。
module k06_dll_replay_test_top (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         dll_active,
    input  wire         mac_rx_valid,
    input  wire [15:0]  mac_rx_data,
    input  wire [1:0]   mac_rx_keep,
    input  wire         mac_rx_sop,
    input  wire         mac_rx_eop,
    input  wire         mac_rx_is_dllp,
    input  wire [3:0]   mac_rx_error,
    output wire         mac_tx_valid,
    input  wire         mac_tx_ready,
    output wire [15:0]  mac_tx_data,
    output wire [1:0]   mac_tx_keep,
    output wire         mac_tx_sop,
    output wire         mac_tx_eop,
    output wire         mac_tx_is_dllp,
    output wire         mac_tx_bad,
    input  wire         rx_dllp_valid,
    input  wire [31:0]  rx_dllp_data,
    input  wire         rx_dllp_crc_good,
    input  wire [3:0]   rx_dllp_error,
    output wire         tx_ack_dllp_valid,
    input  wire         tx_ack_dllp_ready,
    output wire [31:0]  tx_ack_dllp_data,
    input  wire         tx_tlp_valid,
    output wire         tx_tlp_ready,
    input  wire [127:0] tx_tlp_data,
    input  wire [15:0]  tx_tlp_keep,
    input  wire         tx_tlp_sop,
    input  wire         tx_tlp_eop,
    input  wire [3:0]   tx_tlp_error,
    input  wire [1:0]   tx_tlp_type,
    input  wire [11:0]  tx_tlp_data_credits,
    output wire         rx_tlp_valid,
    input  wire         rx_tlp_ready,
    output wire [127:0] rx_tlp_data,
    output wire [15:0]  rx_tlp_keep,
    output wire         rx_tlp_sop,
    output wire         rx_tlp_eop,
    output wire [3:0]   rx_tlp_error,
    output wire [1:0]   tx_fc_check_type,
    output wire [11:0]  tx_fc_check_data_credits,
    input  wire         tx_fc_credit_available,
    output wire         tx_fc_consume_valid,
    output wire [1:0]   tx_fc_consume_type,
    output wire [11:0]  tx_fc_consume_data_credits,
    output wire         rx_fc_consume_valid,
    output wire [1:0]   rx_fc_consume_type,
    output wire [11:0]  rx_fc_consume_data_credits,
    output wire [11:0]  next_tx_seq,
    output wire [11:0]  next_rx_seq,
    output wire [11:0]  last_acked_seq,
    output wire [4:0]   replay_occupancy,
    output wire         replay_active,
    output wire         replay_fatal,
    output wire         recovery_req,
    output wire [31:0]  tx_tlp_count,
    output wire [31:0]  rx_tlp_count,
    output wire [31:0]  ack_tx_count,
    output wire [31:0]  nak_tx_count,
    output wire [31:0]  replay_count,
    output wire [31:0]  lcrc_error_count,
    output wire [31:0]  duplicate_tlp_count,
    output wire [31:0]  sequence_error_count,
    output wire [31:0]  ack_error_count,
    output wire [31:0]  buffer_error_count
);
    assign tx_tlp_ready = rst_n && dll_active;
    assign mac_tx_valid = 1'b0;
    assign mac_tx_data = 16'd0;
    assign mac_tx_keep = 2'b00;
    assign mac_tx_sop = 1'b0;
    assign mac_tx_eop = 1'b0;
    assign mac_tx_is_dllp = 1'b0;
    assign mac_tx_bad = 1'b0;
    assign tx_ack_dllp_valid = 1'b0;
    assign tx_ack_dllp_data = 32'd0;
    assign rx_tlp_valid = 1'b0;
    assign rx_tlp_data = 128'd0;
    assign rx_tlp_keep = 16'd0;
    assign rx_tlp_sop = 1'b0;
    assign rx_tlp_eop = 1'b0;
    assign rx_tlp_error = 4'd0;
    assign tx_fc_check_type = 2'd0;
    assign tx_fc_check_data_credits = 12'd0;
    assign tx_fc_consume_valid = 1'b0;
    assign tx_fc_consume_type = 2'd0;
    assign tx_fc_consume_data_credits = 12'd0;
    assign rx_fc_consume_valid = 1'b0;
    assign rx_fc_consume_type = 2'd0;
    assign rx_fc_consume_data_credits = 12'd0;
    assign next_tx_seq = 12'd0;
    assign next_rx_seq = 12'd0;
    assign last_acked_seq = 12'hfff;
    assign replay_occupancy = 5'd0;
    assign replay_active = 1'b0;
    assign replay_fatal = 1'b0;
    assign recovery_req = 1'b0;
    assign tx_tlp_count = 32'd0;
    assign rx_tlp_count = 32'd0;
    assign ack_tx_count = 32'd0;
    assign nak_tx_count = 32'd0;
    assign replay_count = 32'd0;
    assign lcrc_error_count = 32'd0;
    assign duplicate_tlp_count = 32'd0;
    assign sequence_error_count = 32'd0;
    assign ack_error_count = 32'd0;
    assign buffer_error_count = 32'd0;

    wire [231:0] _unused = {mac_rx_valid, mac_rx_data, mac_rx_keep,
        mac_rx_sop, mac_rx_eop, mac_rx_is_dllp, mac_rx_error, mac_tx_ready,
        rx_dllp_valid, rx_dllp_data, rx_dllp_crc_good, rx_dllp_error,
        tx_ack_dllp_ready, tx_tlp_data, tx_tlp_keep, tx_tlp_sop, tx_tlp_eop,
        tx_tlp_error, tx_tlp_type, tx_tlp_data_credits, rx_tlp_ready,
        tx_fc_credit_available};
endmodule

`default_nettype wire
