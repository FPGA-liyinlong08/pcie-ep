`timescale 1ns/1ps
`default_nettype none

// Minimal K15 Gen3 Data Stream source.  It emits one SDS block followed by
// continuous scrambled 128-bit logical-idle data blocks, separated every 370
// and 371 blocks by an explicit 16-symbol SKP Ordered Set block, and pauses
// TXDATA_VALID for one beat at a block boundary every 16 blocks (128b/130b
// rate match; see RATE_GAP_BLOCKS below).
//
// Cadence: spec r3.1a Errata B34 requires a scheduled SKP OS "at an interval
// between 370 to 375 blocks" in L0 for a Link that is not in SRIS (common
// clock / SRNS -- the K11-B board feeds both partners from one refclk).  The
// earlier 15/16-block cadence (added for the SVT VIP max_rx_skp_interval
// check) is SRIS-class density; the RP RX GT deleted every one of those SKP
// OSs, its RX elastic buffer underflowed and repeated a data beat, which
// permanently misaligned the 128b/130b block framing (no EIEOS in L0 to
// re-align) and drove the endless RP L0->Recovery loop.  (An intermediate
// revision replaced the 1-beat PIPE valid gap with an explicit SKP OS block;
// the RP RX GT produced the identical corruption for both, because the
// corruption is the SKP *deletion*, not the wire format.)
//
// The SKP OS uses the os_tx format already verified against the RP and the
// SVT VIP (12x AA + SKP_END tail, commit 2252e15).  The LFSR is frozen across
// the SKP OS.  It deliberately contains no DLLP or TLP support; K16
// replaces/extends this source.
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
    localparam [1:0] SEND_SDS = 2'd0;
    localparam [1:0] SEND_IDLE = 2'd1;
    localparam [1:0] SEND_SKP  = 2'd2;
    localparam [1:0] SEND_GAP  = 2'd3;
    // Gen3 SKP symbol: 8'haa (8'h1c is the 8b/10b Gen1/2 code).
    localparam [7:0] SKP_SYM = 8'haa;
    // Spec Errata B34: SKP OS interval 370..375 blocks outside SRIS.  The
    // 10-bit counter toggles between 370 and 371 so both values stay legal.
    // DEBUG K15_RP_L0_FIX: dense SRIS-class cadence so the RP RX GT always
    // has real SKP OSs to clock-correct against in L0.
`ifdef K15_L0_SKP_DENSE
    localparam [9:0] SKP_GAP_A = 10'd4;
    localparam [9:0] SKP_GAP_B = 10'd5;
`else
    localparam [9:0] SKP_GAP_A = 10'd370;
    localparam [9:0] SKP_GAP_B = 10'd371;
`endif
    // K15 RP L0 fix: 1-beat PIPE valid gap (TXDATA_VALID low) every 16
    // blocks, at a block boundary.  A Gen3 block occupies 130 bit times on
    // the wire, so the wire's payload capacity is 64/65 of the 250 MHz /
    // 32-bit PIPE interface rate; a continuous stream over-drives the GT TX
    // buffer by exactly 1 beat per 65 (every 260ns) and the model drops it,
    // which the RP RX GT repairs by repeating a *data* beat (no SKP nearby)
    // -- the observed 260ns bubble and the endless RP L0<->Recovery loop.
    // The GT secureip substitutes a real SKP OS during every valid gap
    // (same mechanism as the training transmitter), giving the partner RX
    // elastic buffer SKP symbols to clock-correct with: at one gap per 16
    // blocks the EP TX buffer is exactly balanced (64/65 = 128/130).
    // Cadence note: one gap per 15 blocks (os_tx training density) drains
    // the EP TX buffer, and explicit SKP OS blocks alone (the earlier
    // 4/5-block and 370/371-block cadences) change nothing -- the drop is
    // duty-cycle driven, not SKP-content driven.
    localparam [4:0] RATE_GAP_BLOCKS = 5'd16;

    reg [1:0] state;
    reg [1:0] word_index;
    reg [1:0] skp_word_index;
    reg [22:0] lfsr_state;
    reg [9:0] skp_gap_count;
    reg [4:0] rate_gap_cnt;
    reg       gap_run;
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
            skp_word_index <= 2'd0;
            skp_gap_count <= 10'd0;
            rate_gap_cnt <= 5'd0;
            gap_run <= 1'b0;
            lfsr_state <= LANE0_SEED;
        end else if (!enable) begin
            state <= SEND_SDS;
            word_index <= 2'd0;
            skp_word_index <= 2'd0;
            skp_gap_count <= 10'd0;
            rate_gap_cnt <= 5'd0;
            gap_run <= 1'b0;
            // Track the training transmitter while idle.  On the first SDS
            // beat this is already the state after the final TS word.
            lfsr_state <= lfsr_state_in;
        end else if (state == SEND_GAP) begin
            // One-beat pause between blocks; out_valid is low this beat and
            // the GT secureip substitutes an SKP OS (see RATE_GAP_BLOCKS).
            state <= SEND_IDLE;
            word_index <= 2'd0;
        end else if (state == SEND_SKP) begin
            // Four unscrambled beats; the lane LFSR is frozen across the SKP
            // OS exactly as in the training transmitter.
            if (skp_word_index == 2'd3) begin
                skp_word_index <= 2'd0;
                word_index <= 2'd0;
                rate_gap_cnt <= rate_gap_cnt + 1'b1;
                state <= SEND_IDLE;
            end else begin
                skp_word_index <= skp_word_index + 1'b1;
            end
        end else if (word_index == 2'd3) begin
            word_index <= 2'd0;
            if (state == SEND_SDS) begin
                state <= SEND_IDLE;
                rate_gap_cnt <= 5'd0;
            end else if (rate_gap_cnt >= RATE_GAP_BLOCKS) begin
                rate_gap_cnt <= 5'd0;
                state <= SEND_GAP;
            end else if (skp_gap_count == (gap_run ? SKP_GAP_B : SKP_GAP_A)) begin
                skp_gap_count <= 10'd0;
                gap_run <= ~gap_run;
                state <= SEND_SKP;
                skp_word_index <= 2'd0;
                rate_gap_cnt <= rate_gap_cnt + 1'b1;
            end else begin
                skp_gap_count <= skp_gap_count + 1'b1;
                rate_gap_cnt <= rate_gap_cnt + 1'b1;
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
        out_valid = enable && (state != SEND_GAP);
        start_block = enable && (word_index == 2'd0) &&
                      (state != SEND_SKP) && (state != SEND_GAP);
        sync_header = 2'b00;
        out_data = 32'd0;
        if (state == SEND_SKP) begin
            // 16-symbol SKP OS, identical to pcie_gen3_os_tx.sv SEND_SKP:
            // 12 SKP symbols then the SKP_END tail
            // {SKP_END, Data Parity + LFSR[22:16], LFSR[15:8], LFSR[7:0]},
            // wire order bits[7:0] first.
            start_block = (skp_word_index == 2'd0);
            sync_header = (skp_word_index == 2'd0) ? SH_ORDERED_SET : 2'b00;
            case (skp_word_index)
                2'd0, 2'd1, 2'd2: out_data = {4{SKP_SYM}};
                default: out_data = {lfsr_state[7:0], lfsr_state[15:8],
                                     ~lfsr_state[22], lfsr_state[22:16],
                                     8'he1};
            endcase
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
