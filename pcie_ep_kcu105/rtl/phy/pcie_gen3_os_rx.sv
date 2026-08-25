`timescale 1ns/1ps
`default_nettype none

// Gen3 ordered-set receiver at the 32-bit PIPE boundary.
//
// PG239 defines RxDataValid as a per-cycle "use/ignore" qualifier and
// RxStartBlock as the byte-0 marker for a 128-bit block. The receiver first
// reassembles complete blocks; bubbles therefore do not abort a block and
// words observed before a StartBlock are ignored. Protocol state is not
// allowed to consume TS1/TS2 until an exact EIEOS has established the Gen3
// block/scrambler boundary.
module pcie_gen3_os_rx (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,
    input  wire         in_valid,
    input  wire         start_block,
    input  wire [1:0]   sync_header,
    input  wire [31:0]  in_data,
    output reg          ts1_valid,
    output reg          ts2_valid,
    output reg          malformed,
    output reg          idle_valid,
    output reg          block_locked,
    output reg          lock_acquired,
    output reg          lock_lost,
    output reg          eieos_valid,
    output reg          sds_valid,
    output reg  [7:0]   link_number,
    output reg          link_is_pad,
    output reg  [7:0]   lane_number,
    output reg          lane_is_pad,
    output reg  [7:0]   n_fts,
    output reg  [7:0]   rate_id,
    output reg  [7:0]   training_control,
    output reg  [7:0]   eq_control,
    output reg  [23:0]  eq_data
);
    localparam [7:0] K_PAD = 8'hf7;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;
    localparam [7:0] OS_TS1 = 8'h1e;
    localparam [7:0] OS_TS2 = 8'h2d;
    localparam [7:0] OS_SDS = 8'he1;
    localparam [1:0] SH_ORDERED_SET = 2'b01;
    localparam [1:0] SH_DATA_STREAM = 2'b10;
    localparam [22:0] LANE0_SEED = 23'h1dbfbc;
    localparam [127:0] EIEOS_BLOCK = {
        32'hff00_ff00, 32'hff00_ff00,
        32'hff00_ff00, 32'hff00_ff00
    };

    wire [127:0] block_data;
    wire [1:0] block_sync_header;
    wire block_valid;
    wire boundary_error;

    reg [22:0] lfsr_state;
    reg        lfsr_ready;

    wire [31:0] descrambled_word0;
    wire [31:0] descrambled_word1;
    wire [31:0] descrambled_word2;
    wire [31:0] descrambled_word3;
    wire [22:0] lfsr_after_word0;
    wire [22:0] lfsr_after_word1;
    wire [22:0] lfsr_after_word2;
    wire [22:0] lfsr_after_block;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [127:0] descrambled_block = {
        descrambled_word3, descrambled_word2,
        descrambled_word1, descrambled_word0
    };
    /* verilator lint_on UNUSEDSIGNAL */

    wire ordered_set_block = block_sync_header == SH_ORDERED_SET;
    wire data_stream_block = block_sync_header == SH_DATA_STREAM;
    wire valid_sync_header = ordered_set_block || data_stream_block;
    wire is_eieos = ordered_set_block && (block_data == EIEOS_BLOCK);
    // SDS Symbols 0..11 and its identifier are invariant. Symbols 13..15
    // are deliberately not compared here: captures from an independent
    // Xilinx partner show legal state-dependent values in those bytes.
    wire is_sds = ordered_set_block &&
                  (block_data[95:0] == {12{8'haa}}) &&
                  (block_data[103:96] == OS_SDS);
    wire is_ts1 = ordered_set_block && (block_data[7:0] == OS_TS1);
    wire is_ts2 = ordered_set_block && (block_data[7:0] == OS_TS2);
    wire ts_payload_valid =
        (is_ts1 &&
         (descrambled_block[95:80] == {D_TS1, D_TS1}) &&
         (descrambled_block[111:96] == {D_TS1, D_TS1})) ||
        (is_ts2 &&
         (descrambled_block[95:80] == {D_TS2, D_TS2}) &&
         (descrambled_block[111:96] == {D_TS2, D_TS2}));

    pcie_gen3_block_rx u_block_rx (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .in_valid(in_valid), .start_block(start_block),
        .sync_header(sync_header), .in_data(in_data),
        .block_valid(block_valid), .block_data(block_data),
        .block_sync_header(block_sync_header),
        .boundary_error(boundary_error)
    );

    // The first byte is the clear Ordered-Set Block identifier. It is not
    // XORed, but the LFSR advances over all 128 payload bits.
    pcie_gen3_scrambler32 u_descrambler_word0 (
        .state_in(lfsr_state), .data_in(block_data[31:0]),
        .bypass_byte(4'b0001), .data_out(descrambled_word0),
        .state_out(lfsr_after_word0)
    );
    pcie_gen3_scrambler32 u_descrambler_word1 (
        .state_in(lfsr_after_word0), .data_in(block_data[63:32]),
        .bypass_byte(4'b0000), .data_out(descrambled_word1),
        .state_out(lfsr_after_word1)
    );
    pcie_gen3_scrambler32 u_descrambler_word2 (
        .state_in(lfsr_after_word1), .data_in(block_data[95:64]),
        .bypass_byte(4'b0000), .data_out(descrambled_word2),
        .state_out(lfsr_after_word2)
    );
    pcie_gen3_scrambler32 u_descrambler_word3 (
        .state_in(lfsr_after_word2), .data_in(block_data[127:96]),
        .bypass_byte(4'b0000), .data_out(descrambled_word3),
        .state_out(lfsr_after_block)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts1_valid <= 1'b0;
            ts2_valid <= 1'b0;
            malformed <= 1'b0;
            idle_valid <= 1'b0;
            block_locked <= 1'b0;
            lock_acquired <= 1'b0;
            lock_lost <= 1'b0;
            eieos_valid <= 1'b0;
            sds_valid <= 1'b0;
            lfsr_state <= LANE0_SEED;
            lfsr_ready <= 1'b0;
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
            idle_valid <= 1'b0;
            lock_acquired <= 1'b0;
            lock_lost <= 1'b0;
            eieos_valid <= 1'b0;
            sds_valid <= 1'b0;

            if (!enable) begin
                block_locked <= 1'b0;
                lfsr_ready <= 1'b0;
                lfsr_state <= LANE0_SEED;
            end else if (boundary_error) begin
                malformed <= 1'b1;
                if (block_locked)
                    lock_lost <= 1'b1;
                block_locked <= 1'b0;
                lfsr_ready <= 1'b0;
                lfsr_state <= LANE0_SEED;
            end else if (block_valid) begin
                if (!valid_sync_header) begin
                    malformed <= 1'b1;
                    if (block_locked)
                        lock_lost <= 1'b1;
                    block_locked <= 1'b0;
                    lfsr_ready <= 1'b0;
                    lfsr_state <= LANE0_SEED;
                end else if (is_eieos) begin
                    eieos_valid <= 1'b1;
                    if (!block_locked)
                        lock_acquired <= 1'b1;
                    block_locked <= 1'b1;
                    lfsr_ready <= 1'b1;
                    lfsr_state <= LANE0_SEED;
                end else if (!block_locked || !lfsr_ready) begin
                    // Before EIEOS the PIPE boundary is observable, but no
                    // training block is semantically consumable.
                    block_locked <= 1'b0;
                end else if (is_sds) begin
                    sds_valid <= 1'b1;
                end else if (is_ts1 || is_ts2) begin
                    // The additive scrambler advances even when payload
                    // validation fails, preserving alignment for the next
                    // complete 128-bit block.
                    lfsr_state <= lfsr_after_block;
                    if (!ts_payload_valid) begin
                        malformed <= 1'b1;
                    end else begin
                        link_number <= descrambled_block[15:8];
                        link_is_pad <= descrambled_block[15:8] == K_PAD;
                        lane_number <= descrambled_block[23:16];
                        lane_is_pad <= descrambled_block[23:16] == K_PAD;
                        n_fts <= descrambled_block[31:24];
                        rate_id <= descrambled_block[39:32];
                        training_control <= descrambled_block[47:40];
                        eq_control <= descrambled_block[55:48];
                        eq_data <= {
                            descrambled_block[79:64],
                            descrambled_block[63:56]
                        };
                        if (is_ts1)
                            ts1_valid <= 1'b1;
                        else
                            ts2_valid <= 1'b1;
                    end
                end else if (data_stream_block) begin
                    // E1 exposes only a block-level logical-idle marker.
                    // Full Gen3 framing-token decoding belongs to E5.
                    idle_valid <= block_data == 128'd0;
                end else begin
                    // A structurally valid but unsupported Ordered Set must
                    // not destroy block lock; report it to the protocol layer.
                    malformed <= 1'b1;
                end
            end
        end
    end
endmodule

// Reassemble four accepted 32-bit PIPE transfers into one 128-bit block.
// RxDataValid bubbles are ignored. A new StartBlock in the middle of a block
// reports a boundary error and simultaneously starts a fresh candidate block.
/* verilator lint_off DECLFILENAME */
module pcie_gen3_block_rx (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,
    input  wire         in_valid,
    input  wire         start_block,
    input  wire [1:0]   sync_header,
    input  wire [31:0]  in_data,
    output reg          block_valid,
    output reg  [127:0] block_data,
    output reg  [1:0]   block_sync_header,
    output reg          boundary_error
);
    reg collecting;
    reg [1:0] word_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            collecting <= 1'b0;
            word_index <= 2'd0;
            block_valid <= 1'b0;
            block_data <= 128'd0;
            block_sync_header <= 2'b00;
            boundary_error <= 1'b0;
        end else begin
            block_valid <= 1'b0;
            boundary_error <= 1'b0;
            if (!enable) begin
                collecting <= 1'b0;
                word_index <= 2'd0;
                block_data <= 128'd0;
                block_sync_header <= 2'b00;
            end else if (in_valid) begin
                if (start_block) begin
                    if (collecting)
                        boundary_error <= 1'b1;
                    collecting <= 1'b1;
                    word_index <= 2'd1;
                    block_data[31:0] <= in_data;
                    block_sync_header <= sync_header;
                end else if (collecting) begin
                    case (word_index)
                        2'd1: block_data[63:32] <= in_data;
                        2'd2: block_data[95:64] <= in_data;
                        default: block_data[127:96] <= in_data;
                    endcase
                    if (word_index == 2'd3) begin
                        collecting <= 1'b0;
                        word_index <= 2'd0;
                        block_valid <= 1'b1;
                    end else begin
                        word_index <= word_index + 1'b1;
                    end
                end
            end
        end
    end
endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
