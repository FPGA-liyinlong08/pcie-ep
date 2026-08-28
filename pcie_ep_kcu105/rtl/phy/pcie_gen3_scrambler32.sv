`timescale 1ns/1ps
`default_nettype none

// PCIe 8.0 GT/s 23-bit additive scrambler, one 32-bit PIPE word at a time.
// The lane-0 seed is 23'h1DBFBC.  The state transition implements
// x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1, LSB-first on PIPE data.
// bypass_byte affects only the XOR; the LFSR advances across every byte.
module pcie_gen3_scrambler32 (
    input  wire [22:0] state_in,
    input  wire [31:0] data_in,
    input  wire [3:0]  bypass_byte,
    output reg  [31:0] data_out,
    output reg  [22:0] state_out
);
    // The original bit-at-a-time loop synthesized as a 32-level serial
    // feedback network.  Keep the same polynomial, but express the linear
    // transform eight bits at a time.  Each byte is now a shallow XOR matrix
    // and the four byte stages form only four levels of state dependency.
    function automatic [22:0] advance8;
        input [22:0] state;
        begin
            advance8[0]  = ^(state & 23'h6a8000);
            advance8[1]  = ^(state & 23'h550000);
            advance8[2]  = ^(state & 23'h408000);
            advance8[3]  = ^(state & 23'h010000);
            advance8[4]  = ^(state & 23'h020000);
            advance8[5]  = ^(state & 23'h6e8000);
            advance8[6]  = ^(state & 23'h5d0000);
            advance8[7]  = ^(state & 23'h3a0000);
            advance8[8]  = ^(state & 23'h1e8001);
            advance8[9]  = ^(state & 23'h3d0002);
            advance8[10] = ^(state & 23'h7a0004);
            advance8[11] = ^(state & 23'h740008);
            advance8[12] = ^(state & 23'h680010);
            advance8[13] = ^(state & 23'h500020);
            advance8[14] = ^(state & 23'h200040);
            advance8[15] = ^(state & 23'h400080);
            advance8[16] = ^(state & 23'h6a8100);
            advance8[17] = ^(state & 23'h550200);
            advance8[18] = ^(state & 23'h2a0400);
            advance8[19] = ^(state & 23'h540800);
            advance8[20] = ^(state & 23'h281000);
            advance8[21] = ^(state & 23'h3aa000);
            advance8[22] = ^(state & 23'h754000);
        end
    endfunction

    function automatic [7:0] scramble_byte;
        input [22:0] state;
        begin
            scramble_byte[0] = ^(state & 23'h400000);
            scramble_byte[1] = ^(state & 23'h200000);
            scramble_byte[2] = ^(state & 23'h500000);
            scramble_byte[3] = ^(state & 23'h280000);
            scramble_byte[4] = ^(state & 23'h540000);
            scramble_byte[5] = ^(state & 23'h2a0000);
            scramble_byte[6] = ^(state & 23'h550000);
            scramble_byte[7] = ^(state & 23'h6a8000);
        end
    endfunction

    wire [7:0]  scramble_byte0 = scramble_byte(state_in);
    wire [22:0] state_byte1 = advance8(state_in);
    wire [7:0]  scramble_byte1 = scramble_byte(state_byte1);
    wire [22:0] state_byte2 = advance8(state_byte1);
    wire [7:0]  scramble_byte2 = scramble_byte(state_byte2);
    wire [22:0] state_byte3 = advance8(state_byte2);
    wire [7:0]  scramble_byte3 = scramble_byte(state_byte3);
    wire [22:0] state_after32 = advance8(state_byte3);
    wire [31:0] scramble_mask = {
        scramble_byte3, scramble_byte2, scramble_byte1, scramble_byte0
    };
    wire [31:0] scramble_enable = {
        {8{!bypass_byte[3]}}, {8{!bypass_byte[2]}},
        {8{!bypass_byte[1]}}, {8{!bypass_byte[0]}}
    };

    always @* begin
        data_out = data_in ^ (scramble_mask & scramble_enable);
        state_out = state_after32;
    end
endmodule

`default_nettype wire
