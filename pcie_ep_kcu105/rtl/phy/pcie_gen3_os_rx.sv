`timescale 1ns/1ps
`default_nettype none

// Gen3 32-bit PIPE ordered-set receiver. EIEOS and SDS are clear control
// blocks. EIEOS initializes the lane scrambler; SDS only starts a data stream
// and still advances the LFSR. TS symbols 1..15 are descrambled while the
// 1E/2D identifier remains clear.
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
    output reg  [7:0]  link_number,
    output reg         link_is_pad,
    output reg  [7:0]  lane_number,
    output reg         lane_is_pad,
    output reg  [7:0]  n_fts,
    output reg  [7:0]  rate_id,
    output reg  [7:0]  training_control,
    output reg  [7:0]  eq_control,
    output reg  [23:0] eq_data
);
    localparam [7:0] K_PAD = 8'hf7;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;
    localparam [7:0] OS_TS1 = 8'h1e;
    localparam [7:0] OS_TS2 = 8'h2d;
    localparam [1:0] SH_ORDERED_SET = 2'b01;
    localparam [2:0] BLOCK_NONE  = 3'd0;
    localparam [2:0] BLOCK_EIEOS = 3'd1;
    localparam [2:0] BLOCK_SDS   = 3'd2;
    localparam [2:0] BLOCK_TS1   = 3'd3;
    localparam [2:0] BLOCK_TS2   = 3'd4;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;

    reg [2:0] block_kind;
    reg [1:0] word_index;
    reg parse_error;
    reg lfsr_ready;
    reg [22:0] lfsr_state;
    wire [31:0] descrambled_data;
    wire [22:0] lfsr_next;
    wire ts_start = start_block &&
                    ((in_data[7:0] == OS_TS1) ||
                     (in_data[7:0] == OS_TS2));

    pcie_gen3_scrambler32 u_descrambler (
        .state_in(lfsr_state), .data_in(in_data),
        .bypass_byte((word_index == 2'd0) ? 4'b0001 : 4'b0000),
        .data_out(descrambled_data), .state_out(lfsr_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_kind <= BLOCK_NONE;
            word_index <= 2'd0;
            parse_error <= 1'b0;
            lfsr_ready <= 1'b0;
            lfsr_state <= LANE0_SEED;
            ts1_valid <= 1'b0;
            ts2_valid <= 1'b0;
            malformed <= 1'b0;
            link_number <= K_PAD;
            link_is_pad <= 1'b1;
            lane_number <= K_PAD;
            lane_is_pad <= 1'b1;
            n_fts <= 8'd0;
            rate_id <= 8'd0;
            training_control <= 8'd0;
            eq_control <= 8'd0;
            eq_data <= 24'd0;
        end else begin
            ts1_valid <= 1'b0;
            ts2_valid <= 1'b0;
            malformed <= 1'b0;

            if (!enable) begin
                block_kind <= BLOCK_NONE;
                word_index <= 2'd0;
                parse_error <= 1'b0;
                lfsr_ready <= 1'b0;
                lfsr_state <= LANE0_SEED;
            end else if (!in_valid) begin
                if (block_kind != BLOCK_NONE) begin
                    malformed <= 1'b1;
                    block_kind <= BLOCK_NONE;
                    word_index <= 2'd0;
                end
            end else if (start_block) begin
                word_index <= 2'd1;
                parse_error <= (sync_header != SH_ORDERED_SET);
                if (in_data == 32'hff00_ff00) begin
                    block_kind <= BLOCK_EIEOS;
                end else if (in_data == 32'haaaa_aaaa) begin
                    block_kind <= BLOCK_SDS;
                    lfsr_state <= lfsr_next;
                end else if (ts_start && lfsr_ready) begin
                    block_kind <= (in_data[7:0] == OS_TS1) ? BLOCK_TS1 :
                                                                   BLOCK_TS2;
                    link_number <= descrambled_data[15:8];
                    link_is_pad <= descrambled_data[15:8] == K_PAD;
                    lane_number <= descrambled_data[23:16];
                    lane_is_pad <= descrambled_data[23:16] == K_PAD;
                    n_fts <= descrambled_data[31:24];
                    lfsr_state <= lfsr_next;
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
                            end
                            block_kind <= BLOCK_NONE;
                            word_index <= 2'd0;
                        end else word_index <= word_index + 1'b1;
                    end
                    BLOCK_SDS: begin
                        lfsr_state <= lfsr_next;
                        if (((word_index != 2'd3) &&
                             (in_data != 32'haaaa_aaaa)) ||
                            ((word_index == 2'd3) &&
                             (in_data != 32'hbcbf_9de1)))
                            parse_error <= 1'b1;
                        if (word_index == 2'd3) begin
                            if (parse_error || (in_data != 32'hbcbf_9de1)) begin
                                malformed <= 1'b1;
                                lfsr_ready <= 1'b0;
                            end
                            block_kind <= BLOCK_NONE;
                            word_index <= 2'd0;
                        end else word_index <= word_index + 1'b1;
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
