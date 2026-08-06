`timescale 1ns/1ps
`default_nettype none

// K01 顶层：PCIe 参考时钟缓冲与 standalone PHY/PIPE/Core 复位分发。
module kcu105_refclk_reset #(
    parameter integer RESET_SYNC_STAGES = 4
) (
    input  wire pcie_refclk_p,
    input  wire pcie_refclk_n,
    input  wire pcie_perst_n,
    input  wire phy_pclk,
    input  wire phy_coreclk,
    input  wire phy_phystatus_rst,

    output wire phy_gtrefclk,
    output wire phy_refclk,
    output wire phy_rst_n,
    output wire pipe_rst_n,
    output wire core_rst_n
);

    wire phy_refclk_unbuf;

    IBUFDS_GTE3 #(
        .REFCLK_EN_TX_PATH  (1'b0),
        .REFCLK_HROW_CK_SEL (2'b00),
        .REFCLK_ICNTL_RX    (2'b00)
    ) u_pcie_refclk_ibuf (
        .O     (phy_gtrefclk),
        .ODIV2 (phy_refclk_unbuf),
        .CEB   (1'b0),
        .I     (pcie_refclk_p),
        .IB    (pcie_refclk_n)
    );

    BUFG_GT u_phy_refclk_bufg (
        .O       (phy_refclk),
        .CE      (1'b1),
        .CEMASK  (1'b0),
        .CLR     (1'b0),
        .CLRMASK (1'b0),
        .DIV     (3'b000),
        .I       (phy_refclk_unbuf)
    );

    kcu105_reset_ctrl #(
        .RESET_SYNC_STAGES (RESET_SYNC_STAGES)
    ) u_reset_ctrl (
        .phy_pclk           (phy_pclk),
        .phy_coreclk        (phy_coreclk),
        .pcie_perst_n       (pcie_perst_n),
        .phy_phystatus_rst  (phy_phystatus_rst),
        .phy_rst_n          (phy_rst_n),
        .pipe_rst_n         (pipe_rst_n),
        .core_rst_n         (core_rst_n)
    );

endmodule

`default_nettype wire
