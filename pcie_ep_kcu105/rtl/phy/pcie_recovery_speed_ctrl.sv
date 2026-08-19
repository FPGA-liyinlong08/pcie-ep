`timescale 1ns/1ps
`default_nettype none

// K13 Recovery.Speed 控制器（semantic layer）。
// 不再直接驱动 raw phy_rate / phy_txelecidle，也不再消费 raw phy_phystatus。
// 改用 rate_req_* 语义接口向 pcie_phy_rate_contract 发请求。
//
// 8 态 FSM（Doc Section 9）：
//   ST_L0                稳态，等 retrain 请求
//   ST_QUIESCE           等 ltssm_speed_ready
//   ST_RATE_REQUEST      驱动 rate_req_valid/target，等 rate_req_ready
//   ST_RATE_WAIT         已被 contract 接受，等 rate_op_done/failed
//   ST_RECOVERY_IDLE     物理切速完成，等 peer TS
//   ST_FALLBACK_REQUEST  fallback 路径：发 Gen1 请求
//   ST_FALLBACK_WAIT     等 Gen1 物理完成
//   ST_FALLBACK_IDLE     等对端接受 Gen1
//
// 状态编码：3'd0..3'd7
// 0=L0 1=QUIESCE 2=RATE_REQUEST 3=RATE_WAIT
// 4=RECOVERY_IDLE 5=FALLBACK_REQUEST 6=FALLBACK_WAIT 7=FALLBACK_IDLE
module pcie_recovery_speed_ctrl #(
    parameter integer SPEED_TIMEOUT_CYCLES = 1_000_000
) (
    input wire clk, input wire rst_n, input wire link_up,
    input wire retrain_valid, input wire [1:0] retrain_target_speed,
    input wire ltssm_speed_ready,

    // Semantic request to pcie_phy_rate_contract
    output reg rate_req_valid,
    output reg [1:0] rate_req_target,
    input wire rate_req_ready,

    // Completion feedback from contract
    input wire rate_op_done,
    input wire rate_op_failed,

    // 内部诊断
    output reg retrain_accept, input wire phy_cdr_lost,
    input wire peer_speed_ok, input wire peer_speed_reject,
    output reg [2:0] state,

    // Active signals（不再是 raw phy_rate / phy_txelecidle）
    output reg traffic_quiesce, output reg recovery_active,
    output reg [1:0] negotiated_speed,

    // Sticky 故障位
    output reg speed_timeout_sticky, output reg peer_reject_sticky,
    output reg illegal_speed_sticky, output reg cdr_loss_sticky,
    output reg fallback_taken_sticky
);
    localparam [2:0] ST_L0               = 3'd0;
    localparam [2:0] ST_QUIESCE          = 3'd1;
    localparam [2:0] ST_RATE_REQUEST     = 3'd2;
    localparam [2:0] ST_RATE_WAIT        = 3'd3;
    localparam [2:0] ST_RECOVERY_IDLE    = 3'd4;
    localparam [2:0] ST_FALLBACK_REQUEST = 3'd5;
    localparam [2:0] ST_FALLBACK_WAIT    = 3'd6;
    localparam [2:0] ST_FALLBACK_IDLE    = 3'd7;

    localparam integer TIMEOUT_LIMIT =
        (SPEED_TIMEOUT_CYCLES < 1) ? 1 : SPEED_TIMEOUT_CYCLES;
    reg [1:0] pending_speed;
    reg [31:0] timeout_count;
    wire target_speed_legal = retrain_target_speed != 2'b11;
    wire timeout_expired    = timeout_count >= (TIMEOUT_LIMIT - 1);

    // 组合输出
    always @* begin
        rate_req_valid  = 1'b0;
        rate_req_target = pending_speed;
        traffic_quiesce = 1'b0;
        recovery_active = 1'b0;
        case (state)
            ST_QUIESCE: begin
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_RATE_REQUEST: begin
                rate_req_valid  = 1'b1;
                rate_req_target = pending_speed;
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_RATE_WAIT: begin
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_RECOVERY_IDLE: begin
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_FALLBACK_REQUEST: begin
                // 唯一允许 rate_req_valid=1 但 target!=pending_speed 的状态
                rate_req_valid  = 1'b1;
                rate_req_target = 2'b00;  // Gen1 fallback 唯一合法目标
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_FALLBACK_WAIT: begin
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_FALLBACK_IDLE: begin
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            default: begin end
        endcase
    end

    // 同步时序
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_L0; pending_speed <= 2'b00;
            timeout_count <= 32'd0;
            retrain_accept <= 1'b0; negotiated_speed <= 2'b00;
            speed_timeout_sticky <= 1'b0; peer_reject_sticky <= 1'b0;
            illegal_speed_sticky <= 1'b0; cdr_loss_sticky <= 1'b0;
            fallback_taken_sticky <= 1'b0;
        end else begin
            retrain_accept <= 1'b0;
            case (state)
                ST_L0: begin
                    timeout_count <= 32'd0;
                    if (retrain_valid && link_up) begin
                        retrain_accept <= 1'b1;
                        if (!target_speed_legal) begin
                            illegal_speed_sticky <= 1'b1;
                        end else if (retrain_target_speed != negotiated_speed) begin
                            pending_speed  <= retrain_target_speed;
                            timeout_count  <= 32'd0;
                            state          <= ST_QUIESCE;
                        end
                    end
                end
                ST_QUIESCE: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky      <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (ltssm_speed_ready) begin
                        timeout_count <= 32'd0;
                        state         <= ST_RATE_REQUEST;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RATE_REQUEST: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky      <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (rate_op_failed) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (rate_req_ready) begin
                        timeout_count <= 32'd0;
                        state         <= ST_RATE_WAIT;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RATE_WAIT: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky      <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (rate_op_failed) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (rate_op_done) begin
                        timeout_count <= 32'd0;
                        state         <= ST_RECOVERY_IDLE;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RECOVERY_IDLE: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky      <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (peer_speed_reject) begin
                        peer_reject_sticky    <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else if (peer_speed_ok) begin
                        negotiated_speed <= pending_speed;
                        timeout_count    <= 32'd0;
                        state            <= ST_L0;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_REQUEST: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky      <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                    end else if (rate_op_failed) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_IDLE;
                    end else if (rate_req_ready) begin
                        timeout_count <= 32'd0;
                        state         <= ST_FALLBACK_WAIT;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_IDLE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_WAIT: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky      <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_IDLE;
                    end else if (rate_op_done) begin
                        timeout_count <= 32'd0;
                        state         <= ST_FALLBACK_IDLE;
                    end else if (rate_op_failed) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_IDLE;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count        <= 32'd0;
                        state                <= ST_FALLBACK_IDLE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_IDLE: begin
                    if (peer_speed_ok) begin
                        negotiated_speed <= 2'b00;
                        timeout_count    <= 32'd0;
                        state            <= ST_L0;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        negotiated_speed     <= 2'b00;
                        timeout_count        <= 32'd0;
                        state                <= ST_L0;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                default: begin
                    state          <= ST_L0;
                    negotiated_speed <= 2'b00;
                    timeout_count  <= 32'd0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
