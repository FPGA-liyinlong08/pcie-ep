`timescale 1ns/1ps

// 故意错误的测试 Stub：用于证明 M01 Checker 能发现复位无法释放。
module pcie_clk_reset_ctrl #(
    parameter integer RESET_SYNC_STAGES  = 4,
    parameter integer STATUS_SYNC_STAGES = 2
) (
    input  logic core_clk,
    input  logic pipe_clk,
    input  logic pcie_perst_n,
    input  logic core_clock_locked,
    input  logic gt_pll_lock,
    input  logic gt_tx_reset_done,
    input  logic gt_rx_reset_done,
    output logic core_rst_n,
    output logic pipe_rst_n,
    output logic clock_ready
);

    assign core_rst_n  = 1'b0;
    assign pipe_rst_n  = 1'b0;
    assign clock_ready = 1'b0;

endmodule

