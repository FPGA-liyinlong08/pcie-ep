`timescale 1ns/1ps
`default_nettype none

// Semantic Recovery.Speed controller.  Raw PHY_RATE, TXEI and PhyStatus are
// owned/consumed by pcie_phy_rate_contract; this block only sequences protocol
// requests, completion and fallback policy.
module pcie_recovery_speed_ctrl #(
    parameter integer SPEED_TIMEOUT_CYCLES = 1_000_000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       link_up,
    input  wire       reinitialize_gen1,
    input  wire       retrain_valid,
    input  wire [1:0] retrain_target_speed,
    input  wire       ltssm_speed_ready,

    output reg        rate_req_valid,
    output reg  [1:0] rate_req_target,
    output reg        fallback_req,
    input  wire       rate_req_ready,
    input  wire       rate_op_done,
    input  wire       rate_op_failed,
    input  wire [1:0] active_rate,

    output reg        retrain_accept,
    input  wire       phy_cdr_lost,
    input  wire       peer_speed_ok,
    input  wire       peer_speed_reject,
    output reg  [2:0] state,
    output reg        traffic_quiesce,
    output reg        recovery_active,
    output reg  [1:0] negotiated_speed,
    output reg        speed_timeout_sticky,
    output reg        peer_reject_sticky,
    output reg        illegal_speed_sticky,
    output reg        cdr_loss_sticky,
    output reg        fallback_taken_sticky
);
    localparam [2:0] ST_L0               = 3'd0;
    localparam [2:0] ST_QUIESCE          = 3'd1;
    localparam [2:0] ST_RATE_REQUEST     = 3'd2;
    localparam [2:0] ST_RATE_WAIT        = 3'd3;
    localparam [2:0] ST_RECOVERY_IDLE    = 3'd4;
    localparam [2:0] ST_FALLBACK_REQUEST = 3'd5;
    localparam [2:0] ST_FALLBACK_WAIT    = 3'd6;
    localparam [2:0] ST_FALLBACK_IDLE   = 3'd7;

    localparam integer TIMEOUT_LIMIT =
        (SPEED_TIMEOUT_CYCLES < 1) ? 1 : SPEED_TIMEOUT_CYCLES;
    reg [1:0] pending_speed;
    reg [31:0] timeout_count;
    wire target_speed_legal = retrain_target_speed != 2'b11;
    wire timeout_expired = timeout_count >= (TIMEOUT_LIMIT - 1);

    always @* begin
        rate_req_valid  = 1'b0;
        rate_req_target = pending_speed;
        fallback_req    = 1'b0;
        traffic_quiesce = 1'b0;
        recovery_active = 1'b0;
        case (state)
            ST_QUIESCE, ST_RATE_WAIT, ST_RECOVERY_IDLE,
            ST_FALLBACK_WAIT, ST_FALLBACK_IDLE: begin
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_RATE_REQUEST: begin
                rate_req_valid  = 1'b1;
                rate_req_target = pending_speed;
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            ST_FALLBACK_REQUEST: begin
                rate_req_valid  = 1'b1;
                rate_req_target = 2'b00;
                fallback_req    = 1'b1;
                traffic_quiesce = 1'b1;
                recovery_active = 1'b1;
            end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_L0;
            pending_speed <= 2'b00;
            timeout_count <= 32'd0;
            retrain_accept <= 1'b0;
            negotiated_speed <= 2'b00;
            speed_timeout_sticky <= 1'b0;
            peer_reject_sticky <= 1'b0;
            illegal_speed_sticky <= 1'b0;
            cdr_loss_sticky <= 1'b0;
            fallback_taken_sticky <= 1'b0;
        end else if (reinitialize_gen1) begin
            state <= ST_L0;
            pending_speed <= 2'b00;
            timeout_count <= 32'd0;
            retrain_accept <= 1'b0;
            negotiated_speed <= 2'b00;
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
                ST_QUIESCE: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if (ltssm_speed_ready) begin
                        timeout_count <= 32'd0;
                        state <= ST_RATE_REQUEST;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RATE_REQUEST: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if (rate_op_failed) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if (rate_req_ready) begin
                        timeout_count <= 32'd0;
                        state <= ST_RATE_WAIT;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RATE_WAIT: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if (rate_op_failed) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if (rate_op_done) begin
                        timeout_count <= 32'd0;
                        state <= ST_RECOVERY_IDLE;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_RECOVERY_IDLE: begin
                    if (phy_cdr_lost) begin
                        cdr_loss_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if (peer_speed_reject) begin
                        peer_reject_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else if ((active_rate == pending_speed) && peer_speed_ok) begin
                        negotiated_speed <= pending_speed;
                        timeout_count <= 32'd0;
                        state <= ST_L0;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        fallback_taken_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_REQUEST;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_REQUEST: begin
                    // Once fallback is policy-selected, a persistent CDR-loss
                    // indication must not prevent the Gen1 request handshake.
                    if (rate_req_ready) begin
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_WAIT;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_IDLE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_WAIT: begin
                    if (rate_op_done) begin
                        timeout_count <= 32'd0;
                        state <= ST_FALLBACK_IDLE;
                    end else if (rate_op_failed) begin
                        // Keep Recovery asserted.  LTSSM timeout/reinitialize
                        // is the only safe exit after a failed fallback.
                        speed_timeout_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                    end else if (timeout_expired) begin
                        speed_timeout_sticky <= 1'b1;
                        timeout_count <= 32'd0;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                ST_FALLBACK_IDLE: begin
                    if ((active_rate == 2'b00) && peer_speed_ok) begin
                        negotiated_speed <= 2'b00;
                        timeout_count <= 32'd0;
                        state <= ST_L0;
                    end else if (timeout_expired) begin
                        // Gen1 fallback is still the safe negotiated state;
                        // allow LTSSM to continue its recovery timeout policy.
                        negotiated_speed <= 2'b00;
                        timeout_count <= 32'd0;
                        state <= ST_L0;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                default: state <= ST_L0;
            endcase
        end
    end
endmodule

`default_nettype wire
