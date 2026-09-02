`timescale 1ns/1ps
`default_nettype none

// Gen3 32-bit PIPE ordered-set transmitter. On enable the stream reproduces
// the official pat_gen cadence: EIEOS, then TS1/TS2 blocks separated by
// 1-beat PIPE valid gaps (TXDATA_VALID low) at block boundaries -- 15 blocks,
// gap, 16 blocks, gap, back to EIEOS (130-beat period). The GT secureip
// substitutes real SKP ordered sets during every valid-gap beat; a stream
// that never deasserts TXDATA_VALID produces no wire SKPs and the partner
// GTHE3 never block-locks (K15 Gen3 acquisition root cause, 2026-08-31
// isolation experiment).
// The GT only substitutes SKPs at its own buffer-drift rate, however, and
// the SVT VIP's max_rx_skp_interval check (and PG239's "the MAC must
// transmit SKP Ordered Sets as 16 symbols") require the MAC to emit
// explicit Gen3 SKP OS content: once every 8 cadence periods the 8th block
// of the 16-block run is replaced by a 16-symbol SKP OS (13x 1Ch + SKP_END
// carrying Data Parity and the LFSR value). The LFSR is frozen across the
// SKP block exactly like the valid gap.
// SDS is for the Ordered-Set-to-Data-Stream transition in Recovery.Idle.
// Symbols 1..15 of each TS are scrambled while the 1E/2D block identifier
// remains clear; the LFSR still advances over it and is re-seeded after EIEOS
// and frozen across valid gaps. Symbols 14/15 implement the 128b/130b TS
// running-DC-balance substitutions.
module pcie_gen3_os_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [1:0]  mode,
    input  wire [7:0]  link_number,
    input  wire        link_is_pad,
    input  wire [7:0]  lane_number,
    input  wire        lane_is_pad,
    input  wire [7:0]  n_fts,
    input  wire [7:0]  rate_id,
    input  wire [7:0]  training_control,
    input  wire [7:0]  eq_control,
    input  wire [23:0] eq_data,
    output reg  [31:0] out_data,
    output reg         out_valid,
    output reg         start_block,
    output reg  [1:0]  sync_header,
    output wire        os_complete,
    output wire [1:0]  word_index_debug,
    output wire        eieos_active,
    output wire        eieos_start,
    // State after the currently presented 32-bit word.  Recovery.Idle uses
    // this hand-off so SDS and the first Data Block continue the same lane
    // scrambler stream instead of silently restarting from the lane seed.
    output wire [22:0] lfsr_state_after_word
);
    localparam [7:0] K_PAD = 8'hf7;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;
    localparam [7:0] OS_TS1 = 8'h1e;
    localparam [7:0] OS_TS2 = 8'h2d;
    localparam [1:0] SH_ORDERED_SET = 2'b01;
    // 128b/130b SKP symbol.  8'h1c is the 8b/10b SKP code (Gen1/2 macros
    // GEN12_SKP*_TX_DATA); Gen3 ordered sets use 8'haa -- confirmed by the
    // Xilinx hard-IP EP golden capture (aaaaaaaa x3 + bcbf9de1) and the
    // ExpressRich constants I_SKP_8G=16'haaaa / T_SKP_END=8'he1.
    localparam [7:0] SKP_SYM = 8'haa;
    localparam [1:0] SEND_EIEOS = 2'd0;
    localparam [1:0] SEND_SKP   = 2'd1;
    localparam [1:0] SEND_TS    = 2'd2;
    localparam [1:0] SEND_GAP   = 2'd3;
    // One explicit SKP OS every 8 cadence periods (~260 blocks, well under
    // the VIP's 375-block max_rx_skp_interval).
    localparam [2:0] SKP_PERIOD = 3'd7;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;

    reg [1:0] word_index;
    reg [1:0] active_mode;
    reg [1:0] stream_state;
    // Selects which TS run length the current period is in (15 blocks before
    // the first gap, 16 before the second), and signals the second gap to
    // return to EIEOS.
    reg       gap_run;
    reg [5:0] ts_interval_count;
    reg [2:0] skp_period_count;
    reg [1:0] skp_word_index;
    reg [22:0] lfsr_state;
    reg signed [10:0] dc_balance;
    reg [6:0] dc_ones_q;
    reg [6:0] dc_included_bits_q;
    reg       dc_count_valid_q;
    // The request is accepted only after word 3 of the active TS block.
    wire [1:0] output_mode = (active_mode == 2'd0) ? mode : active_mode;
    wire [1:0] active_index = word_index;
    wire [7:0] identifier = (output_mode == 2'd1) ? D_TS1 : D_TS2;
    wire [7:0] os_identifier = (output_mode == 2'd1) ? OS_TS1 : OS_TS2;
    reg [31:0] plain_data;
    wire [31:0] scrambled_data;
    wire [22:0] lfsr_next;
    reg [31:0] balanced_data;
    reg [6:0] output_ones;

    function automatic [2:0] popcount4;
        input [3:0] value;
        begin
            popcount4 = {2'b0, value[0]} + {2'b0, value[1]} +
                        {2'b0, value[2]} + {2'b0, value[3]};
        end
    endfunction

    function automatic [4:0] popcount8;
        input [7:0] value;
        begin
            popcount8 = {2'b0, popcount4(value[3:0])} +
                        {2'b0, popcount4(value[7:4])};
        end
    endfunction

    function automatic [6:0] count_ones32;
        input [31:0] value;
        begin
            count_ones32 = {2'b0, popcount8(value[7:0])} +
                           {2'b0, popcount8(value[15:8])} +
                           {2'b0, popcount8(value[23:16])} +
                           {2'b0, popcount8(value[31:24])};
        end
    endfunction

    function automatic signed [10:0] update_dc_balance_counts;
        input signed [10:0] current_balance;
        input [6:0] ones;
        input [6:0] included_bits;
        reg signed [11:0] next_balance;
        begin
            next_balance = $signed({current_balance[10], current_balance}) +
                           $signed({4'b0, ones, 1'b0}) -
                           $signed({5'b0, included_bits});
            if (next_balance > 511)
                update_dc_balance_counts = 11'sd511;
            else if (next_balance < -511)
                update_dc_balance_counts = -11'sd511;
            else
                update_dc_balance_counts = next_balance[10:0];
        end
    endfunction

    pcie_gen3_scrambler32 u_scrambler (
        .state_in(lfsr_state), .data_in(plain_data),
        .bypass_byte((active_index == 2'd0) ? 4'b0001 : 4'b0000),
        .data_out(scrambled_data), .state_out(lfsr_next)
    );

    assign os_complete = enable && (output_mode != 2'd0) &&
                         (((stream_state == SEND_TS) && (word_index == 2'd3)) ||
                          ((stream_state == SEND_SKP) && (skp_word_index == 2'd3)));
    assign eieos_active = out_valid && (stream_state == SEND_EIEOS);
    assign eieos_start = eieos_active && (active_index == 2'd0);
    assign word_index_debug = active_index;
    assign lfsr_state_after_word =
        (enable && (output_mode != 2'd0) && (stream_state == SEND_TS)) ?
            lfsr_next : lfsr_state;

    reg signed [10:0] dc_balance_for_output;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_index <= 2'd0;
            active_mode <= 2'd0;
            stream_state <= SEND_EIEOS;
            ts_interval_count <= 6'd0;
            gap_run <= 1'b0;
            skp_period_count <= 3'd0;
            skp_word_index <= 2'd0;
            lfsr_state <= LANE0_SEED;
            dc_balance <= 11'sd0;
            dc_ones_q <= 7'd0;
            dc_included_bits_q <= 7'd0;
            dc_count_valid_q <= 1'b0;
        end else if (!enable ||
                     ((active_mode == 2'd0) && (mode == 2'd0))) begin
            word_index <= 2'd0;
            active_mode <= 2'd0;
            stream_state <= SEND_EIEOS;
            ts_interval_count <= 6'd0;
            gap_run <= 1'b0;
            skp_period_count <= 3'd0;
            skp_word_index <= 2'd0;
            lfsr_state <= LANE0_SEED;
            dc_balance <= 11'sd0;
            dc_ones_q <= 7'd0;
            dc_included_bits_q <= 7'd0;
            dc_count_valid_q <= 1'b0;
        end else begin
            if ((active_mode == 2'd0) && (mode != 2'd0))
                active_mode <= mode;

            if (dc_count_valid_q)
                dc_balance <= update_dc_balance_counts(
                    dc_balance, dc_ones_q, dc_included_bits_q
                );
            dc_count_valid_q <= 1'b0;
            if (stream_state == SEND_TS) begin
                dc_ones_q <= output_ones;
                dc_included_bits_q <= (active_index == 2'd0) ? 7'd24 : 7'd32;
                dc_count_valid_q <= 1'b1;
            end

            if (stream_state == SEND_EIEOS) begin
                if (word_index == 2'd3) begin
                    word_index <= 2'd0;
                    lfsr_state <= LANE0_SEED;
                    ts_interval_count <= 6'd0;
                    if (mode == 2'd0) begin
                        active_mode <= 2'd0;
                        stream_state <= SEND_EIEOS;
                    end else begin
                        active_mode <= mode;
                        stream_state <= SEND_TS;
                        gap_run <= 1'b0;
                    end
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end else if (stream_state == SEND_GAP) begin
                // One PIPE beat with TXDATA_VALID low (the GT secureip
                // substitutes a real SKP ordered set there), then the TS
                // stream resumes at a block boundary (word_index is already
                // 0, so the resume beat pulses start_block).  After the
                // second gap of the period the stream returns to EIEOS.
                // The LFSR is frozen across the gap.
                gap_run <= ~gap_run;
                stream_state <= gap_run ? SEND_EIEOS : SEND_TS;
                word_index <= 2'd0;
            end else if (stream_state == SEND_SKP) begin
                // Explicit 16-symbol SKP OS: four unscrambled beats, LFSR
                // frozen across the block (same semantics as the gap beat).
                if (skp_word_index == 2'd3) begin
                    skp_word_index <= 2'd0;
                    skp_period_count <= (skp_period_count == SKP_PERIOD) ?
                                        3'd0 : skp_period_count + 1'b1;
                    word_index <= 2'd0;
                    if (mode == 2'd0) begin
                        active_mode <= 2'd0;
                        stream_state <= SEND_EIEOS;
                        ts_interval_count <= 6'd0;
                    end else begin
                        active_mode <= mode;
                        stream_state <= SEND_TS;
                    end
                end else begin
                    skp_word_index <= skp_word_index + 1'b1;
                end
            end else if (word_index == 2'd3) begin
                word_index <= 2'd0;
                lfsr_state <= lfsr_next;
                if (mode == 2'd0) begin
                    active_mode <= 2'd0;
                    stream_state <= SEND_EIEOS;
                    ts_interval_count <= 6'd0;
                end else if (ts_interval_count ==
                             (gap_run ? 6'd15 : 6'd14)) begin
                    // Official cadence: 1-beat PIPE gap between TS block
                    // runs (15 blocks then 16 blocks per EIEOS period), so
                    // every periodic EIEOS is immediately preceded by a gap.
                    active_mode <= mode;
                    stream_state <= SEND_GAP;
                    ts_interval_count <= 6'd0;
                end else if (gap_run && (ts_interval_count == 6'd7) &&
                             (skp_period_count == 3'd0)) begin
                    // Insert an explicit SKP OS after the 8th block of the
                    // 16-block run once every SKP_PERIOD+1 cadence periods
                    // (the period gains one beat, negligible against the
                    // VIP's 375-block budget).  The gap before the periodic
                    // EIEOS stays adjacent.
                    active_mode <= mode;
                    stream_state <= SEND_SKP;
                    skp_word_index <= 2'd0;
                    ts_interval_count <= 6'd8;
                end else begin
                    active_mode <= mode;
                    ts_interval_count <= ts_interval_count + 1'b1;
                end
            end else begin
                word_index <= word_index + 1'b1;
                lfsr_state <= lfsr_next;
            end
        end
    end

    always @* begin
        plain_data = 32'd0;
        out_data = 32'd0;
        out_valid = enable && (output_mode != 2'd0);
        start_block = out_valid && (active_index == 2'd0);
        // The PIPE sync header is sampled by the PHY on the TXSTART_BLOCK
        // beat and does not enter the serial stream on continuation beats
        // (the K15_AB_HEADER_HELD A/B showed no difference and the official
        // golden holds 01 on data beats too).
        sync_header = out_valid && (active_index == 2'd0) ?
                      SH_ORDERED_SET : 2'b00;
        balanced_data = scrambled_data;
        output_ones = 7'd0;
        if (stream_state == SEND_GAP) begin
            // The gap beat holds TXDATA_VALID, TXSTART_BLOCK and
            // TXSYNC_HEADER low, exactly like the official pat_gen's
            // PAT_GEN_GEN3_PAT_Z3/Z4 states.
            out_data = 32'd0;
            out_valid = 1'b0;
            start_block = 1'b0;
            sync_header = 2'b00;
        end else if (stream_state == SEND_SKP) begin
            // 16-symbol SKP OS (sync header 10 at the PIPE mapping used by
            // the official pat_gen): 12 SKP symbols then the SKP_END tail
            // {SKP_END, Data Parity + LFSR[22:16], LFSR[15:8], LFSR[7:0]}.
            // Wire order is bits[7:0] first, so the tail word reads
            // {LFSR[7:0], LFSR[15:8], ~LFSR[22], LFSR[22:16], 8'hE1} --
            // identical to pcie_gen3_os_rx.sv expected_skp_end and to the
            // Xilinx hard-IP golden beat bcbf9de1 for seed 1DBFBC.
            start_block = (skp_word_index == 2'd0);
            sync_header = (skp_word_index == 2'd0) ? SH_ORDERED_SET : 2'b00;
            case (skp_word_index)
                2'd0, 2'd1, 2'd2: out_data = {4{SKP_SYM}};
                default: out_data = {lfsr_state[7:0], lfsr_state[15:8],
                                     ~lfsr_state[22], lfsr_state[22:16],
                                     8'he1};
            endcase
        end else if (stream_state == SEND_EIEOS) begin
            out_data = 32'hff00_ff00;
        end else begin
            case (active_index)
                2'd0: plain_data = {
                    n_fts,
                    lane_is_pad ? K_PAD : lane_number,
                    link_is_pad ? K_PAD : link_number,
                    os_identifier
                };
                // TS1 (Table 4-5): symbols 6..9 carry the role/phase-specific
                // EQ tuple.  The upstream Endpoint response differs from the
                // downstream Root Port request, so these fields must not be
                // constants.  TS2 (Table 4-6) has no EQ tuple at 8.0 GT/s:
                // symbols 6..13 are the 45h identifier (symbol 6 bits 7/6 are
                // the Request Equalization/Quiesce Guarantee flags, both 0b
                // here), so the EQ inputs are bypassed in TS2 mode.
                2'd1: plain_data = (output_mode == 2'd2) ?
                                   {identifier, identifier,
                                    training_control, rate_id} :
                                   {eq_data[7:0], eq_control,
                                    training_control, rate_id};
                2'd2: plain_data = (output_mode == 2'd2) ?
                                   {identifier, identifier,
                                    identifier, identifier} :
                                   {identifier, identifier,
                                    eq_data[23:8]};
                default: begin
                    // Symbols 12/13 carry the repeated post-cursor/parity
                    // field. Symbols 14/15 normally carry identifiers, but
                    // may bypass scrambling with the mandated DC-balance
                    // values based on the balance at the end of Symbol 11.
                    plain_data = {identifier, identifier, identifier, identifier};
                end
            endcase
            // Add the pending preceding-word count for TS word 3. Both
            // operands are registered, so this is a short balance-only path
            // rather than scrambler -> popcount -> balance arithmetic.
            dc_balance_for_output = dc_balance;
            if (dc_count_valid_q)
                dc_balance_for_output = update_dc_balance_counts(
                    dc_balance, dc_ones_q, dc_included_bits_q
                );
            balanced_data = scrambled_data;
            // Symbol 0 is the clear 1E/2D Ordered-Set identifier.  It is
            // excluded from the Gen3 TS running-DC counter; counting its
            // four set bits while declaring only 24 included bits biases the
            // first word by +8 and selects Symbol-15 substitution one TS too
            // early.
            if (active_index == 2'd0)
                output_ones =
                    {2'b0, popcount8(scrambled_data[31:24])} +
                    {2'b0, popcount8(scrambled_data[23:16])} +
                    {2'b0, popcount8(scrambled_data[15:8])};
            else
                output_ones = count_ones32(scrambled_data);
            if (active_index == 2'd3) begin
                if ($signed(dc_balance_for_output) > 11'sd31) begin
                    balanced_data[31:16] = 16'h0820;
                    output_ones = {2'b0, popcount8(scrambled_data[15:8])} +
                                  {2'b0, popcount8(scrambled_data[7:0])} + 7'd2;
                end else if ($signed(dc_balance_for_output) < -11'sd31) begin
                    balanced_data[31:16] = 16'hf7df;
                    output_ones = {2'b0, popcount8(scrambled_data[15:8])} +
                                  {2'b0, popcount8(scrambled_data[7:0])} + 7'd15;
                end else if ($signed(dc_balance_for_output) > 11'sd15) begin
                    balanced_data[31:24] = 8'h08;
                    output_ones = {2'b0, popcount8(scrambled_data[23:16])} +
                                  {2'b0, popcount8(scrambled_data[15:8])} +
                                  {2'b0, popcount8(scrambled_data[7:0])} + 7'd1;
                end else if ($signed(dc_balance_for_output) < -11'sd15) begin
                    balanced_data[31:24] = 8'hf7;
                    output_ones = {2'b0, popcount8(scrambled_data[23:16])} +
                                  {2'b0, popcount8(scrambled_data[15:8])} +
                                  {2'b0, popcount8(scrambled_data[7:0])} + 7'd7;
                end
            end
            out_data = balanced_data;
        end
    end
endmodule

`default_nettype wire
