`timescale 1ns/1ps
`default_nettype none

// K14 Golden SVT overlay: follow PIPE comma phase changes in either direction.
module pcie_gen1_rx_symbol_aligner (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_data,
    input  wire [1:0]  in_datak,
    output wire        out_valid,
    output wire [15:0] out_data,
    output wire [1:0]  out_datak
);
    localparam [7:0] K_COM = 8'hbc;

    reg       shift_one_symbol;
    reg [7:0] saved_high_data;
    reg       saved_high_k;
    wire      low_com = in_datak[0] && (in_data[7:0] == K_COM);
    wire      high_com = in_datak[1] && (in_data[15:8] == K_COM) && !low_com;
    wire      realign_to_low = shift_one_symbol && low_com;

    // If PIPE has moved COM back to symbol 0, use that word directly and clear
    // the sticky one-symbol shift.  A high COM still starts the normal carry.
    assign out_valid = in_valid &&
                       (realign_to_low || shift_one_symbol || !high_com);
    assign out_data  = realign_to_low ? in_data :
                       shift_one_symbol ? {in_data[7:0], saved_high_data} :
                                          in_data;
    assign out_datak = realign_to_low ? in_datak :
                       shift_one_symbol ? {in_datak[0], saved_high_k} :
                                          in_datak;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_one_symbol <= 1'b0;
            saved_high_data  <= 8'd0;
            saved_high_k     <= 1'b0;
        end else if (!in_valid) begin
            shift_one_symbol <= 1'b0;
            saved_high_data  <= 8'd0;
            saved_high_k     <= 1'b0;
        end else if (realign_to_low) begin
            shift_one_symbol <= 1'b0;
            saved_high_data  <= 8'd0;
            saved_high_k     <= 1'b0;
        end else if (shift_one_symbol) begin
            saved_high_data <= in_data[15:8];
            saved_high_k    <= in_datak[1];
        end else if (high_com) begin
            shift_one_symbol <= 1'b1;
            saved_high_data  <= in_data[15:8];
            saved_high_k     <= in_datak[1];
        end
    end
endmodule

`default_nettype wire
