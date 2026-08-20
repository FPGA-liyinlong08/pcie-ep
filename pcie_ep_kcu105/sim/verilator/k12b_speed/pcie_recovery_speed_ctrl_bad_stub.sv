// Deliberately bad semantic stub for checker-selftest: it enters
// RECOVERY_IDLE as soon as a request is seen, before rate_op_done.
module pcie_recovery_speed_ctrl #(
    parameter integer SPEED_TIMEOUT_CYCLES = 4
) (
    input wire clk, input wire rst_n, input wire link_up,
    input wire reinitialize_gen1,
    input wire retrain_valid, input wire [1:0] retrain_target_speed,
    input wire ltssm_speed_ready,
    output reg rate_req_valid, output reg [1:0] rate_req_target,
    output reg fallback_req, input wire rate_req_ready,
    input wire rate_op_done, input wire rate_op_failed,
    input wire [1:0] active_rate,
    output reg retrain_accept, input wire phy_cdr_lost,
    input wire peer_speed_ok, input wire peer_speed_reject,
    output reg [2:0] state,
    output reg traffic_quiesce, output reg recovery_active,
    output reg [1:0] negotiated_speed,
    output reg speed_timeout_sticky, output reg peer_reject_sticky,
    output reg illegal_speed_sticky, output reg cdr_loss_sticky,
    output reg fallback_taken_sticky
);
    localparam [2:0] ST_L0 = 3'd0;
    localparam [2:0] ST_RECOVERY_IDLE = 3'd4;
    always @* begin
        rate_req_valid = 1'b0;
        rate_req_target = retrain_target_speed;
        fallback_req = 1'b0;
        traffic_quiesce = (state != ST_L0);
        recovery_active = traffic_quiesce;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || reinitialize_gen1) begin
            state <= ST_L0;
            retrain_accept <= 1'b0;
            negotiated_speed <= 2'b00;
            speed_timeout_sticky <= 1'b0;
            peer_reject_sticky <= 1'b0;
            illegal_speed_sticky <= 1'b0;
            cdr_loss_sticky <= 1'b0;
            fallback_taken_sticky <= 1'b0;
        end else begin
            retrain_accept <= retrain_valid && link_up;
            if (retrain_valid && link_up && retrain_target_speed != 2'b11)
                state <= ST_RECOVERY_IDLE;
            if (state == ST_RECOVERY_IDLE && peer_speed_ok)
                state <= ST_L0;
        end
    end
endmodule
