`timescale 1ns/1ps
`default_nettype none

// D3 standalone semantic stimulus.  It performs only P1->P0 power-up and one
// Golden Gen1->Gen3 rate transaction through pcie_phy_command_ctrl.  No raw
// PHY command is generated here.
module pcie_phy_rate_test_seq #(
    parameter integer ARM_DELAY_CYCLES = 500_000_000,
    parameter integer GEN1_HOLD_CYCLES = 12_500
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       phy_ready,
    input  wire       op_ready,
    input  wire       op_done,
    input  wire       rate_req_ready,
    input  wire       rate_done,
    input  wire [2:0] rate_result,
    output reg  [2:0] cmd_profile,
    output reg        op_valid,
    output reg        op_kind,
    output reg        rate_req_valid,
    output wire [1:0] rate_req_target,
    output reg  [3:0] state,
    output reg        failed
);
    localparam [3:0] ST_WAIT_READY = 4'd0;
    localparam [3:0] ST_ARM_DELAY = 4'd1;
    localparam [3:0] ST_POWER_UP = 4'd2;
    localparam [3:0] ST_GEN1_HOLD = 4'd3;
    localparam [3:0] ST_RATE_REQUEST = 4'd6;
    localparam [3:0] ST_RATE_WAIT = 4'd7;
    localparam [3:0] ST_DONE = 4'd8;
    localparam [3:0] ST_ERROR = 4'd15;

    localparam [2:0] PROFILE_DETECT_QUIET = 3'd0;
    localparam [2:0] PROFILE_PHY_POWERUP = 3'd2;
    localparam [2:0] PROFILE_ACTIVE = 3'd4;
    localparam [2:0] PROFILE_RECOVERY_SPEED = 3'd5;
    localparam OP_POWER_UP = 1'b1;

    localparam integer ARM_LIMIT =
        (ARM_DELAY_CYCLES < 1) ? 1 : ARM_DELAY_CYCLES;
    localparam integer HOLD_LIMIT =
        (GEN1_HOLD_CYCLES < 1) ? 1 : GEN1_HOLD_CYCLES;

    reg [31:0] count_r;

    assign rate_req_target = 2'b10;

    always @* begin
        cmd_profile = PROFILE_DETECT_QUIET;
        op_valid = 1'b0;
        op_kind = OP_POWER_UP;
        rate_req_valid = 1'b0;
        case (state)
            ST_POWER_UP: begin
                cmd_profile = PROFILE_PHY_POWERUP;
                op_valid = 1'b1;
            end
            ST_GEN1_HOLD: cmd_profile = PROFILE_ACTIVE;
            ST_RATE_REQUEST: begin
                cmd_profile = PROFILE_RECOVERY_SPEED;
                rate_req_valid = 1'b1;
            end
            ST_RATE_WAIT: cmd_profile = PROFILE_RECOVERY_SPEED;
            ST_DONE: cmd_profile = PROFILE_ACTIVE;
            ST_ERROR: cmd_profile = PROFILE_RECOVERY_SPEED;
            default: cmd_profile = PROFILE_DETECT_QUIET;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_WAIT_READY;
            count_r <= 32'd0;
            failed <= 1'b0;
        end else begin
            case (state)
                ST_WAIT_READY: begin
                    count_r <= 32'd0;
                    if (phy_ready)
                        state <= ST_ARM_DELAY;
                end
                ST_ARM_DELAY: begin
                    if (count_r >= (ARM_LIMIT - 1)) begin
                        count_r <= 32'd0;
                        state <= ST_POWER_UP;
                    end else begin
                        count_r <= count_r + 1'b1;
                    end
                end
                ST_POWER_UP: begin
                    if (op_ready && op_done) begin
                        count_r <= 32'd0;
                        state <= ST_GEN1_HOLD;
                    end
                end
                ST_GEN1_HOLD: begin
                    if (count_r >= (HOLD_LIMIT - 1)) begin
                        count_r <= 32'd0;
                        state <= ST_RATE_REQUEST;
                    end else begin
                        count_r <= count_r + 1'b1;
                    end
                end
                ST_RATE_REQUEST: begin
                    if (rate_req_ready)
                        state <= ST_RATE_WAIT;
                end
                ST_RATE_WAIT: begin
                    if (rate_done) begin
                        if (rate_result == 3'd1)
                            state <= ST_DONE;
                        else begin
                            failed <= 1'b1;
                            state <= ST_ERROR;
                        end
                    end
                end
                ST_DONE: state <= ST_DONE;
                default: begin
                    failed <= 1'b1;
                    state <= ST_ERROR;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
