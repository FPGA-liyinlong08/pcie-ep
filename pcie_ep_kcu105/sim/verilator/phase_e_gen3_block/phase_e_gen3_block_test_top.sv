`timescale 1ns/1ps
`default_nettype none

module phase_e_gen3_block_test_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        rx_enable,
    input  wire        rx_in_valid,
    input  wire        rx_start_block,
    input  wire [1:0]  rx_sync_header,
    input  wire [31:0] rx_data,
    output wire        rx_ts1_valid,
    output wire        rx_ts2_valid,
    output wire        rx_malformed,
    output wire        rx_idle_valid,
    output wire        rx_block_locked,
    output wire        rx_lock_acquired,
    output wire        rx_lock_lost,
    output wire        rx_eieos_valid,
    output wire        rx_sds_valid,
    output wire [7:0]  rx_link_number,
    output wire        rx_link_is_pad,
    output wire [7:0]  rx_lane_number,
    output wire        rx_lane_is_pad,
    output wire [7:0]  rx_n_fts,
    output wire [7:0]  rx_rate_id,
    output wire [7:0]  rx_training_control,
    output wire [7:0]  rx_eq_control,
    output wire [23:0] rx_eq_data,

    input  wire        tx_enable,
    input  wire [1:0]  tx_mode,
    input  wire [7:0]  tx_link_number,
    input  wire        tx_link_is_pad,
    input  wire [7:0]  tx_lane_number,
    input  wire        tx_lane_is_pad,
    input  wire [7:0]  tx_n_fts,
    input  wire [7:0]  tx_rate_id,
    input  wire [7:0]  tx_training_control,
    input  wire [7:0]  tx_eq_control,
    input  wire [23:0] tx_eq_data,
    output wire [31:0] tx_data,
    output wire        tx_valid,
    output wire        tx_start_block,
    output wire [1:0]  tx_sync_header,
    output wire        tx_os_complete
);
    wire [1:0] tx_word_index_unused;

    pcie_gen3_os_rx u_rx (
        .clk(clk), .rst_n(rst_n), .enable(rx_enable),
        .in_valid(rx_in_valid), .start_block(rx_start_block),
        .sync_header(rx_sync_header), .in_data(rx_data),
        .ts1_valid(rx_ts1_valid), .ts2_valid(rx_ts2_valid),
        .malformed(rx_malformed), .idle_valid(rx_idle_valid),
        .block_locked(rx_block_locked),
        .lock_acquired(rx_lock_acquired), .lock_lost(rx_lock_lost),
        .eieos_valid(rx_eieos_valid), .sds_valid(rx_sds_valid),
        .link_number(rx_link_number), .link_is_pad(rx_link_is_pad),
        .lane_number(rx_lane_number), .lane_is_pad(rx_lane_is_pad),
        .n_fts(rx_n_fts), .rate_id(rx_rate_id),
        .training_control(rx_training_control),
        .eq_control(rx_eq_control), .eq_data(rx_eq_data)
    );

    pcie_gen3_os_tx u_tx (
        .clk(clk), .rst_n(rst_n), .enable(tx_enable), .mode(tx_mode),
        .link_number(tx_link_number), .link_is_pad(tx_link_is_pad),
        .lane_number(tx_lane_number), .lane_is_pad(tx_lane_is_pad),
        .n_fts(tx_n_fts), .rate_id(tx_rate_id),
        .training_control(tx_training_control),
        .eq_control(tx_eq_control), .eq_data(tx_eq_data),
        .out_data(tx_data), .out_valid(tx_valid),
        .start_block(tx_start_block), .sync_header(tx_sync_header),
        .os_complete(tx_os_complete),
        .word_index_debug(tx_word_index_unused)
    );
endmodule

`default_nettype wire
