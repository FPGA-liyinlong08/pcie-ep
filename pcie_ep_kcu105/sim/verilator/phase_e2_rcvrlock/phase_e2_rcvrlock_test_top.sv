`timescale 1ns/1ps
`default_nettype none

module phase_e2_rcvrlock_test_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       block_locked,
    input  wire       lock_lost,
    input  wire       ts1_valid,
    input  wire       ts1_fields_match,
    input  wire       ts2_valid,
    input  wire       malformed,
    output wire       complete,
    output wire       failed,
    output wire [4:0] ts1_count
);
    pcie_gen3_rcvrlock_ctrl #(.TS_REQUIRED(5'd8)) u_dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .block_locked(block_locked), .lock_lost(lock_lost),
        .ts1_valid(ts1_valid), .ts1_fields_match(ts1_fields_match),
        .ts2_valid(ts2_valid), .malformed(malformed),
        .complete(complete), .failed(failed), .ts1_count(ts1_count)
    );
endmodule

`default_nettype wire
