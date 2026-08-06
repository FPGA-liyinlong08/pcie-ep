`timescale 1ns/1ps
`default_nettype none

module k06_dll_replay_native_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dll_active,
    input  wire        enqueue_valid,
    output wire        enqueue_ready,
    input  wire [31:0] packet_dw0,
    input  wire [31:0] packet_dw1,
    input  wire [31:0] packet_dw2,
    input  wire        mac_ready,
    output wire        mac_valid,
    output wire [15:0] mac_data,
    output wire [1:0]  mac_keep,
    output wire        mac_sop,
    output wire        mac_eop,
    input  wire        ack_valid,
    input  wire        ack_is_nak,
    input  wire [11:0] ack_seq,
    output wire [11:0] next_tx_seq,
    output wire [11:0] last_acked_seq,
    output wire [3:0]  replay_occupancy,
    output wire        replay_active,
    output wire [31:0] tx_tlp_count,
    output wire [31:0] replay_count,
    output wire [31:0] ack_error_count,
    output wire [31:0] buffer_error_count
);
    wire [31:0] ack_data = {ack_seq[7:0], 4'h0, ack_seq[11:8],
                            8'h00, ack_is_nak ? 8'h10 : 8'h00};
    wire unused_tx_ack_valid;
    wire [31:0] unused_tx_ack_data;
    wire unused_rx_tlp_valid;
    wire [127:0] unused_rx_tlp_data;
    wire [15:0] unused_rx_tlp_keep;
    wire unused_rx_tlp_sop;
    wire unused_rx_tlp_eop;
    wire [3:0] unused_rx_tlp_error;
    wire [1:0] unused_tx_fc_check_type;
    wire [11:0] unused_tx_fc_check_data;
    wire unused_tx_fc_consume_valid;
    wire [1:0] unused_tx_fc_consume_type;
    wire [11:0] unused_tx_fc_consume_data;
    wire unused_rx_fc_consume_valid;
    wire [1:0] unused_rx_fc_consume_type;
    wire [11:0] unused_rx_fc_consume_data;
    wire [11:0] unused_next_rx_seq;
    wire unused_replay_fatal;
    wire unused_recovery_req;
    wire [31:0] unused_rx_tlp_count;
    wire [31:0] unused_ack_tx_count;
    wire [31:0] unused_nak_tx_count;
    wire [31:0] unused_lcrc_error_count;
    wire [31:0] unused_duplicate_count;
    wire [31:0] unused_sequence_error_count;
    wire unused_mac_is_dllp;
    wire unused_mac_bad;

    pcie_dll_replay #(
        .REPLAY_DEPTH(8), .RX_FRAME_SLOTS(2),
        .ACK_LATENCY_CYCLES(8), .REPLAY_TIMEOUT_CYCLES(128),
        .REPLAY_RETRY_LIMIT(3)
    ) dut (
        .clk(clk), .rst_n(rst_n), .dll_active(dll_active),
        .mac_rx_valid(1'b0), .mac_rx_data(16'd0), .mac_rx_keep(2'd0),
        .mac_rx_sop(1'b0), .mac_rx_eop(1'b0), .mac_rx_is_dllp(1'b0),
        .mac_rx_error(4'd0), .mac_tx_valid(mac_valid),
        .mac_tx_ready(mac_ready), .mac_tx_data(mac_data),
        .mac_tx_keep(mac_keep), .mac_tx_sop(mac_sop), .mac_tx_eop(mac_eop),
        .mac_tx_is_dllp(unused_mac_is_dllp), .mac_tx_bad(unused_mac_bad),
        .rx_dllp_valid(ack_valid), .rx_dllp_data(ack_data),
        .rx_dllp_crc_good(1'b1), .rx_dllp_error(4'd0),
        .tx_ack_dllp_valid(unused_tx_ack_valid), .tx_ack_dllp_ready(1'b1),
        .tx_ack_dllp_data(unused_tx_ack_data), .tx_tlp_valid(enqueue_valid),
        .tx_tlp_ready(enqueue_ready),
        .tx_tlp_data({32'd0, packet_dw2, packet_dw1, packet_dw0}),
        .tx_tlp_keep(16'h0fff), .tx_tlp_sop(1'b1), .tx_tlp_eop(1'b1),
        .tx_tlp_error(4'd0), .tx_tlp_type(2'd1),
        .tx_tlp_data_credits(12'd0), .rx_tlp_valid(unused_rx_tlp_valid),
        .rx_tlp_ready(1'b1), .rx_tlp_data(unused_rx_tlp_data),
        .rx_tlp_keep(unused_rx_tlp_keep), .rx_tlp_sop(unused_rx_tlp_sop),
        .rx_tlp_eop(unused_rx_tlp_eop), .rx_tlp_error(unused_rx_tlp_error),
        .tx_fc_check_type(unused_tx_fc_check_type),
        .tx_fc_check_data_credits(unused_tx_fc_check_data),
        .tx_fc_credit_available(1'b1),
        .tx_fc_consume_valid(unused_tx_fc_consume_valid),
        .tx_fc_consume_type(unused_tx_fc_consume_type),
        .tx_fc_consume_data_credits(unused_tx_fc_consume_data),
        .rx_fc_consume_valid(unused_rx_fc_consume_valid),
        .rx_fc_consume_type(unused_rx_fc_consume_type),
        .rx_fc_consume_data_credits(unused_rx_fc_consume_data),
        .next_tx_seq(next_tx_seq), .next_rx_seq(unused_next_rx_seq),
        .last_acked_seq(last_acked_seq), .replay_occupancy(replay_occupancy),
        .replay_active(replay_active), .replay_fatal(unused_replay_fatal),
        .recovery_req(unused_recovery_req), .tx_tlp_count(tx_tlp_count),
        .rx_tlp_count(unused_rx_tlp_count), .ack_tx_count(unused_ack_tx_count),
        .nak_tx_count(unused_nak_tx_count), .replay_count(replay_count),
        .lcrc_error_count(unused_lcrc_error_count),
        .duplicate_tlp_count(unused_duplicate_count),
        .sequence_error_count(unused_sequence_error_count),
        .ack_error_count(ack_error_count), .buffer_error_count(buffer_error_count)
    );

    wire [435:0] _unused = {unused_tx_ack_valid, unused_tx_ack_data,
        unused_rx_tlp_valid, unused_rx_tlp_data, unused_rx_tlp_keep,
        unused_rx_tlp_sop, unused_rx_tlp_eop, unused_rx_tlp_error,
        unused_tx_fc_check_type, unused_tx_fc_check_data,
        unused_tx_fc_consume_valid, unused_tx_fc_consume_type,
        unused_tx_fc_consume_data, unused_rx_fc_consume_valid,
        unused_rx_fc_consume_type, unused_rx_fc_consume_data,
        unused_next_rx_seq, unused_replay_fatal, unused_recovery_req,
        unused_rx_tlp_count, unused_ack_tx_count, unused_nak_tx_count,
        unused_lcrc_error_count, unused_duplicate_count,
        unused_sequence_error_count, unused_mac_is_dllp, unused_mac_bad};
endmodule

`default_nettype wire
