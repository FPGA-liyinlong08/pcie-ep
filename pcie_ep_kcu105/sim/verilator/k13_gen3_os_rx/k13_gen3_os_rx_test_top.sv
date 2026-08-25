`timescale 1ns/1ps
`default_nettype none

module k13_gen3_os_rx_test_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        in_valid,
    input  wire        start_block,
    input  wire [1:0]  sync_header,
    input  wire [31:0] in_data,
    output wire        ts1_valid,
    output wire        ts2_valid,
    output wire        malformed,
    output wire        idle_valid,
    output wire        block_locked,
    output wire        lock_acquired,
    output wire        lock_lost,
    output wire        eieos_valid,
    output wire        sds_valid,
    output wire [7:0]  link_number,
    output wire        link_is_pad,
    output wire [7:0]  lane_number,
    output wire        lane_is_pad,
    output wire [7:0]  n_fts,
    output wire [7:0]  rate_id,
    output wire [7:0]  training_control,
    output wire [7:0]  eq_control,
    output wire [23:0] eq_data
);
    pcie_gen3_os_rx u_rx (
        .clk(clk), .rst_n(rst_n), .enable(enable), .in_valid(in_valid),
        .start_block(start_block), .sync_header(sync_header), .in_data(in_data),
        .ts1_valid(ts1_valid), .ts2_valid(ts2_valid), .malformed(malformed),
        .idle_valid(idle_valid), .link_number(link_number),
        .block_locked(block_locked), .lock_acquired(lock_acquired),
        .lock_lost(lock_lost), .eieos_valid(eieos_valid),
        .sds_valid(sds_valid),
        .link_is_pad(link_is_pad), .lane_number(lane_number),
        .lane_is_pad(lane_is_pad), .n_fts(n_fts), .rate_id(rate_id),
        .training_control(training_control), .eq_control(eq_control),
        .eq_data(eq_data)
    );
endmodule

`default_nettype wire
