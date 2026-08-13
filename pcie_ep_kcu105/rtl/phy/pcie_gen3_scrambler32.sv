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
    integer bit_index;
    reg [22:0] work;
    reg feedback;

    always @* begin
        work = state_in;
        data_out = data_in;
        for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
            if (!bypass_byte[bit_index / 8])
                data_out[bit_index] = data_in[bit_index] ^ work[22];

            feedback = work[22];
            work = {work[21:0], feedback};
            work[21] = work[21] ^ feedback;
            work[16] = work[16] ^ feedback;
            work[8]  = work[8]  ^ feedback;
            work[5]  = work[5]  ^ feedback;
            work[2]  = work[2]  ^ feedback;
        end
        state_out = work;
    end
endmodule

`default_nettype wire
