`timescale 1ns/1ps
`default_nettype none

// Gen3 32-bit PIPE ordered-set receiver. EIEOS, SKP and SDS are clear control
// blocks. EIEOS initializes the lane scrambler, SKP does not advance it, and
// SDS advances it while arming the following Data Stream. TS symbols 1..15
// are descrambled while the 1E/2D identifier remains clear.
module pcie_gen3_os_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        in_valid,
    input  wire        start_block,
    input  wire [1:0]  sync_header,
    input  wire [31:0] in_data,
    output reg         ts1_valid,
    output reg         ts2_valid,
    output reg         malformed,
    // A valid zero Data Stream block is the minimal Gen3 logical-idle
    // indication used at Recovery.Idle -> L0.  Ordered-Set parsing remains
    // independent from this semantic stream boundary.
    output reg         idle_valid,
    output reg  [7:0]  link_number,
    output reg         link_is_pad,
    output reg  [7:0]  lane_number,
    output reg         lane_is_pad,
    output reg  [7:0]  n_fts,
    output reg  [7:0]  rate_id,
    output reg  [7:0]  training_control,
    output reg  [7:0]  eq_control,
    output reg  [23:0] eq_data,
    // Observation-only pulse at the first beat of a decoded EIEOS block.
    output reg         eieos_start
);
    localparam [7:0] K_PAD = 8'hf7;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;
    localparam [7:0] OS_TS1 = 8'h1e;
    localparam [7:0] OS_TS2 = 8'h2d;
    localparam [31:0] EDS_TOKEN = 32'h0090_801f;
    localparam [1:0] SH_ORDERED_SET = 2'b01;
    localparam [2:0] BLOCK_NONE  = 3'd0;
    localparam [2:0] BLOCK_EIEOS = 3'd1;
    localparam [2:0] BLOCK_SKP   = 3'd2;
    localparam [2:0] BLOCK_TS1   = 3'd3;
    localparam [2:0] BLOCK_TS2   = 3'd4;
    localparam [2:0] BLOCK_IDLE  = 3'd5;
    localparam [2:0] BLOCK_SDS   = 3'd6;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;

    reg [2:0] block_kind;
    reg [1:0] word_index;
    reg parse_error;
    reg lfsr_ready;
    reg data_stream_armed;
    reg [22:0] lfsr_state;
    reg data_parity;
    wire [31:0] descrambled_data;
    wire [22:0] lfsr_next;
    wire [31:0] expected_skp_end = {
        lfsr_state[7:0], lfsr_state[15:8],
        data_stream_armed ? data_parity : ~lfsr_state[22],
        lfsr_state[22:16], 8'he1
    };
    wire ts_start = start_block &&
                    ((in_data[7:0] == OS_TS1) ||
                     (in_data[7:0] == OS_TS2));
    wire [3:0] descramble_bypass = ts_start ? 4'b0001 : 4'b0000;

    pcie_gen3_scrambler32 u_descrambler (
        .state_in(lfsr_state), .data_in(in_data),
        .bypass_byte(descramble_bypass),
        .data_out(descrambled_data), .state_out(lfsr_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_kind <= BLOCK_NONE;
            word_index <= 2'd0;
            parse_error <= 1'b0;
            lfsr_ready <= 1'b0;
            data_stream_armed <= 1'b0;
            lfsr_state <= LANE0_SEED;
            data_parity <= 1'b0;
            ts1_valid <= 1'b0;
            ts2_valid <= 1'b0;
            malformed <= 1'b0;
            idle_valid <= 1'b0;
            link_number <= K_PAD;
            link_is_pad <= 1'b1;
            lane_number <= K_PAD;
            lane_is_pad <= 1'b1;
            n_fts <= 8'd0;
            rate_id <= 8'd0;
            training_control <= 8'd0;
            eq_control <= 8'd0;
            eq_data <= 24'd0;
            eieos_start <= 1'b0;
        end else begin
            ts1_valid <= 1'b0;
            ts2_valid <= 1'b0;
            malformed <= 1'b0;
            idle_valid <= 1'b0;
            eieos_start <= 1'b0;

            if (!enable) begin
                block_kind <= BLOCK_NONE;
                word_index <= 2'd0;
                parse_error <= 1'b0;
                lfsr_ready <= 1'b0;
                data_stream_armed <= 1'b0;
                lfsr_state <= LANE0_SEED;
                data_parity <= 1'b0;
            end else if (!in_valid) begin
                // RxDataValid is a per-cycle use/ignore qualifier.  A bubble
                // inside a 128-bit block does not terminate or corrupt it.
            end else if (start_block) begin
                word_index <= 2'd1;
                parse_error <= (sync_header != SH_ORDERED_SET);
                if (in_data == 32'hff00_ff00) begin
                    block_kind <= BLOCK_EIEOS;
                    data_stream_armed <= 1'b0;
                    eieos_start <= 1'b1;
                end else if (in_data == 32'haaaa_aaaa) begin
                    block_kind <= BLOCK_SKP;
                    // An in-stream SKP is preceded by an EDS token, but does
                    // not end the Data Stream; keep data_stream_armed so the
                    // following Data Block resumes without another SDS.
                end else if ((in_data == 32'h5555_55e1) && lfsr_ready) begin
                    block_kind <= BLOCK_SDS;
                    data_stream_armed <= 1'b0;
                    // SDS bypasses descrambling but advances the LFSR.
                    lfsr_state <= lfsr_next;
                end else if (ts_start && lfsr_ready) begin
                    block_kind <= (in_data[7:0] == OS_TS1) ? BLOCK_TS1 :
                                                                   BLOCK_TS2;
                    data_stream_armed <= 1'b0;
                    link_number <= descrambled_data[15:8];
                    link_is_pad <= descrambled_data[15:8] == K_PAD;
                    lane_number <= descrambled_data[23:16];
                    lane_is_pad <= descrambled_data[23:16] == K_PAD;
                    n_fts <= descrambled_data[31:24];
                    lfsr_state <= lfsr_next;
                end else if ((sync_header == 2'b10) && lfsr_ready &&
                             data_stream_armed) begin
                    block_kind <= BLOCK_IDLE;
                    parse_error <= (descrambled_data != 32'd0);
                    lfsr_state <= lfsr_next;
                    data_parity <= data_parity ^ (^in_data);
                end else begin
                    block_kind <= BLOCK_NONE;
                    malformed <= 1'b1;
                end
            end else begin
                case (block_kind)
                    BLOCK_EIEOS: begin
                        if (in_data != 32'hff00_ff00)
                            parse_error <= 1'b1;
                        if (word_index == 2'd3) begin
                            if (parse_error || (in_data != 32'hff00_ff00)) begin
                                malformed <= 1'b1;
                                lfsr_ready <= 1'b0;
                            end else begin
                                lfsr_state <= LANE0_SEED;
                                lfsr_ready <= 1'b1;
                                data_parity <= 1'b0;
                            end
                            block_kind <= BLOCK_NONE;
                            word_index <= 2'd0;
                        end else word_index <= word_index + 1'b1;
                    end
                    BLOCK_SKP: begin
                        if (((word_index != 2'd3) &&
                             (in_data != 32'haaaa_aaaa)) ||
                            ((word_index == 2'd3) &&
                             (in_data != expected_skp_end)))
                            parse_error <= 1'b1;
                        if (word_index == 2'd3) begin
                            if (parse_error || (in_data != expected_skp_end)) begin
                                malformed <= 1'b1;
                                lfsr_ready <= 1'b0;
                            end
                            block_kind <= BLOCK_NONE;
                            word_index <= 2'd0;
                            data_parity <= 1'b0;
                        end else word_index <= word_index + 1'b1;
                    end
                    BLOCK_SDS: begin
                        lfsr_state <= lfsr_next;
                        if (in_data != 32'h5555_5555)
                            parse_error <= 1'b1;
                        if (word_index == 2'd3) begin
                            block_kind <= BLOCK_NONE;
                            word_index <= 2'd0;
                            if (parse_error || (in_data != 32'h5555_5555)) begin
                                malformed <= 1'b1;
                                lfsr_ready <= 1'b0;
                                data_stream_armed <= 1'b0;
                            end else begin
                                data_stream_armed <= 1'b1;
                                data_parity <= 1'b0;
                            end
                        end else begin
                            word_index <= word_index + 1'b1;
                        end
                    end
                    BLOCK_TS1, BLOCK_TS2: begin
                        lfsr_state <= lfsr_next;
                        case (word_index)
                            2'd1: begin
                                rate_id <= descrambled_data[7:0];
                                training_control <= descrambled_data[15:8];
                                eq_control <= descrambled_data[23:16];
                                eq_data[7:0] <= descrambled_data[31:24];
                                word_index <= 2'd2;
                            end
                            2'd2: begin
                                eq_data[23:8] <= descrambled_data[15:0];
                                if (((block_kind == BLOCK_TS1) &&
                                     (descrambled_data[31:16] != {D_TS1, D_TS1})) ||
                                    ((block_kind == BLOCK_TS2) &&
                                     (descrambled_data[31:16] != {D_TS2, D_TS2})))
                                    parse_error <= 1'b1;
                                word_index <= 2'd3;
                            end
                            default: begin
                                block_kind <= BLOCK_NONE;
                                word_index <= 2'd0;
                                // Gen3 TS1/TS2 symbols 13..15 carry the
                                // equalization control/data fields.  A
                                // partner is therefore allowed to replace
                                // the upper byte of the final 32-bit word;
                                // the two trailing identifier symbols remain
                                // the ordered-set discriminator.  Requiring
                                // all four bytes to be 4A/45 rejected the
                                // Xilinx Root Port's legal EQ encoding and
                                // converted every Recovery TS into
                                // malformed.
                                if (parse_error ||
                                    ((block_kind == BLOCK_TS1) &&
                                     (descrambled_data[15:0] != 16'h4a4a)) ||
                                    ((block_kind == BLOCK_TS2) &&
                                     (descrambled_data[15:0] != 16'h4545)))
                                    malformed <= 1'b1;
                                else if (block_kind == BLOCK_TS1)
                                    ts1_valid <= 1'b1;
                                else
                                    ts2_valid <= 1'b1;
                            end
                        endcase
                    end
                    BLOCK_IDLE: begin
                        lfsr_state <= lfsr_next;
                        data_parity <= data_parity ^ (^in_data);
                        if ((word_index != 2'd3) &&
                            (descrambled_data != 32'd0))
                            parse_error <= 1'b1;
                        if (word_index == 2'd3) begin
                            block_kind <= BLOCK_NONE;
                            word_index <= 2'd0;
                            // A valid idle data block may end either in IDL
                            // or in the four-Symbol EDS token that frames an
                            // immediately following SKP Ordered Set.
                            if (parse_error ||
                                ((descrambled_data != 32'd0) &&
                                 (descrambled_data != EDS_TOKEN)))
                                malformed <= 1'b1;
                            else if (descrambled_data == 32'd0)
                                idle_valid <= 1'b1;
                        end else begin
                            word_index <= word_index + 1'b1;
                        end
                    end
                    default: begin
                        malformed <= 1'b1;
                        word_index <= 2'd0;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
