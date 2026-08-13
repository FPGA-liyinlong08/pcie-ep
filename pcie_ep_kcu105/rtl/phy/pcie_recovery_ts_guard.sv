`timescale 1ns/1ps
`default_nettype none

// K12-D：Recovery TS 合法性门禁。
// 只在完整 Ordered Set 边界提交一次合法 TS；任何字段非法或不匹配都拒绝。
module pcie_recovery_ts_guard #(
    parameter [2:0] EXPECTED_LANE = 3'd0,
    parameter [7:0] EXPECTED_LINK = 8'd0
) (
    input wire       clk,
    input wire       rst_n,
    input wire       ts_valid,
    input wire       ts_complete,
    input wire       ts_is_ts1,
    input wire       ts_is_ts2,
    input wire [2:0] ts_lane,
    input wire [7:0] ts_link,
    input wire [1:0] ts_rate,
    input wire       ts_eq_request,
    output reg       ts_accept,
    output reg       ts_reject,
    output reg       malformed_sticky,
    output reg       illegal_rate_sticky,
    output reg       lane_link_mismatch_sticky
);
    wire type_legal = ts_is_ts1 ^ ts_is_ts2;
    wire rate_legal = ts_rate != 2'b11;
    wire lane_link_legal = (ts_lane == EXPECTED_LANE) &&
                           (ts_link == EXPECTED_LINK);
    wire eq_legal = !ts_eq_request || (ts_rate == 2'b10);
    wire fields_legal = type_legal && rate_legal && lane_link_legal && eq_legal;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts_accept <= 1'b0;
            ts_reject <= 1'b0;
            malformed_sticky <= 1'b0;
            illegal_rate_sticky <= 1'b0;
            lane_link_mismatch_sticky <= 1'b0;
        end else begin
            ts_accept <= 1'b0;
            ts_reject <= 1'b0;
            if (ts_valid && ts_complete) begin
                if (fields_legal) begin
                    ts_accept <= 1'b1;
                end else begin
                    ts_reject <= 1'b1;
                    if (!type_legal || !eq_legal)
                        malformed_sticky <= 1'b1;
                    if (!rate_legal)
                        illegal_rate_sticky <= 1'b1;
                    if (!lane_link_legal)
                        lane_link_mismatch_sticky <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
