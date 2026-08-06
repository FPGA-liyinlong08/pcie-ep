`timescale 1ns/1ps
`default_nettype none

// K05 KU040 OOC 资源、250 MHz时序、CDC和DRC签核顶层。
module k05_dllp_fc_ooc_top (
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
    output wire [31:0] malformed_dllp_count,
    output wire [31:0] bad_crc_count,
    output wire [31:0] fc_protocol_error_count,
    output wire [31:0] tx_fc_count,
    output wire [31:0] rx_fc_count
);
    wire dll_rst_n;
    pcie_reset_sync #(.STAGES(4)) u_ooc_reset_sync (
        .clk(clk), .async_release_n(rst_n), .sync_reset_n(dll_rst_n)
    );

    pcie_dllp_fc u_dut (
        .rst_n(dll_rst_n), .*
    );
endmodule

`default_nettype wire
