module pcie_recovery_speed_ctrl #(
    parameter integer SPEED_TIMEOUT_CYCLES = 4
) (
    input wire clk, input wire rst_n, input wire link_up,
    input wire retrain_valid, input wire [1:0] retrain_target_speed,
    output reg retrain_accept, input wire phy_phystatus,
    input wire phy_cdr_lost, input wire peer_speed_ok, input wire peer_speed_reject,
    output reg [2:0] state, output reg [1:0] phy_rate,
    output reg phy_txelecidle, output reg traffic_quiesce, output reg recovery_active,
    output reg [1:0] negotiated_speed, output reg speed_timeout_sticky,
    output reg peer_reject_sticky, output reg illegal_speed_sticky,
    output reg cdr_loss_sticky, output reg fallback_taken_sticky
);
    localparam [2:0] ST_L0 = 3'd0;
    localparam [2:0] ST_RECOVERY_IDLE = 3'd3;
    reg [1:0] bad_target;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_L0; retrain_accept <= 0; negotiated_speed <= 0; bad_target <= 0;
        end else begin
            retrain_accept <= retrain_valid && link_up;
            if (retrain_valid && link_up && retrain_target_speed != 2'b11) begin
                state <= ST_RECOVERY_IDLE; bad_target <= retrain_target_speed;
            end
        end
    end
    always @* begin
        phy_rate = (state == ST_RECOVERY_IDLE) ? bad_target : negotiated_speed;
        phy_txelecidle = 0; traffic_quiesce = (state == ST_RECOVERY_IDLE);
        recovery_active = traffic_quiesce; speed_timeout_sticky = 0;
        peer_reject_sticky = 0; illegal_speed_sticky = 0; cdr_loss_sticky = 0;
        fallback_taken_sticky = 0;
    end
endmodule
