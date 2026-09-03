`timescale 1ns/1ps
`default_nettype none

// Minimal K15 Gen3 Data Stream source.  It emits one SDS block followed by
// continuous scrambled 128-bit logical-idle data blocks.  An EDS-terminated
// Data Block frames each explicit 16-symbol SKP Ordered Set scheduled every
// 370/371 blocks, after which the Data Stream resumes without another SDS.
// The transmitter also pauses
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
    localparam [2:0] SEND_SDS  = 3'd0;
    localparam [2:0] SEND_IDLE = 3'd1;
    localparam [2:0] SEND_SKP  = 3'd2;
    localparam [2:0] SEND_GAP  = 3'd3;
    localparam [2:0] SEND_EDS  = 3'd4;
    // Four-Symbol End Data Stream token, wire byte order 1f 80 90 00.
    localparam [31:0] EDS_TOKEN = 32'h0090_801f;
    // Gen3 SKP symbol: 8'haa (8'h1c is the 8b/10b Gen1/2 code).
    localparam [7:0] SKP_SYM = 8'haa;
    // Spec Errata B34: SKP OS interval 370..375 blocks outside SRIS.  The
    // 10-bit counter toggles between 370 and 371 so both values stay legal.
    // Diagnostic dense cadence for the 65-byte compensation artifact in the
    // composed Xilinx secureip/SVT model.  It is not the board default.
`ifdef K15_L0_SKP_DENSE
    // After the first SKP, two Idle Data Blocks plus the EDS and SKP blocks
    // form a 64-byte cycle.  This brackets every 65-byte structural
    // compensation event in the SVT PIPE model with a legal SKP boundary.
    localparam [9:0] SKP_GAP_A = 10'd1;
    localparam [9:0] SKP_GAP_B = 10'd1;
    // Recovery.Idle still needs eight consecutive Idle Data Blocks before
    // the first EDS/SKP pair is allowed to interrupt the stream.
    localparam [9:0] FIRST_SKP_GAP = 10'd7;
`else
    localparam [9:0] SKP_GAP_A = 10'd370;
    localparam [9:0] SKP_GAP_B = 10'd371;
    localparam [9:0] FIRST_SKP_GAP = SKP_GAP_A;
`endif
    // l0fix29 finding: the first SKP OS block in L0 breaks the RP GT's
    // 128b/130b framing (3 aa beats decoded, 4th beat alien, sb never
    // asserts again) and shifts the EP gap grid by 4 beats (SKP block not
    // counted by the gap counter) -- the Xilinx demo EP shows NO SKP OS
    // events at the RP RX PIPE output in L0 at all.  K15_L0_SKP_OFF
    // disables the scheduled SKP OS in the idle stream entirely; SVT VIP
    // SKP-interval compliance must be solved separately.
`ifdef K15_L0_SKP_OFF
    localparam SKP_OS_DISABLE = 1'b1;
`else
    localparam SKP_OS_DISABLE = 1'b0;
`endif
    // K15_SVT l0fix30i finding: the 1-beat v=0 gap beat reaches the wire as
    // 4 bytes of TXDATA residue with no block framing (the GT secureip does
    // NOT substitute an SKP OS there in a data stream).  The Xilinx RP GT
    // survives because its 65-beat comp event is a *deletion* phase-aligned
    // onto the gap (PHASE=4), which swallows exactly those 4 bytes.  The SVT
    // VIP comp event is an *insertion* (1-beat data_valid=0 stall, mask +
    // repeat): the VIP PCS counts stalls correctly (12 clean blocks verified
    // across 3 stalls) but cannot swallow the unframed gap bytes -- the next
    // block boundary check reads their sh bits (2'b00) and shuts the
    // receiver down (status=6).  K15_L0_GAP_OFF removes the gap beat from
    // the idle stream entirely for SVT-class receivers; rate matching is
    // then carried by the scheduled SKP OS blocks (370/371-block cadence)
    // and the VIP's own benign stalls.
`ifdef K15_L0_GAP_OFF
    localparam GAP_OS_DISABLE = 1'b1;
`else
    localparam GAP_OS_DISABLE = 1'b0;
