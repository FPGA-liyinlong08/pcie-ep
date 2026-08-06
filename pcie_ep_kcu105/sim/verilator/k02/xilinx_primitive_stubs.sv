`timescale 1ns/1ps

module IBUFDS_GTE3 #(
    parameter REFCLK_EN_TX_PATH = 1'b0,
    parameter [1:0] REFCLK_HROW_CK_SEL = 2'b00,
    parameter [1:0] REFCLK_ICNTL_RX = 2'b00
) (
    output wire O,
    output wire ODIV2,
    input  wire CEB,
    input  wire I,
    input  wire IB
);
    assign O = CEB ? 1'b0 : I;
    assign ODIV2 = CEB ? 1'b0 : I;
endmodule

module BUFG_GT (
    output wire O,
    input  wire CE,
    input  wire CEMASK,
    input  wire CLR,
    input  wire CLRMASK,
    input  wire [2:0] DIV,
    input  wire I
);
    assign O = (CLR && !CLRMASK) ? 1'b0 : ((CE || CEMASK) ? I : 1'b0);
endmodule
