`timescale 1ns/1ps

// 故意错误：复位永久释放，用于证明 K01 Checker 能观察到复位安全错误。
module kcu105_reset_ctrl #(
    parameter integer RESET_SYNC_STAGES = 4
) (
    input  logic phy_pclk,
    input  logic phy_coreclk,
    input  logic pcie_perst_n,
    input  logic phy_phystatus_rst,
    output logic phy_rst_n,
    output logic pipe_rst_n,
    output logic core_rst_n
);

    assign phy_rst_n  = 1'b1;
    assign pipe_rst_n = 1'b1;
    assign core_rst_n = 1'b1;

endmodule
