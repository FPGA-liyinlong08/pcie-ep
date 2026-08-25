`timescale 1ns/1ps
`default_nettype none

// Gen3 32-bit PIPE ordered-set transmitter. Recovery training starts with an
// EIEOS and then sends TS continuously. An EIEOS is inserted after every 32
// TS blocks; SDS belongs to the later Data Stream transition and must not be
// injected into Recovery.RcvrLock training traffic.
// Symbols 1..15 of each TS are scrambled while the 1E/2D block identifier
// remains clear; the LFSR still advances over it and is re-seeded after EIEOS.
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
    output wire [1:0]  word_index_debug
);
    localparam [7:0] K_PAD = 8'hf7;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;
    localparam [7:0] OS_TS1 = 8'h1e;
    localparam [7:0] OS_TS2 = 8'h2d;
    localparam [1:0] SH_ORDERED_SET = 2'b01;
    localparam [1:0] SEND_EIEOS = 2'd0;
    localparam [1:0] SEND_TS    = 2'd1;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;

    reg [1:0] word_index;
    reg [1:0] previous_mode;
    reg [1:0] stream_state;
    reg [5:0] ts_interval_count;
    reg [22:0] lfsr_state;
    wire [1:0] active_index = (mode != previous_mode) ? 2'd0 : word_index;
    wire [7:0] identifier = (mode == 2'd1) ? D_TS1 : D_TS2;
    wire [7:0] os_identifier = (mode == 2'd1) ? OS_TS1 : OS_TS2;
    reg [31:0] plain_data;
    wire [31:0] scrambled_data;
    wire [22:0] lfsr_next;

    pcie_gen3_scrambler32 u_scrambler (
        .state_in(lfsr_state), .data_in(plain_data),
        .bypass_byte((active_index == 2'd0) ? 4'b0001 : 4'b0000),
        .data_out(scrambled_data), .state_out(lfsr_next)
    );

    assign os_complete = enable && (mode != 2'd0) &&
                         (stream_state == SEND_TS) &&
                         (mode == previous_mode) && (word_index == 2'd3);
    assign word_index_debug = active_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_index <= 2'd0;
            previous_mode <= 2'd0;
            stream_state <= SEND_EIEOS;
            ts_interval_count <= 6'd0;
            lfsr_state <= LANE0_SEED;
        end else if (!enable || (mode == 2'd0)) begin
            word_index <= 2'd0;
            previous_mode <= mode;
            stream_state <= SEND_EIEOS;
            ts_interval_count <= 6'd0;
            lfsr_state <= LANE0_SEED;
        end else if (stream_state == SEND_EIEOS) begin
            previous_mode <= mode;
            if (word_index == 2'd3) begin
                word_index <= 2'd0;
                stream_state <= SEND_TS;
                ts_interval_count <= 6'd0;
                // EIEOS is clear and re-initializes the lane scrambler.
                lfsr_state <= LANE0_SEED;
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
                ts_interval_count <= 6'd0;
            end else begin
                ts_interval_count <= ts_interval_count + 1'b1;
            end
        end else begin
            word_index <= word_index + 1'b1;
            lfsr_state <= lfsr_next;
        end
    end

    always @* begin
        plain_data = 32'd0;
        out_data = 32'd0;
        out_valid = enable && (mode != 2'd0);
        start_block = out_valid && (active_index == 2'd0);
        sync_header = start_block ? SH_ORDERED_SET : 2'b00;
        if (stream_state == SEND_EIEOS) begin
            out_data = 32'hff00_ff00;
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
                    // Phase-0 ordered sets use identifiers in the final word.
                    // The receiver accepts the legal EQ-field replacement
                    // used by a partner during later equalization phases.
                    plain_data = {identifier, identifier, identifier, identifier};
                end
            endcase
            out_data = scrambled_data;
        end
    end
endmodule

`default_nettype wire
