`timescale 1ns/1ps
module pcie_gen12_scrambler (
    input wire clk, input wire rst_n, input wire in_valid,
    input wire scramble_disable, input wire [15:0] in_data,
    input wire [1:0] in_datak, output wire out_valid,
    output wire [15:0] out_data, output wire [1:0] out_datak,
    output wire [15:0] lfsr_state
);
    assign out_valid = in_valid;
    assign out_data = in_data;
    assign out_datak = in_datak;
    assign lfsr_state = 16'hffff;
    wire unused = &{1'b0, clk, rst_n, scramble_disable};
endmodule
