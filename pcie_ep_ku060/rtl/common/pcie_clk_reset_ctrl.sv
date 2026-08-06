`timescale 1ns/1ps
`default_nettype none

// 不包含厂商时钟原语的复位与状态控制核心。
module pcie_clk_reset_ctrl #(
    parameter integer RESET_SYNC_STAGES  = 4,
    parameter integer STATUS_SYNC_STAGES = 2
) (
    input  wire core_clk,
    input  wire pipe_clk,

    input  wire pcie_perst_n,
    input  wire core_clock_locked,
    input  wire gt_pll_lock,
    input  wire gt_tx_reset_done,
    input  wire gt_rx_reset_done,

    output wire core_rst_n,
    output wire pipe_rst_n,
    output wire clock_ready
);

    wire core_async_release_n;
    wire pipe_async_release_n;
    wire gt_ready_async;
    wire gt_ready_core;
    wire pipe_reset_released_core;

    generate
        if ((RESET_SYNC_STAGES < 2) || (RESET_SYNC_STAGES > 8)) begin : g_invalid_reset_stages
            initial $error("pcie_clk_reset_ctrl: RESET_SYNC_STAGES must be in range 2..8");
        end
        if ((STATUS_SYNC_STAGES < 2) || (STATUS_SYNC_STAGES > 4)) begin : g_invalid_status_stages
            initial $error("pcie_clk_reset_ctrl: STATUS_SYNC_STAGES must be in range 2..4");
        end
    endgenerate

    assign gt_ready_async = gt_pll_lock && gt_tx_reset_done && gt_rx_reset_done;

    // 任一异步条件撤销都会立即重新置位相应时钟域复位。
    assign core_async_release_n = pcie_perst_n && core_clock_locked;
    assign pipe_async_release_n = pcie_perst_n && gt_ready_async;

    pcie_reset_sync #(
        .STAGES (RESET_SYNC_STAGES)
    ) u_core_reset_sync (
        .clk             (core_clk),
        .async_release_n (core_async_release_n),
        .sync_reset_n    (core_rst_n)
    );

    pcie_reset_sync #(
        .STAGES (RESET_SYNC_STAGES)
    ) u_pipe_reset_sync (
        .clk             (pipe_clk),
        .async_release_n (pipe_async_release_n),
        .sync_reset_n    (pipe_rst_n)
    );

    pcie_bit_sync #(
        .STAGES (STATUS_SYNC_STAGES)
    ) u_gt_ready_core_sync (
        .clk      (core_clk),
        .rst_n    (core_rst_n),
        .async_in (gt_ready_async),
        .sync_out (gt_ready_core)
    );

    pcie_bit_sync #(
        .STAGES (STATUS_SYNC_STAGES)
    ) u_pipe_reset_core_sync (
        .clk      (core_clk),
        .rst_n    (core_rst_n),
        .async_in (pipe_rst_n),
        .sync_out (pipe_reset_released_core)
    );

    assign clock_ready = core_rst_n && gt_ready_core && pipe_reset_released_core;

endmodule

`default_nettype wire

