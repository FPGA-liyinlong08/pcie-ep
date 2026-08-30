`timescale 1ns/1ps
`default_nettype none

// Minimal K15 Gen3 Data Stream source.  It emits one SDS block followed by
// continuous scrambled 128-bit logical-idle data blocks.  It deliberately
// contains no SKP, DLLP or TLP support; K16 replaces/extends this source.
module pcie_gen3_idle_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    // Lane scrambler state immediately after the final Recovery Ordered Set.
    input  wire [22:0] lfsr_state_in,
    output reg  [31:0] out_data,
    output reg         out_valid,
    output reg         start_block,
    output reg  [1:0]  sync_header,
    output wire        idle_block_complete
);
    localparam [1:0] SH_ORDERED_SET = 2'b01;
    localparam [1:0] SH_DATA = 2'b10;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;
    localparam SEND_SDS = 1'b0;
    localparam SEND_IDLE = 1'b1;

    reg state;
    reg [1:0] word_index;
    reg [22:0] lfsr_state;
    wire [31:0] scrambled_zero;
    wire [22:0] lfsr_next;

    pcie_gen3_scrambler32 u_scrambler (
        .state_in(lfsr_state), .data_in(32'd0), .bypass_byte(4'b0000),
        .data_out(scrambled_zero), .state_out(lfsr_next)
    );

    assign idle_block_complete = enable && (state == SEND_IDLE) &&
                                 (word_index == 2'd3);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= SEND_SDS;
            word_index <= 2'd0;
            lfsr_state <= LANE0_SEED;
        end else if (!enable) begin
            state <= SEND_SDS;
            word_index <= 2'd0;
            // Track the training transmitter while idle.  On the first SDS
            // beat this is already the state after the final TS word.
            lfsr_state <= lfsr_state_in;
        end else if (word_index == 2'd3) begin
            word_index <= 2'd0;
            if (state == SEND_SDS) begin
                state <= SEND_IDLE;
            end
            // SDS bypasses XOR but, unlike SKP, advances the LFSR over all
            // 16 Symbols.  The first Data Block therefore starts here.
            lfsr_state <= lfsr_next;
        end else begin
            word_index <= word_index + 1'b1;
            lfsr_state <= lfsr_next;
        end
    end

    always @* begin
        out_valid = enable;
        start_block = enable && (word_index == 2'd0);
        sync_header = 2'b00;
        out_data = 32'd0;
        if (state == SEND_SDS) begin
`ifdef K15_AB_HEADER_HELD
            sync_header = out_valid ? SH_ORDERED_SET : 2'b00;
`else
            sync_header = out_valid && (word_index == 2'd0) ?
                          SH_ORDERED_SET : 2'b00;
`endif
            // Symbol 0 is E1; Symbols 1..15 are 55.  All Symbols bypass
            // scrambling even though they advance the lane LFSR.
            out_data = (word_index == 2'd0) ? 32'h5555_55e1 :
                                              32'h5555_5555;
        end else begin
`ifdef K15_AB_HEADER_HELD
            sync_header = out_valid ? SH_DATA : 2'b00;
`else
            sync_header = out_valid && (word_index == 2'd0) ?
                          SH_DATA : 2'b00;
`endif
            out_data = scrambled_zero;
        end
    end
endmodule

`default_nettype wire
