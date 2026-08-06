`timescale 1ns/1ps
`default_nettype none

module pcie_dll #(
    parameter integer REPLAY_DEPTH = 16,
    parameter integer RX_FRAME_SLOTS = 8,
    parameter integer ACK_LATENCY_CYCLES = 128,
    parameter integer REPLAY_TIMEOUT_CYCLES = 2048,
    parameter integer REPLAY_RETRY_LIMIT = 3,
    parameter integer RX_PH_CREDITS = 32,
    parameter integer RX_PD_CREDITS = 128,
    parameter integer RX_NPH_CREDITS = 32,
    parameter integer RX_NPD_CREDITS = 16,
    parameter integer RX_CPLH_CREDITS = 8,
    parameter integer RX_CPLD_CREDITS = 32,
    parameter integer UPDATE_INTERVAL_CYCLES = 256
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         link_up,

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

    input  wire         rx_tlp_release_valid,
    input  wire [1:0]   rx_tlp_release_type,
    input  wire [11:0]  rx_tlp_release_data_credits,

    output wire         dll_active,
    output wire [1:0]   fc_state,
    output wire         recovery_req,
    output wire [11:0]  next_tx_seq,
    output wire [11:0]  next_rx_seq,
    output wire [11:0]  last_acked_seq,
    output wire [$clog2(REPLAY_DEPTH+1)-1:0] replay_occupancy,
    output wire         replay_active,
    output wire         replay_fatal,
    output reg  [31:0]  malformed_dllp_count,
    output reg  [31:0]  bad_dllp_crc_count,
    output wire [31:0]  fc_protocol_error_count,
    output wire [31:0]  tx_fc_count,
    output wire [31:0]  rx_fc_count,
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
    function automatic [31:0] sat_inc32(input [31:0] value);
        sat_inc32 = (&value) ? value : value + 1'b1;
    endfunction

    wire rx_dllp_valid;
    wire [31:0] rx_dllp_data;
    wire rx_dllp_crc_good;
    wire [3:0] rx_dllp_error;

    wire ack_raw_valid;
    wire ack_raw_ready;
    wire [31:0] ack_raw_data;
    wire fc_raw_valid;
    wire fc_raw_ready;
    wire [31:0] fc_raw_data;
    wire codec_raw_valid;
    wire codec_raw_ready;
    wire [31:0] codec_raw_data;

    wire dllp_mac_valid;
    wire dllp_mac_ready;
    wire [15:0] dllp_mac_data;
    wire [1:0] dllp_mac_keep;
    wire dllp_mac_sop;
    wire dllp_mac_eop;
    wire dllp_mac_is_dllp;
    wire dllp_mac_bad;

    wire tlp_mac_valid;
    wire tlp_mac_ready;
    wire [15:0] tlp_mac_data;
    wire [1:0] tlp_mac_keep;
    wire tlp_mac_sop;
    wire tlp_mac_eop;
    wire tlp_mac_is_dllp;
    wire tlp_mac_bad;

    wire [1:0] tx_fc_check_type;
    wire [11:0] tx_fc_check_data_credits;
    wire tx_fc_credit_available;
    wire tx_fc_consume_valid;
    wire [1:0] tx_fc_consume_type;
    wire [11:0] tx_fc_consume_data_credits;
    wire rx_fc_consume_valid;
    wire [1:0] rx_fc_consume_type;
    wire [11:0] rx_fc_consume_data_credits;

    wire [7:0] tx_ph_available;
    wire [11:0] tx_pd_available;
    wire [7:0] tx_nph_available;
    wire [11:0] tx_npd_available;
    wire [7:0] tx_cplh_available;
    wire [11:0] tx_cpld_available;
    wire [7:0] rx_ph_occupied;
    wire [11:0] rx_pd_occupied;
    wire [7:0] rx_nph_occupied;
    wire [11:0] rx_npd_occupied;
    wire [7:0] rx_cplh_occupied;
    wire [11:0] rx_cpld_occupied;

    pcie_dllp_codec u_dllp_codec (
        .clk(clk), .rst_n(rst_n), .enable(link_up),
        .mac_rx_valid(mac_rx_valid), .mac_rx_data(mac_rx_data),
        .mac_rx_keep(mac_rx_keep), .mac_rx_sop(mac_rx_sop),
        .mac_rx_eop(mac_rx_eop), .mac_rx_is_dllp(mac_rx_is_dllp),
        .mac_rx_error(mac_rx_error), .mac_tx_valid(dllp_mac_valid),
        .mac_tx_ready(dllp_mac_ready), .mac_tx_data(dllp_mac_data),
        .mac_tx_keep(dllp_mac_keep), .mac_tx_sop(dllp_mac_sop),
        .mac_tx_eop(dllp_mac_eop), .mac_tx_is_dllp(dllp_mac_is_dllp),
        .mac_tx_bad(dllp_mac_bad), .rx_dllp_valid(rx_dllp_valid),
        .rx_dllp_data(rx_dllp_data), .rx_dllp_crc_good(rx_dllp_crc_good),
        .rx_dllp_error(rx_dllp_error), .tx_dllp_valid(codec_raw_valid),
        .tx_dllp_ready(codec_raw_ready), .tx_dllp_data(codec_raw_data)
    );

    pcie_dllp_fc_manager #(
        .RX_PH_CREDITS(RX_PH_CREDITS), .RX_PD_CREDITS(RX_PD_CREDITS),
        .RX_NPH_CREDITS(RX_NPH_CREDITS), .RX_NPD_CREDITS(RX_NPD_CREDITS),
        .RX_CPLH_CREDITS(RX_CPLH_CREDITS), .RX_CPLD_CREDITS(RX_CPLD_CREDITS),
        .UPDATE_INTERVAL_CYCLES(UPDATE_INTERVAL_CYCLES)
    ) u_fc_manager (
        .clk(clk), .rst_n(rst_n), .link_up(link_up),
        .rx_dllp_valid(rx_dllp_valid), .rx_dllp_data(rx_dllp_data),
        .rx_dllp_crc_good(rx_dllp_crc_good), .rx_dllp_error(rx_dllp_error),
        .tx_dllp_valid(fc_raw_valid), .tx_dllp_ready(fc_raw_ready),
        .tx_dllp_data(fc_raw_data), .tx_tlp_check_type(tx_fc_check_type),
        .tx_tlp_check_data_credits(tx_fc_check_data_credits),
        .tx_tlp_credit_available(tx_fc_credit_available),
        .tx_tlp_consume_valid(tx_fc_consume_valid),
        .tx_tlp_consume_type(tx_fc_consume_type),
        .tx_tlp_consume_data_credits(tx_fc_consume_data_credits),
        .rx_tlp_consume_valid(rx_fc_consume_valid),
        .rx_tlp_consume_type(rx_fc_consume_type),
        .rx_tlp_consume_data_credits(rx_fc_consume_data_credits),
        .rx_tlp_release_valid(rx_tlp_release_valid),
        .rx_tlp_release_type(rx_tlp_release_type),
        .rx_tlp_release_data_credits(rx_tlp_release_data_credits),
        .dll_active(dll_active), .fc_state(fc_state),
        .tx_ph_available(tx_ph_available), .tx_pd_available(tx_pd_available),
        .tx_nph_available(tx_nph_available), .tx_npd_available(tx_npd_available),
        .tx_cplh_available(tx_cplh_available), .tx_cpld_available(tx_cpld_available),
        .rx_ph_occupied(rx_ph_occupied), .rx_pd_occupied(rx_pd_occupied),
        .rx_nph_occupied(rx_nph_occupied), .rx_npd_occupied(rx_npd_occupied),
        .rx_cplh_occupied(rx_cplh_occupied), .rx_cpld_occupied(rx_cpld_occupied),
        .fc_protocol_error_count(fc_protocol_error_count),
        .tx_fc_count(tx_fc_count), .rx_fc_count(rx_fc_count)
    );

    pcie_dll_replay #(
        .REPLAY_DEPTH(REPLAY_DEPTH), .RX_FRAME_SLOTS(RX_FRAME_SLOTS),
        .ACK_LATENCY_CYCLES(ACK_LATENCY_CYCLES),
        .REPLAY_TIMEOUT_CYCLES(REPLAY_TIMEOUT_CYCLES),
        .REPLAY_RETRY_LIMIT(REPLAY_RETRY_LIMIT)
    ) u_replay (
        .clk(clk), .rst_n(rst_n), .dll_active(dll_active),
        .mac_rx_valid(mac_rx_valid), .mac_rx_data(mac_rx_data),
        .mac_rx_keep(mac_rx_keep), .mac_rx_sop(mac_rx_sop),
        .mac_rx_eop(mac_rx_eop), .mac_rx_is_dllp(mac_rx_is_dllp),
        .mac_rx_error(mac_rx_error), .mac_tx_valid(tlp_mac_valid),
        .mac_tx_ready(tlp_mac_ready), .mac_tx_data(tlp_mac_data),
        .mac_tx_keep(tlp_mac_keep), .mac_tx_sop(tlp_mac_sop),
        .mac_tx_eop(tlp_mac_eop), .mac_tx_is_dllp(tlp_mac_is_dllp),
        .mac_tx_bad(tlp_mac_bad), .rx_dllp_valid(rx_dllp_valid),
        .rx_dllp_data(rx_dllp_data), .rx_dllp_crc_good(rx_dllp_crc_good),
        .rx_dllp_error(rx_dllp_error), .tx_ack_dllp_valid(ack_raw_valid),
        .tx_ack_dllp_ready(ack_raw_ready), .tx_ack_dllp_data(ack_raw_data),
        .tx_tlp_valid(tx_tlp_valid), .tx_tlp_ready(tx_tlp_ready),
        .tx_tlp_data(tx_tlp_data), .tx_tlp_keep(tx_tlp_keep),
        .tx_tlp_sop(tx_tlp_sop), .tx_tlp_eop(tx_tlp_eop),
        .tx_tlp_error(tx_tlp_error), .tx_tlp_type(tx_tlp_type),
        .tx_tlp_data_credits(tx_tlp_data_credits),
        .rx_tlp_valid(rx_tlp_valid), .rx_tlp_ready(rx_tlp_ready),
        .rx_tlp_data(rx_tlp_data), .rx_tlp_keep(rx_tlp_keep),
        .rx_tlp_sop(rx_tlp_sop), .rx_tlp_eop(rx_tlp_eop),
        .rx_tlp_error(rx_tlp_error), .tx_fc_check_type(tx_fc_check_type),
        .tx_fc_check_data_credits(tx_fc_check_data_credits),
        .tx_fc_credit_available(tx_fc_credit_available),
        .tx_fc_consume_valid(tx_fc_consume_valid),
        .tx_fc_consume_type(tx_fc_consume_type),
        .tx_fc_consume_data_credits(tx_fc_consume_data_credits),
        .rx_fc_consume_valid(rx_fc_consume_valid),
        .rx_fc_consume_type(rx_fc_consume_type),
        .rx_fc_consume_data_credits(rx_fc_consume_data_credits),
        .next_tx_seq(next_tx_seq), .next_rx_seq(next_rx_seq),
        .last_acked_seq(last_acked_seq), .replay_occupancy(replay_occupancy),
        .replay_active(replay_active), .replay_fatal(replay_fatal),
        .recovery_req(recovery_req), .tx_tlp_count(tx_tlp_count),
        .rx_tlp_count(rx_tlp_count), .ack_tx_count(ack_tx_count),
        .nak_tx_count(nak_tx_count), .replay_count(replay_count),
        .lcrc_error_count(lcrc_error_count),
        .duplicate_tlp_count(duplicate_tlp_count),
        .sequence_error_count(sequence_error_count),
        .ack_error_count(ack_error_count), .buffer_error_count(buffer_error_count)
    );

    pcie_dllp_tx_arbiter u_raw_arbiter (
        .ack_valid(ack_raw_valid), .ack_ready(ack_raw_ready),
        .ack_data(ack_raw_data), .fc_valid(fc_raw_valid),
        .fc_ready(fc_raw_ready), .fc_data(fc_raw_data),
        .out_valid(codec_raw_valid), .out_ready(codec_raw_ready),
        .out_data(codec_raw_data)
    );

    pcie_dll_mac_tx_arbiter u_mac_arbiter (
        .clk(clk), .rst_n(rst_n), .enable(link_up),
        .dllp_valid(dllp_mac_valid), .dllp_ready(dllp_mac_ready),
        .dllp_data(dllp_mac_data), .dllp_keep(dllp_mac_keep),
        .dllp_sop(dllp_mac_sop), .dllp_eop(dllp_mac_eop),
        .dllp_bad(dllp_mac_bad), .tlp_valid(tlp_mac_valid),
        .tlp_ready(tlp_mac_ready), .tlp_data(tlp_mac_data),
        .tlp_keep(tlp_mac_keep), .tlp_sop(tlp_mac_sop),
        .tlp_eop(tlp_mac_eop), .tlp_bad(tlp_mac_bad),
        .out_valid(mac_tx_valid), .out_ready(mac_tx_ready),
        .out_data(mac_tx_data), .out_keep(mac_tx_keep),
        .out_sop(mac_tx_sop), .out_eop(mac_tx_eop),
        .out_is_dllp(mac_tx_is_dllp), .out_bad(mac_tx_bad)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            malformed_dllp_count <= 0;
            bad_dllp_crc_count <= 0;
        end else if (rx_dllp_valid) begin
            if (rx_dllp_error[0] || rx_dllp_error[1] || rx_dllp_error[3])
                malformed_dllp_count <= sat_inc32(malformed_dllp_count);
            if (rx_dllp_error[2])
                bad_dllp_crc_count <= sat_inc32(bad_dllp_crc_count);
        end
    end

    wire [121:0] _unused_credit_status = {dllp_mac_is_dllp, tlp_mac_is_dllp,
        tx_ph_available, tx_pd_available, tx_nph_available, tx_npd_available,
        tx_cplh_available, tx_cpld_available, rx_ph_occupied, rx_pd_occupied,
        rx_nph_occupied, rx_npd_occupied, rx_cplh_occupied, rx_cpld_occupied};
endmodule

`default_nettype wire
