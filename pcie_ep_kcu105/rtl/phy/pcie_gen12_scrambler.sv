`timescale 1ns/1ps
`default_nettype none

// PCIe Gen1/2 16-bit并行扰码/解扰器。加性扰码在TX和RX使用相同逻辑。
// Symbol 0（in_data[7:0]）先处理并先上线。
module pcie_gen12_scrambler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire        scramble_disable,
    input  wire [15:0] in_data,
    input  wire [1:0]  in_datak,
    output wire        out_valid,
    output wire [15:0] out_data,
    output wire [1:0]  out_datak,
    output wire [15:0] lfsr_state
);
    localparam [7:0] K_COM = 8'hbc;
    localparam [7:0] K_SKP = 8'h1c;

    reg [15:0] lfsr;

    function automatic [15:0] advance_byte(input [15:0] value);
        begin
            advance_byte[0]  = value[8];
            advance_byte[1]  = value[9];
            advance_byte[2]  = value[10];
            advance_byte[3]  = value[11] ^ value[8];
            advance_byte[4]  = value[12] ^ value[9] ^ value[8];
            advance_byte[5]  = value[13] ^ value[10] ^ value[9] ^ value[8];
            advance_byte[6]  = value[14] ^ value[11] ^ value[10] ^ value[9];
            advance_byte[7]  = value[15] ^ value[12] ^ value[11] ^ value[10];
            advance_byte[8]  = value[0] ^ value[13] ^ value[12] ^ value[11];
            advance_byte[9]  = value[1] ^ value[14] ^ value[13] ^ value[12];
            advance_byte[10] = value[2] ^ value[15] ^ value[14] ^ value[13];
            advance_byte[11] = value[3] ^ value[15] ^ value[14];
            advance_byte[12] = value[4] ^ value[15];
            advance_byte[13] = value[5];
            advance_byte[14] = value[6];
            advance_byte[15] = value[7];
        end
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic [7:0] scramble_mask(input [15:0] value);
        begin
            scramble_mask = {value[8], value[9], value[10], value[11],
                             value[12], value[13], value[14], value[15]};
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic [15:0] next_symbol_state(
        input [15:0] value,
        input [7:0]  symbol,
        input        symbol_k
    );
        begin
            if (symbol_k && (symbol == K_COM))
                next_symbol_state = 16'hffff;
            else if (symbol_k && (symbol == K_SKP))
                next_symbol_state = value;
            else
                next_symbol_state = advance_byte(value);
        end
    endfunction

    wire [15:0] state_after_symbol0 = next_symbol_state(
        lfsr, in_data[7:0], in_datak[0]);
    wire [15:0] state_after_symbol1 = next_symbol_state(
        state_after_symbol0, in_data[15:8], in_datak[1]);

    wire bypass_symbol0 = scramble_disable || in_datak[0];
    wire bypass_symbol1 = scramble_disable || in_datak[1];

    assign out_valid = in_valid;
    assign out_data[7:0] = bypass_symbol0 ? in_data[7:0] :
                           (in_data[7:0] ^ scramble_mask(lfsr));
    assign out_data[15:8] = bypass_symbol1 ? in_data[15:8] :
                            (in_data[15:8] ^ scramble_mask(state_after_symbol0));
    assign out_datak = in_datak;
    assign lfsr_state = lfsr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 16'hffff;
        else if (in_valid)
            lfsr <= state_after_symbol1;
    end
endmodule

`default_nettype wire
