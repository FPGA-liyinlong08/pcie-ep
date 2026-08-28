`timescale 1ns/1ps
`default_nettype none

// Gen3 32-bit PIPE ordered-set transmitter. On the first Gen3 enable, EIEOS
// and one SKP establish block alignment/LFSR state before TS1/TS2.  Later
// periodic EIEOS insertion does not emit another SKP.  SDS is reserved for
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
    reg [1:0] previous_mode;
    reg [1:0] stream_state;
    reg       skp_after_eieos;
    reg [5:0] ts_interval_count;
    reg [22:0] lfsr_state;
    reg signed [10:0] dc_balance;
    wire [1:0] active_index = (mode != previous_mode) ? 2'd0 : word_index;
    wire [7:0] identifier = (mode == 2'd1) ? D_TS1 : D_TS2;
    wire [7:0] os_identifier = (mode == 2'd1) ? OS_TS1 : OS_TS2;
    reg [31:0] plain_data;
    wire [31:0] scrambled_data;
    wire [22:0] lfsr_next;
    reg [31:0] balanced_data;

    function automatic [2:0] popcount4;
        input [3:0] value;
        begin
            popcount4 = value[0] + value[1] + value[2] + value[3];
        end
    endfunction

    function automatic [4:0] popcount8;
        input [7:0] value;
        begin
            popcount8 = popcount4(value[3:0]) + popcount4(value[7:4]);
        end
    endfunction

    function automatic signed [10:0] update_dc_balance;
        input signed [10:0] current_balance;
        input [31:0] transmitted_data;
        input [3:0] included_bytes;
        reg [6:0] ones;
        reg [6:0] included_bits;
        reg signed [11:0] next_balance;
        begin
            ones = (included_bytes[0] ? popcount8(transmitted_data[7:0]) : 7'd0) +
                   (included_bytes[1] ? popcount8(transmitted_data[15:8]) : 7'd0) +
                   (included_bytes[2] ? popcount8(transmitted_data[23:16]) : 7'd0) +
                   (included_bytes[3] ? popcount8(transmitted_data[31:24]) : 7'd0);
            included_bits = (included_bytes[0] ? 7'd8 : 7'd0) +
                            (included_bytes[1] ? 7'd8 : 7'd0) +
                            (included_bytes[2] ? 7'd8 : 7'd0) +
                            (included_bytes[3] ? 7'd8 : 7'd0);
            next_balance = current_balance + ((ones * 2) - included_bits);
            if (next_balance > 511)
                update_dc_balance = 11'sd511;
            else if (next_balance < -511)
                update_dc_balance = -11'sd511;
            else
                update_dc_balance = next_balance[10:0];
        end
    endfunction

    pcie_gen3_scrambler32 u_scrambler (
        .state_in(lfsr_state), .data_in(plain_data),
        .bypass_byte((active_index == 2'd0) ? 4'b0001 : 4'b0000),
        .data_out(scrambled_data), .state_out(lfsr_next)
    );

    assign os_complete = enable && (mode != 2'd0) &&
                         (stream_state == SEND_TS) &&
                         (mode == previous_mode) && (word_index == 2'd3);
    assign word_index_debug = active_index;
    assign lfsr_state_after_word =
        (enable && (mode != 2'd0) && (stream_state == SEND_TS)) ?
            lfsr_next : lfsr_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_index <= 2'd0;
            previous_mode <= 2'd0;
            stream_state <= SEND_EIEOS;
            skp_after_eieos <= 1'b1;
            ts_interval_count <= 6'd0;
            lfsr_state <= LANE0_SEED;
            dc_balance <= 11'sd0;
        end else if (!enable || (mode == 2'd0)) begin
            word_index <= 2'd0;
            previous_mode <= mode;
            stream_state <= SEND_EIEOS;
            skp_after_eieos <= 1'b1;
            ts_interval_count <= 6'd0;
            lfsr_state <= LANE0_SEED;
            // Electrical-idle exit resets the TS running DC balance.
            dc_balance <= 11'sd0;
        end else begin
            if (stream_state == SEND_EIEOS) begin
                previous_mode <= mode;
                if (word_index == 2'd3) begin
                    word_index <= 2'd0;
                    stream_state <= skp_after_eieos ? SEND_SKP : SEND_TS;
                    skp_after_eieos <= 1'b0;
                    ts_interval_count <= 6'd0;
                    // EIEOS advances the LFSR but re-initializes it after Symbol 15.
                    lfsr_state <= LANE0_SEED;
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end else if (stream_state == SEND_SKP) begin
                previous_mode <= mode;
                // The passing XDMA demo emits the lane-0 SKP body
                // AA...AA/E1/9D/BF/BC and starts the first TS from the lane seed.
                lfsr_state <= LANE0_SEED;
                if (word_index == 2'd3) begin
                    word_index <= 2'd0;
                    stream_state <= SEND_TS;
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end else if (mode != previous_mode) begin
                previous_mode <= mode;
                word_index <= 2'd1;
                lfsr_state <= lfsr_next;
            end else if (word_index == 2'd3) begin
                word_index <= 2'd0;
                lfsr_state <= lfsr_next;
                if (ts_interval_count == 6'd31) begin
                    stream_state <= SEND_EIEOS;
                    skp_after_eieos <= 1'b0;
                    ts_interval_count <= 6'd0;
                end else begin
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
        out_valid = enable && (mode != 2'd0);
        start_block = out_valid && (active_index == 2'd0);
        // AMD PHY32 requires the block type to remain valid on every 32-bit
        // beat; TXSTART_BLOCK alone identifies the first beat.
        sync_header = out_valid ? SH_ORDERED_SET : 2'b00;
        balanced_data = scrambled_data;
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
            balanced_data = scrambled_data;
            if (active_index == 2'd3) begin
                if ($signed(dc_balance) > 11'sd31)
                    balanced_data[31:16] = 16'h0820;
                else if ($signed(dc_balance) < -11'sd31)
                    balanced_data[31:16] = 16'hf7df;
                else if ($signed(dc_balance) > 11'sd15)
                    balanced_data[31:24] = 8'h08;
                else if ($signed(dc_balance) < -11'sd15)
                    balanced_data[31:24] = 8'hf7;
            end
            out_data = balanced_data;
        end
    end
endmodule

`default_nettype wire
