`timescale 1ns/1ps
`default_nettype none

// KCU105 standalone PCIe PHY 的复位分发。
// PERST# 异步置位全部复位；PHY Status Reset 只异步置位 PIPE 域复位。
module kcu105_reset_ctrl #(
    parameter integer RESET_SYNC_STAGES = 4
) (
    input  wire phy_pclk,
    input  wire phy_coreclk,
    input  wire pcie_perst_n,
    input  wire phy_phystatus_rst,

    output wire phy_rst_n,
    output wire pipe_rst_n,
    output wire core_rst_n
);

    wire pipe_async_release_n;

    generate
        if ((RESET_SYNC_STAGES < 2) || (RESET_SYNC_STAGES > 8)) begin : g_invalid_stages
            initial $error("kcu105_reset_ctrl: RESET_SYNC_STAGES must be in [2, 8]");
        end
    endgenerate

    assign phy_rst_n             = pcie_perst_n;
    assign pipe_async_release_n  = pcie_perst_n && !phy_phystatus_rst;

    pcie_reset_sync #(
        .STAGES (RESET_SYNC_STAGES)
    ) u_pipe_reset_sync (
        .clk             (phy_pclk),
        .async_release_n (pipe_async_release_n),
        .sync_reset_n    (pipe_rst_n)
    );

    pcie_reset_sync #(
        .STAGES (RESET_SYNC_STAGES)
    ) u_core_reset_sync (
        .clk             (phy_coreclk),
        .async_release_n (pcie_perst_n),
        .sync_reset_n    (core_rst_n)
    );

endmodule

`default_nettype wire
