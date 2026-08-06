`timescale 1ns/1ps
`default_nettype none

module pcie_dllp_fc #(
    parameter integer RX_PH_CREDITS   = 32,
    parameter integer RX_PD_CREDITS   = 128,
    parameter integer RX_NPH_CREDITS  = 32,
    parameter integer RX_NPD_CREDITS  = 16,
    parameter integer RX_CPLH_CREDITS = 8,
    parameter integer RX_CPLD_CREDITS = 32,
    parameter integer UPDATE_INTERVAL_CYCLES = 256
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        link_up,
    input  wire        mac_rx_valid,
    input  wire [15:0] mac_rx_data,
    input  wire [1:0]  mac_rx_keep,
    input  wire        mac_rx_sop,
    input  wire        mac_rx_eop,
    input  wire        mac_rx_is_dllp,
    input  wire [3:0]  mac_rx_error,
    output wire        mac_tx_valid,
    input  wire        mac_tx_ready,
    output wire [15:0] mac_tx_data,
    output wire [1:0]  mac_tx_keep,
    output wire        mac_tx_sop,
    output wire        mac_tx_eop,
    output wire        mac_tx_is_dllp,
    output wire        mac_tx_bad,
    output wire        rx_dllp_valid,
    output wire [31:0] rx_dllp_data,
    output wire        rx_dllp_crc_good,
    output wire [3:0]  rx_dllp_error,
    input  wire [1:0]  tx_tlp_check_type,
    input  wire [11:0] tx_tlp_check_data_credits,
    output wire        tx_tlp_credit_available,
    input  wire        tx_tlp_consume_valid,
    input  wire [1:0]  tx_tlp_consume_type,
    input  wire [11:0] tx_tlp_consume_data_credits,
    input  wire        rx_tlp_consume_valid,
    input  wire [1:0]  rx_tlp_consume_type,
    input  wire [11:0] rx_tlp_consume_data_credits,
    input  wire        rx_tlp_release_valid,
    input  wire [1:0]  rx_tlp_release_type,
    input  wire [11:0] rx_tlp_release_data_credits,
    output wire        dll_active,
    output wire [1:0]  fc_state,
    output wire [7:0]  tx_ph_available,
    output wire [11:0] tx_pd_available,
    output wire [7:0]  tx_nph_available,
    output wire [11:0] tx_npd_available,
    output wire [7:0]  tx_cplh_available,
    output wire [11:0] tx_cpld_available,
    output wire [7:0]  rx_ph_occupied,
    output wire [11:0] rx_pd_occupied,
    output wire [7:0]  rx_nph_occupied,
    output wire [11:0] rx_npd_occupied,
    output wire [7:0]  rx_cplh_occupied,
    output wire [11:0] rx_cpld_occupied,
    output reg  [31:0] malformed_dllp_count,
    output reg  [31:0] bad_crc_count,
    output wire [31:0] fc_protocol_error_count,
    output wire [31:0] tx_fc_count,
    output wire [31:0] rx_fc_count
);
    wire fc_tx_valid;
    wire fc_tx_ready;
    wire [31:0] fc_tx_data;

    function automatic [31:0] sat_inc32(input [31:0] value);
        sat_inc32 = (&value) ? value : value + 1'b1;
    endfunction

    pcie_dllp_codec u_codec (
        .clk(clk), .rst_n(rst_n), .enable(link_up),
        .mac_rx_valid(mac_rx_valid), .mac_rx_data(mac_rx_data),
        .mac_rx_keep(mac_rx_keep), .mac_rx_sop(mac_rx_sop),
        .mac_rx_eop(mac_rx_eop), .mac_rx_is_dllp(mac_rx_is_dllp),
        .mac_rx_error(mac_rx_error), .mac_tx_valid(mac_tx_valid),
        .mac_tx_ready(mac_tx_ready), .mac_tx_data(mac_tx_data),
        .mac_tx_keep(mac_tx_keep), .mac_tx_sop(mac_tx_sop),
        .mac_tx_eop(mac_tx_eop), .mac_tx_is_dllp(mac_tx_is_dllp),
        .mac_tx_bad(mac_tx_bad), .rx_dllp_valid(rx_dllp_valid),
        .rx_dllp_data(rx_dllp_data), .rx_dllp_crc_good(rx_dllp_crc_good),
        .rx_dllp_error(rx_dllp_error), .tx_dllp_valid(fc_tx_valid),
        .tx_dllp_ready(fc_tx_ready), .tx_dllp_data(fc_tx_data)
    );

    pcie_dllp_fc_manager #(
        .RX_PH_CREDITS(RX_PH_CREDITS), .RX_PD_CREDITS(RX_PD_CREDITS),
        .RX_NPH_CREDITS(RX_NPH_CREDITS), .RX_NPD_CREDITS(RX_NPD_CREDITS),
        .RX_CPLH_CREDITS(RX_CPLH_CREDITS), .RX_CPLD_CREDITS(RX_CPLD_CREDITS),
        .UPDATE_INTERVAL_CYCLES(UPDATE_INTERVAL_CYCLES)
    ) u_manager (
        .clk(clk), .rst_n(rst_n), .link_up(link_up),
        .rx_dllp_valid(rx_dllp_valid), .rx_dllp_data(rx_dllp_data),
        .rx_dllp_crc_good(rx_dllp_crc_good), .rx_dllp_error(rx_dllp_error),
        .tx_dllp_valid(fc_tx_valid), .tx_dllp_ready(fc_tx_ready),
        .tx_dllp_data(fc_tx_data), .tx_tlp_check_type(tx_tlp_check_type),
        .tx_tlp_check_data_credits(tx_tlp_check_data_credits),
        .tx_tlp_credit_available(tx_tlp_credit_available),
        .tx_tlp_consume_valid(tx_tlp_consume_valid),
        .tx_tlp_consume_type(tx_tlp_consume_type),
        .tx_tlp_consume_data_credits(tx_tlp_consume_data_credits),
        .rx_tlp_consume_valid(rx_tlp_consume_valid),
        .rx_tlp_consume_type(rx_tlp_consume_type),
        .rx_tlp_consume_data_credits(rx_tlp_consume_data_credits),
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            malformed_dllp_count <= 0;
            bad_crc_count <= 0;
        end else if (rx_dllp_valid) begin
            if (rx_dllp_error[0] || rx_dllp_error[1] || rx_dllp_error[3])
                malformed_dllp_count <= sat_inc32(malformed_dllp_count);
            if (rx_dllp_error[2])
                bad_crc_count <= sat_inc32(bad_crc_count);
        end
    end
endmodule

`default_nettype wire