`endif
    // K15 RP L0 fix: 1-beat PIPE valid gap (TXDATA_VALID low) every 16
    // blocks, at a block boundary, for a gap period of exactly 65 beats
    // (16 blocks x 4 + 1 gap).  l0fix27 root cause: the RP GT RX runs a
    // structural clock-compensation cycle of exactly 65 beats (the 128b/130b
    // payload duty at the 250MHz/32-bit PIPE rate) and deletes 1 beat per
    // cycle no matter what the EP transmits (zero refclk ppm difference does
    // NOT suppress it).  The deletion is benign only when it lands on an EP
    // slack gap -- the Xilinx demo EP gaps every 65 beats and its RP never
    // leaves L0 (297 benign deletions observed); our EP's gap grid sat at a
    // different cadence/phase, so the deletion landed mid-stream: mask beat +
    // data-path-ahead-of-framing + descrambler-realignment aliens -> sh=00
    // at block starts -> rxstatus=100 -> exit L0 -> endless Recovery loop.
    // The elastic buffer was exonerated by l0fix27 BUF_TRACE (chronic +2
    // watermark, but never an overflow transition through the fatal window).
    // K15_L0_GAP_PHASE (0..15): blocks of initial offset applied to the gap
    // grid after each SDS, to scan the gap phase against the RP's deletion
    // cycle (period is identical at 65 beats, so the relative phase is
    // stable and one scan covers all block-aligned alignments).
    localparam [4:0] RATE_GAP_BLOCKS = 5'd16;
`ifdef K15_L0_GAP_PHASE
    localparam [4:0] RATE_GAP_PHASE = 5'd`K15_L0_GAP_PHASE;
`else
    localparam [4:0] RATE_GAP_PHASE = 5'd0;
`endif

    reg [2:0] state;
    reg [1:0] word_index;
    reg [1:0] skp_word_index;
    reg [22:0] lfsr_state;
    // XOR reduction of every scrambled Data Block payload bit since the
    // preceding SDS/SKP boundary.  This is the SKP_END Data Parity bit;
    // deriving it from LFSR[22] is only valid for the old no-data training
    // case and fails once logical-idle blocks precede a SKP.
    reg       data_parity;
    reg [9:0] skp_gap_count;
    reg [4:0] rate_gap_cnt;
    reg       gap_run;
    reg       first_skp_pending;
    wire [31:0] scrambler_data_in = ((state == SEND_EDS) &&
                                     (word_index == 2'd3)) ? EDS_TOKEN : 32'd0;
    wire [31:0] scrambled_data;
    wire [22:0] lfsr_next;

    pcie_gen3_scrambler32 u_scrambler (
        .state_in(lfsr_state), .data_in(scrambler_data_in),
        .bypass_byte(4'b0000), .data_out(scrambled_data),
        .state_out(lfsr_next)
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
            first_skp_pending <= 1'b1;
            lfsr_state <= LANE0_SEED;
            data_parity <= 1'b0;
        end else if (!enable) begin
            state <= SEND_SDS;
            word_index <= 2'd0;
            skp_word_index <= 2'd0;
            skp_gap_count <= 10'd0;
            rate_gap_cnt <= 5'd0;
            gap_run <= 1'b0;
            first_skp_pending <= 1'b1;
            // Track the training transmitter while idle.  On the first SDS
            // beat this is already the state after the final TS word.
            lfsr_state <= lfsr_state_in;
            data_parity <= 1'b0;
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
                data_parity <= 1'b0;
            end else begin
                skp_word_index <= skp_word_index + 1'b1;
            end
        end else if (word_index == 2'd3) begin
            word_index <= 2'd0;
            if (state == SEND_IDLE)
                data_parity <= data_parity ^ (^scrambled_data);
            if (state == SEND_SDS) begin
                state <= SEND_IDLE;
                data_parity <= 1'b0;
                // Phase knob: offset the gap grid after each SDS.  With
                // PHASE=0 the first gap fires after 16 blocks (65-beat
                // period); PHASE=k shifts the whole grid k blocks earlier.
                rate_gap_cnt <= RATE_GAP_PHASE;
            end else if (state == SEND_EDS) begin
                // A SKP Ordered Set may interrupt a Data Stream only when
                // the preceding Data Block ends in an EDS token.  Resume
                // directly with a Data Block after SKP; a second SDS is not
                // used for this in-stream insertion.
                state <= SEND_SKP;
                skp_word_index <= 2'd0;
                rate_gap_cnt <= rate_gap_cnt + 1'b1;
                data_parity <= data_parity ^ (^scrambled_data);
            end else if (!GAP_OS_DISABLE &&
                         rate_gap_cnt >= RATE_GAP_BLOCKS - 5'd1) begin
                rate_gap_cnt <= 5'd0;
                state <= SEND_GAP;
            end else if (!SKP_OS_DISABLE &&
                         skp_gap_count == (first_skp_pending ? FIRST_SKP_GAP :
                                          (gap_run ? SKP_GAP_B : SKP_GAP_A))) begin
                skp_gap_count <= 10'd0;
                gap_run <= ~gap_run;
                first_skp_pending <= 1'b0;
                state <= SEND_EDS;
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
            if ((state == SEND_IDLE) || (state == SEND_EDS))
                data_parity <= data_parity ^ (^scrambled_data);
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
                                     data_parity, lfsr_state[22:16],
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
            out_data = scrambled_data;
        end
    end
endmodule

`default_nettype wire
