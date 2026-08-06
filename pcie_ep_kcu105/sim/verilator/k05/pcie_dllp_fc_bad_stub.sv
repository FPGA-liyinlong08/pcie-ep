`timescale 1ns/1ps
`default_nettype none

// Checker 自检专用错误实现：跳过 InitFC，谎报无限信用，也从不发送 DLLP。
module k05_dllp_fc_test_top (
    input wire clk, rst_n, link_up,
    input wire mac_rx_valid, input wire [15:0] mac_rx_data,
    input wire [1:0] mac_rx_keep, input wire mac_rx_sop, mac_rx_eop,
    input wire mac_rx_is_dllp, input wire [3:0] mac_rx_error,
    output wire mac_tx_valid, input wire mac_tx_ready,
    output wire [15:0] mac_tx_data, output wire [1:0] mac_tx_keep,
    output wire mac_tx_sop, mac_tx_eop, mac_tx_is_dllp, mac_tx_bad,
    output wire rx_dllp_valid, output wire [31:0] rx_dllp_data,
    output wire rx_dllp_crc_good, output wire [3:0] rx_dllp_error,
    input wire [1:0] tx_tlp_check_type, input wire [11:0] tx_tlp_check_data_credits,
    output wire tx_tlp_credit_available,
    input wire tx_tlp_consume_valid, input wire [1:0] tx_tlp_consume_type,
    input wire [11:0] tx_tlp_consume_data_credits,
    input wire rx_tlp_consume_valid, input wire [1:0] rx_tlp_consume_type,
    input wire [11:0] rx_tlp_consume_data_credits,
    input wire rx_tlp_release_valid, input wire [1:0] rx_tlp_release_type,
    input wire [11:0] rx_tlp_release_data_credits,
    output wire dll_active, output wire [1:0] fc_state,
    output wire [7:0] tx_ph_available, output wire [11:0] tx_pd_available,
    output wire [7:0] tx_nph_available, output wire [11:0] tx_npd_available,
    output wire [7:0] tx_cplh_available, output wire [11:0] tx_cpld_available,
    output wire [7:0] rx_ph_occupied, output wire [11:0] rx_pd_occupied,
    output wire [7:0] rx_nph_occupied, output wire [11:0] rx_npd_occupied,
    output wire [7:0] rx_cplh_occupied, output wire [11:0] rx_cpld_occupied,
    output wire [31:0] malformed_dllp_count, output wire [31:0] bad_crc_count,
    output wire [31:0] fc_protocol_error_count,
    output wire [31:0] tx_fc_count, output wire [31:0] rx_fc_count
);
    assign mac_tx_valid = 1'b0;
    assign mac_tx_data = 16'd0;
    assign mac_tx_keep = 2'd0;
    assign mac_tx_sop = 1'b0;
    assign mac_tx_eop = 1'b0;
    assign mac_tx_is_dllp = 1'b0;
    assign mac_tx_bad = 1'b0;
    assign rx_dllp_valid = 1'b0;
    assign rx_dllp_data = 32'd0;
    assign rx_dllp_crc_good = 1'b0;
    assign rx_dllp_error = 4'd0;
    assign dll_active = rst_n && link_up;
    assign fc_state = dll_active ? 2'd3 : 2'd0;
    assign tx_tlp_credit_available = dll_active;
    assign tx_ph_available = 8'hff;
    assign tx_pd_available = 12'hfff;
    assign tx_nph_available = 8'hff;
    assign tx_npd_available = 12'hfff;
    assign tx_cplh_available = 8'hff;
    assign tx_cpld_available = 12'hfff;
    assign rx_ph_occupied = 8'd0;
    assign rx_pd_occupied = 12'd0;
    assign rx_nph_occupied = 8'd0;
    assign rx_npd_occupied = 12'd0;
    assign rx_cplh_occupied = 8'd0;
    assign rx_cpld_occupied = 12'd0;
    assign malformed_dllp_count = 32'd0;
    assign bad_crc_count = 32'd0;
    assign fc_protocol_error_count = 32'd0;
    assign tx_fc_count = 32'd0;
    assign rx_fc_count = 32'd0;
    wire _unused = &{1'b0, clk, mac_rx_valid, mac_rx_data, mac_rx_keep,
        mac_rx_sop, mac_rx_eop, mac_rx_is_dllp, mac_rx_error, mac_tx_ready,
        tx_tlp_check_type, tx_tlp_check_data_credits, tx_tlp_consume_valid,
        tx_tlp_consume_type, tx_tlp_consume_data_credits, rx_tlp_consume_valid,
        rx_tlp_consume_type, rx_tlp_consume_data_credits, rx_tlp_release_valid,
        rx_tlp_release_type, rx_tlp_release_data_credits};
endmodule

`default_nettype wire
