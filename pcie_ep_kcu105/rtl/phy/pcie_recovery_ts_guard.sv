`timescale 1ns/1ps
`default_nettype none

// K12-D：Recovery TS 合法性门禁。
// 只在完整 Ordered Set 边界提交一次合法 TS；任何字段非法或不匹配都拒绝。
module pcie_recovery_ts_guard (
    input wire       clk,
    input wire       rst_n,
    input wire       ts_valid,
    input wire       ts_complete,
    input wire       ts_is_ts1,
    input wire       ts_is_ts2,
    input wire [2:0] ts_lane,
    input wire [7:0] ts_link,
    input wire [1:0] ts_rate,
    input wire [1:0] expected_rate,
    input wire       ts_eq_request,
    input wire [2:0] expected_lane,
    input wire [7:0] expected_link,
    output reg       ts_accept,
    output reg       ts2_accept,   // 仅 TS2 合法时拉高——speed_ctrl 完成 / EQ 启动都应等 TS2
    output reg       ts_reject,
    output reg       malformed_sticky,
    output reg       illegal_rate_sticky,
    output reg       lane_link_mismatch_sticky
);
    wire type_legal = ts_is_ts1 ^ ts_is_ts2;
    wire rate_legal = (ts_rate != 2'b11) && (ts_rate == expected_rate);
    wire lane_link_legal = (ts_lane == expected_lane) &&
                           (ts_link == expected_link);
    wire eq_legal = !ts_eq_request || (ts_rate == 2'b10);
    wire fields_legal = type_legal && rate_legal && lane_link_legal && eq_legal;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts_accept <= 1'b0;
            ts2_accept <= 1'b0;
            ts_reject <= 1'b0;
            malformed_sticky <= 1'b0;
            illegal_rate_sticky <= 1'b0;
            lane_link_mismatch_sticky <= 1'b0;
        end else begin
            ts_accept <= 1'b0;
            ts2_accept <= 1'b0;
            ts_reject <= 1'b0;
            if (ts_valid && ts_complete) begin
                if (fields_legal) begin
                    ts_accept <= 1'b1;
                    // TS2 是 partner 对 rate change 的最终确认:
                    //  partner 在 RECOVERY_SPEED 先发 TS1 (请求), 后发 TS2 (确认)
                    //  speed_ctrl 的 ST_RECOVERY_IDLE 必须等 TS2 才能认为 peer
                    //  真的接受了新速率——否则一拍 TS1 就误判 done, LTSSM 提前
                    //  退 RECOVERY_SPEED, partner 还没发 TS2, 整个闭环崩。
                    if (ts_is_ts2)
                        ts2_accept <= 1'b1;
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
