`timescale 1ns/1ps
`default_nettype none

// Gen1/2 两 Symbol/拍 Ordered Set 接收器。K03 只启用 Gen1。
module pcie_gen1_os_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        in_valid,
    input  wire [15:0] in_data,
    input  wire [1:0]  in_datak,
    output reg         ts1_valid,
    output reg         ts2_valid,
    output reg         malformed,
    output reg         idle_pair_valid,
    output reg  [7:0]  link_number,
    output reg         link_is_pad,
    output reg  [7:0]  lane_number,
    output reg         lane_is_pad,
    output reg  [7:0]  n_fts,
    output reg  [7:0]  rate_id,
    output reg  [7:0]  training_control,
    // === 调试探针：暴露内部 FSM 状态用于 LTSSM 集成诊断 ===
    output wire        dbg_active,
    output wire [2:0]  dbg_word_index
);
    localparam [7:0] K_COM = 8'hbc;
    localparam [7:0] K_PAD = 8'hf7;
    localparam [7:0] D_IDLE = 8'h00;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;

    reg       active;
    reg [2:0] word_index;
    reg [1:0] identifier_kind;
    reg       parse_error;
    assign dbg_active = active;
    assign dbg_word_index = word_index;

    wire [7:0] symbol0 = in_data[7:0];
    wire [7:0] symbol1 = in_data[15:8];
    wire       symbol0_k = in_datak[0];
    wire       symbol1_k = in_datak[1];
    wire       ident_ts1 = !symbol0_k && !symbol1_k &&
                           (symbol0 == D_TS1) && (symbol1 == D_TS1);
    wire       ident_ts2 = !symbol0_k && !symbol1_k &&
                           (symbol0 == D_TS2) && (symbol1 == D_TS2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active           <= 1'b0;
            word_index       <= 3'd0;
            identifier_kind  <= 2'd0;
            parse_error      <= 1'b0;
            ts1_valid        <= 1'b0;
            ts2_valid        <= 1'b0;
            malformed        <= 1'b0;
            idle_pair_valid  <= 1'b0;
            link_number      <= K_PAD;
            link_is_pad      <= 1'b1;
            lane_number      <= K_PAD;
            lane_is_pad      <= 1'b1;
            n_fts            <= 8'd0;
            rate_id          <= 8'd0;
            training_control <= 8'd0;
        end else begin
            ts1_valid       <= 1'b0;
            ts2_valid       <= 1'b0;
            malformed       <= 1'b0;
            idle_pair_valid <= 1'b0;

            if (!enable) begin
                active          <= 1'b0;
                word_index      <= 3'd0;
                identifier_kind <= 2'd0;
                parse_error     <= 1'b0;
            end else if (!in_valid) begin
                if (active) begin
                    malformed <= 1'b1;
                    active    <= 1'b0;
                end
            end else if (!active) begin
                if (symbol0_k && (symbol0 == K_COM)) begin
                    active          <= 1'b1;
                    word_index      <= 3'd1;
                    identifier_kind <= 2'd0;
                    link_number     <= symbol1;
                    link_is_pad     <= symbol1_k && (symbol1 == K_PAD);
                    parse_error     <= symbol1_k != (symbol1 == K_PAD);
                end else if (symbol1_k && (symbol1 == K_COM)) begin
                    // Comma 应由 PHY 对齐到 Symbol 0；这里只报告 PCS/MAC 契约错误。
                    malformed <= 1'b1;
                end else if (!symbol0_k && !symbol1_k &&
                             (symbol0 == D_IDLE) && (symbol1 == D_IDLE)) begin
                    idle_pair_valid <= 1'b1;
                end
            end else begin
                case (word_index)
                    3'd1: begin
                        lane_number <= symbol0;
                        lane_is_pad <= symbol0_k && (symbol0 == K_PAD);
                        n_fts       <= symbol1;
                        parse_error <= parse_error |
                                       (symbol0_k != (symbol0 == K_PAD)) |
                                       symbol1_k;
                        word_index  <= 3'd2;
                    end
                    3'd2: begin
                        rate_id          <= symbol0;
                        training_control <= symbol1;
                        parse_error      <= parse_error | symbol0_k | symbol1_k;
                        word_index       <= 3'd3;
                    end
                    3'd3: begin
                        if (ident_ts1)
                            identifier_kind <= 2'd1;
                        else if (ident_ts2)
                            identifier_kind <= 2'd2;
                        else if (!symbol0_k && !symbol1_k && rate_id[3] &&
                                 (symbol1 == D_TS1)) begin
                            // 8.0 GT/s EQ TS1 uses Symbol 6 for equalization
                            // control; Symbols 7..15 retain the TS1 identifier.
                            identifier_kind <= 2'd1;
                        end else if (!symbol0_k && !symbol1_k && rate_id[3] &&
                                     (symbol1 == D_TS2)) begin
                            // Likewise, EQ TS2 replaces only Symbol 6. Requiring
                            // bit3 and all remaining identifiers keeps ordinary
                            // malformed TS detection strict.
                            identifier_kind <= 2'd2;
                        end
                        else begin
                            identifier_kind <= 2'd0;
                            parse_error     <= 1'b1;
                        end
                        word_index <= 3'd4;
                    end
                    3'd4, 3'd5, 3'd6: begin
                        if (((identifier_kind == 2'd1) && !ident_ts1) ||
                            ((identifier_kind == 2'd2) && !ident_ts2) ||
                            (identifier_kind == 2'd0))
                            parse_error <= 1'b1;
                        word_index <= word_index + 1'b1;
                    end
                    default: begin
                        active     <= 1'b0;
                        word_index <= 3'd0;
                        if (parse_error ||
                            ((identifier_kind == 2'd1) && !ident_ts1) ||
                            ((identifier_kind == 2'd2) && !ident_ts2) ||
                            (identifier_kind == 2'd0)) begin
                            malformed <= 1'b1;
                        end else if (identifier_kind == 2'd1) begin
                            ts1_valid <= 1'b1;
                        end else begin
                            ts2_valid <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
