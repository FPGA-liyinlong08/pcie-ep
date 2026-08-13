`timescale 1ns/1ps
`default_nettype none

// K12-B：Recovery.Speed独立控制骨架。
// 本模块只处理速率阶段和Gen1 fallback，不实现TS解析或EQ Phase 0～3。
module pcie_recovery_speed_ctrl #(
    parameter integer SPEED_TIMEOUT_CYCLES = 32
) (
    input wire clk, input wire rst_n, input wire link_up,
    input wire retrain_valid, input wire [1:0] retrain_target_speed,
    output reg retrain_accept, input wire phy_phystatus,
    input wire phy_cdr_lost, input wire peer_speed_ok,
    input wire peer_speed_reject, output reg [2:0] state,
    output reg [1:0] phy_rate, output reg phy_txelecidle,
    output reg traffic_quiesce, output reg recovery_active,
    output reg [1:0] negotiated_speed,
    output reg speed_timeout_sticky, output reg peer_reject_sticky,
    output reg illegal_speed_sticky, output reg cdr_loss_sticky,
    output reg fallback_taken_sticky
);
    localparam [2:0] ST_L0 = 3'd0;
    localparam [2:0] ST_QUIESCE = 3'd1;
    localparam [2:0] ST_SPEED_WAIT = 3'd2;
    localparam [2:0] ST_RECOVERY_IDLE = 3'd3;
    localparam [2:0] ST_FALLBACK_WAIT = 3'd4;
    localparam [2:0] ST_FALLBACK_IDLE = 3'd5;
    localparam integer TIMEOUT_LIMIT = (SPEED_TIMEOUT_CYCLES < 1) ? 1 : SPEED_TIMEOUT_CYCLES;
    reg [1:0] pending_speed;
    reg [31:0] timeout_count;
    wire target_speed_legal = retrain_target_speed != 2'b11;
    wire timeout_expired = timeout_count >= (TIMEOUT_LIMIT - 1);

    always @* begin
        phy_rate = negotiated_speed;
        phy_txelecidle = 1'b0;
        traffic_quiesce = 1'b0;
        recovery_active = 1'b0;
        case (state)
            ST_QUIESCE: begin traffic_quiesce = 1'b1; recovery_active = 1'b1; end
            ST_SPEED_WAIT: begin
                phy_rate = pending_speed; phy_txelecidle = 1'b1;
                traffic_quiesce = 1'b1; recovery_active = 1'b1;
            end
            ST_RECOVERY_IDLE: begin
                phy_rate = pending_speed; traffic_quiesce = 1'b1; recovery_active = 1'b1;
            end
            ST_FALLBACK_WAIT: begin
                phy_rate = 2'b00; phy_txelecidle = 1'b1;
                traffic_quiesce = 1'b1; recovery_active = 1'b1;
            end
            ST_FALLBACK_IDLE: begin
                phy_rate = 2'b00; traffic_quiesce = 1'b1; recovery_active = 1'b1;
            end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_L0; pending_speed <= 2'b00; timeout_count <= 32'd0;
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
                            pending_speed <= retrain_target_speed;
                            timeout_count <= 32'd0;
                            state <= ST_QUIESCE;
                        end
                    end
                end
                ST_QUIESCE: begin timeout_count <= 32'd0; state <= ST_SPEED_WAIT; end
                ST_SPEED_WAIT: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky <= 1'b1; fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FALLBACK_WAIT;
                    end else if (phy_phystatus) begin
                        timeout_count <= 32'd0; state <= ST_RECOVERY_IDLE;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1; fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FALLBACK_WAIT;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RECOVERY_IDLE: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky <= 1'b1; fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FALLBACK_WAIT;
                    end else if (peer_speed_reject) begin
                        peer_reject_sticky <= 1'b1; fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FALLBACK_WAIT;
                    end else if (peer_speed_ok) begin
                        negotiated_speed <= pending_speed;
                        timeout_count <= 32'd0; state <= ST_L0;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1; fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FALLBACK_WAIT;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_WAIT: begin
                    if (phy_phystatus) begin
                        timeout_count <= 32'd0; state <= ST_FALLBACK_IDLE;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FALLBACK_IDLE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_IDLE: begin
                    if (peer_speed_ok) begin
                        negotiated_speed <= 2'b00; timeout_count <= 32'd0; state <= ST_L0;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1; negotiated_speed <= 2'b00;
                        timeout_count <= 32'd0; state <= ST_L0;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                default: begin state <= ST_L0; negotiated_speed <= 2'b00; timeout_count <= 32'd0; end
            endcase
        end
    end
endmodule

`default_nettype wire
