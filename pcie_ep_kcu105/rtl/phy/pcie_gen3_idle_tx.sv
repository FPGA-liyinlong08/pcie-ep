`timescale 1ns/1ps
`default_nettype none

// Minimal K15 Gen3 Data Stream source.  It emits one SDS block followed by
// continuous scrambled 128-bit logical-idle data blocks, separated every 15
// and 16 blocks by a 1-beat PIPE valid gap (TXDATA_VALID low) so the GT
// secureip substitutes real SKP ordered sets.  Without those gaps the link
// violates the 370-375-block maximum SKP interval and the partner VIP/PCS
// drops the stream (SVT max_rx_skp_interval failure, 2026-08-31).  The LFSR
// is frozen across each gap.  It deliberately contains no DLLP or TLP
// support; K16 replaces/extends this source.
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
    // SKP gap cadence over the data stream: 15 data blocks before the first
    // gap, 16 before the second, matching the training-stream rhythm.
    reg [4:0] skp_gap_count;
    reg       gap_run;
    reg       in_gap;
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
            skp_gap_count <= 5'd0;
            gap_run <= 1'b0;
            in_gap <= 1'b0;
            lfsr_state <= LANE0_SEED;
        end else if (!enable) begin
            state <= SEND_SDS;
            word_index <= 2'd0;
            skp_gap_count <= 5'd0;
            gap_run <= 1'b0;
            in_gap <= 1'b0;
            // Track the training transmitter while idle.  On the first SDS
            // beat this is already the state after the final TS word.
            lfsr_state <= lfsr_state_in;
        end else if (in_gap) begin
            // One PIPE beat with TXDATA_VALID low (the GT secureip
            // substitutes a real SKP ordered set there), then the data
            // stream resumes at a block boundary.  The LFSR is frozen
            // across the gap.
            in_gap <= 1'b0;
            word_index <= 2'd0;
        end else if (word_index == 2'd3) begin
            word_index <= 2'd0;
            if (state == SEND_SDS) begin
                state <= SEND_IDLE;
            end else if (skp_gap_count == (gap_run ? 5'd15 : 5'd14)) begin
                // Official cadence: 1-beat PIPE gap between data block runs.
                skp_gap_count <= 5'd0;
                gap_run <= ~gap_run;
                in_gap <= 1'b1;
            end else begin
                skp_gap_count <= skp_gap_count + 1'b1;
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
        if (in_gap) begin
            // The gap beat holds TXDATA_VALID, TXSTART_BLOCK and
            // TXSYNC_HEADER low, like the training transmitter's gap beats.
            out_valid = 1'b0;
            start_block = 1'b0;
            sync_header = 2'b00;
            out_data = 32'd0;
        end else if (state == SEND_SDS) begin
            sync_header = out_valid && (word_index == 2'd0) ?
                          SH_ORDERED_SET : 2'b00;
            // Symbol 0 is E1; Symbols 1..15 are 55.  All Symbols bypass
            // scrambling even though they advance the lane LFSR.
            out_data = (word_index == 2'd0) ? 32'h5555_55e1 :
                                              32'h5555_5555;
        end else begin
            sync_header = out_valid && (word_index == 2'd0) ?
                          SH_DATA : 2'b00;
            out_data = scrambled_zero;
        end
    end
endmodule

`default_nettype wire
