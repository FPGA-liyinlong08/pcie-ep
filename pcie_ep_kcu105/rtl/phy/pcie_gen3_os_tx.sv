`timescale 1ns/1ps
`default_nettype none

// Gen3 32-bit PIPE ordered-set transmitter. On the first Gen3 enable, EIEOS
// and one SKP establish block alignment/LFSR state before TS1/TS2. Later
// periodic EIEOS insertion does not emit another SKP. An independent SKP
// scheduler bounds the interval to at most 350 training blocks. SDS is for
// the Ordered-Set-to-Data-Stream transition in Recovery.Idle.
// Symbols 1..15 of each TS are scrambled while the 1E/2D block identifier
// remains clear; the LFSR still advances over it and is re-seeded after EIEOS.
// Symbols 14/15 implement the 128b/130b TS running-DC-balance substitutions.
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
    localparam [1:0] SEND_EIEOS = 2'd0;
    localparam [1:0] SEND_SKP   = 2'd1;
    localparam [1:0] SEND_TS    = 2'd2;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;

    reg [1:0] word_index;
    reg [1:0] active_mode;
    reg [1:0] stream_state;
    reg       skp_after_eieos;
    reg [5:0] ts_interval_count;
    reg [8:0] skp_interval_count;
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
                         (stream_state == SEND_TS) &&
                         (word_index == 2'd3);
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
            skp_after_eieos <= 1'b1;
            ts_interval_count <= 6'd0;
            skp_interval_count <= 9'd0;
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
            skp_after_eieos <= 1'b1;
            ts_interval_count <= 6'd0;
            skp_interval_count <= 9'd0;
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
                        skp_after_eieos <= 1'b1;
                        skp_interval_count <= 9'd0;
                    end else begin
                        active_mode <= mode;
                        if (skp_after_eieos ||
                            (skp_interval_count >= 9'd349)) begin
                            stream_state <= SEND_SKP;
                        end else begin
                            stream_state <= SEND_TS;
                            skp_interval_count <= skp_interval_count + 1'b1;
                        end
                        skp_after_eieos <= 1'b0;
                    end
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end else if (stream_state == SEND_SKP) begin
                // SKP bypasses scrambling and does not advance the LFSR.
                if (word_index == 2'd3) begin
                    word_index <= 2'd0;
                    skp_interval_count <= 9'd0;
                    if (mode == 2'd0) begin
                        active_mode <= 2'd0;
                        stream_state <= SEND_EIEOS;
                        skp_after_eieos <= 1'b1;
                    end else begin
                        active_mode <= mode;
                        stream_state <= SEND_TS;
                    end
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end else if (word_index == 2'd3) begin
                word_index <= 2'd0;
                lfsr_state <= lfsr_next;
                if (mode == 2'd0) begin
                    active_mode <= 2'd0;
                    stream_state <= SEND_EIEOS;
                    skp_after_eieos <= 1'b1;
                    ts_interval_count <= 6'd0;
                    skp_interval_count <= 9'd0;
                end else if (skp_interval_count >= 9'd349) begin
                    active_mode <= mode;
                    stream_state <= SEND_SKP;
                    skp_interval_count <= 9'd0;
                end else if (ts_interval_count == 6'd31) begin
                    active_mode <= mode;
                    stream_state <= SEND_EIEOS;
                    skp_after_eieos <= 1'b0;
                    ts_interval_count <= 6'd0;
                    skp_interval_count <= skp_interval_count + 1'b1;
                end else begin
                    active_mode <= mode;
                    ts_interval_count <= ts_interval_count + 1'b1;
                    skp_interval_count <= skp_interval_count + 1'b1;
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
        // The PIPE sync header identifies the 128b block, not each 32-bit
        // beat.  XDMA's Gen3 golden path drives 01 only on the first dword
        // (the same beat as TXSTART_BLOCK) and drives 00 for the remaining
        // three dwords.  Repeating 01 on every beat prevents the partner PCS
        // from acquiring the 128b/130b block boundary and leaves its
        // RXDATA_VALID low during Recovery.Equalization.
`ifdef K15_AB_HEADER_HELD
        sync_header = out_valid ? SH_ORDERED_SET : 2'b00;
`else
        sync_header = out_valid && (active_index == 2'd0) ?
                      SH_ORDERED_SET : 2'b00;
`endif
        balanced_data = scrambled_data;
        output_ones = 7'd0;
        if (stream_state == SEND_EIEOS) begin
            out_data = 32'hff00_ff00;
        end else if (stream_state == SEND_SKP) begin
            out_data = (active_index == 2'd3) ? 32'hbcbf_9de1 :
                                                32'haaaa_aaaa;
        end else begin
            case (active_index)
                2'd0: plain_data = {
                    n_fts,
                    lane_is_pad ? K_PAD : lane_number,
                    link_is_pad ? K_PAD : link_number,
                    os_identifier
                };
                // Symbols 6..9 carry the role/phase-specific EQ tuple.  The
                // upstream Endpoint response differs from the downstream
                // Root Port request, so these fields must not be constants.
                2'd1: plain_data = {eq_data[7:0], eq_control,
                                    training_control, rate_id};
                2'd2: plain_data = {identifier, identifier,
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
`ifdef K15_AB_XILINX_PATTERN
        // Diagnostic only: reproduce the passing Xilinx standalone example
        // after its initial EIEOS.  This is not a PCIe training sequence.
        sync_header = out_valid ? SH_ORDERED_SET : 2'b00;
        if (stream_state != SEND_EIEOS)
            out_data = 32'hbeef_cafe;
`endif
    end
endmodule

`default_nettype wire
