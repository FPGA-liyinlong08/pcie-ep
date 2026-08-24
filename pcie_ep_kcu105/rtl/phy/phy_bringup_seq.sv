`timescale 1ns/1ps
`default_nettype none

// Synthesizable equivalent of imports/board.v's EP/RP bring-up stimulus.
//
// This block is intentionally restricted to the six bring-up inputs consumed
// by the original Xilinx phy_ctrl.v.  PHY_RATE, PHY_POWERDOWN, TXEQ,
// as_mac_in_detect, and as_cdr_hold_req remain outputs of phy_ctrl.v.
//
// board.v timing (100 MHz simulation reference clock):
//   wait phy-ready, #10000, assert READY+GEN1, #5000,
//   wait debug_state==PHY_BUP_PHY_RDY2, #50000,
//   deassert GEN1, #10000, assert GEN3,
//   wait debug_state==PHY_BUP_PHY_RDY2, #80000, deassert GEN3.
//
// The sequence runs in phy_pclk.  At the KCU105 IP configuration phy_pclk is
// 250 MHz, so the delays below preserve the original wall-clock intervals.
module phy_bringup_seq #(
    parameter integer SEQ_CLK_HZ = 250_000_000,
    parameter integer WAIT_AFTER_READY_NS = 10_000,
    parameter integer WAIT_AFTER_GEN1_ON_NS = 5_000,
    parameter integer GEN1_HOLD_NS = 50_000,
    parameter integer WAIT_AFTER_GEN1_OFF_NS = 10_000,
    parameter integer GEN3_HOLD_NS = 80_000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       phy_status_ready,
    input  wire [7:0] phy_ctrl_debug_state,

    output logic      tx_elec_idle,
    output logic      phy_ready_en,
    output logic      gen1_en,
    output logic      gen2_en,
    output logic      gen3_en,
    output logic      gen4_en,
    output logic [3:0] seq_state,
    output logic      gen3_request
);

    localparam logic [3:0] S_RESET          = 4'd0;
    localparam logic [3:0] S_WAIT_READY     = 4'd1;
    localparam logic [3:0] S_POWER_UP      = 4'd2;
    localparam logic [3:0] S_GEN1_WAIT     = 4'd3;
    localparam logic [3:0] S_GEN1_HOLD     = 4'd4;
    localparam logic [3:0] S_GEN1_OFF_GAP  = 4'd5;
    localparam logic [3:0] S_GEN3_WAIT     = 4'd6;
    localparam logic [3:0] S_GEN3_HOLD     = 4'd7;
    localparam logic [3:0] S_DONE          = 4'd8;

    // All requested board.v delays are integer multiples at 250 MHz.
    localparam integer CYCLES_PER_US = (SEQ_CLK_HZ / 1_000_000);
    localparam integer WAIT_AFTER_READY_CYCLES =
        CYCLES_PER_US * (WAIT_AFTER_READY_NS / 1_000);
    localparam integer WAIT_AFTER_GEN1_ON_CYCLES =
        CYCLES_PER_US * (WAIT_AFTER_GEN1_ON_NS / 1_000);
    localparam integer GEN1_HOLD_CYCLES =
        CYCLES_PER_US * (GEN1_HOLD_NS / 1_000);
    localparam integer WAIT_AFTER_GEN1_OFF_CYCLES =
        CYCLES_PER_US * (WAIT_AFTER_GEN1_OFF_NS / 1_000);
    localparam integer GEN3_HOLD_CYCLES =
        CYCLES_PER_US * (GEN3_HOLD_NS / 1_000);

    logic [31:0] delay_count;

    function automatic logic delay_complete(
        input logic [31:0] count,
        input integer limit
    );
        begin
            delay_complete = (limit <= 1) || (count >= limit - 1);
        end
    endfunction

    always_comb begin
        // board.v's comment specifies TX Electrical Idle during power-down.
        // The original phy_ctrl.v remains the only producer of PHY_TXELECIDLE;
        // this is only its original bring-up input.
        tx_elec_idle = 1'b1;
        phy_ready_en = 1'b0;
        gen1_en      = 1'b0;
        gen2_en      = 1'b0;
        gen3_en      = 1'b0;
        gen4_en      = 1'b0;
        gen3_request = 1'b0;

        case (seq_state)
            S_POWER_UP,
            S_GEN1_WAIT,
            S_GEN1_HOLD: begin
                phy_ready_en = 1'b1;
                gen1_en      = 1'b1;
            end
            S_GEN1_OFF_GAP: begin
                phy_ready_en = 1'b1;
            end
            S_GEN3_WAIT,
            S_GEN3_HOLD: begin
                phy_ready_en = 1'b1;
                gen3_en      = 1'b1;
                gen3_request = 1'b1;
            end
            S_DONE: begin
                phy_ready_en = 1'b1;
                // Keep the Gen3 rate contract asserted after the bring-up
                // sequence completes.  Dropping all gen*_en requests here
                // makes phy_ctrl interpret S_DONE as an explicit return to
                // Gen1, which resets the QPLL again.
                gen3_en      = 1'b1;
                gen3_request = 1'b1;
            end
            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            seq_state   <= S_RESET;
            delay_count <= 32'd0;
        end else begin
            case (seq_state)
                S_RESET: begin
                    delay_count <= 32'd0;
                    seq_state   <= S_WAIT_READY;
                end

                S_WAIT_READY: begin
                    delay_count <= 32'd0;
                    if (phy_status_ready)
                        seq_state <= S_POWER_UP;
                end

                S_POWER_UP: begin
                    if (delay_complete(delay_count,
                                       WAIT_AFTER_READY_CYCLES)) begin
                        delay_count <= 32'd0;
                        seq_state   <= S_GEN1_WAIT;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_GEN1_WAIT: begin
                    if ((phy_ctrl_debug_state == 8'h04) &&
                        delay_complete(delay_count,
                                        WAIT_AFTER_GEN1_ON_CYCLES)) begin
                        delay_count <= 32'd0;
                        seq_state   <= S_GEN1_HOLD;
                    end else if (!delay_complete(delay_count,
                                                  WAIT_AFTER_GEN1_ON_CYCLES)) begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_GEN1_HOLD: begin
                    if (delay_complete(delay_count, GEN1_HOLD_CYCLES)) begin
                        delay_count <= 32'd0;
                        seq_state   <= S_GEN1_OFF_GAP;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_GEN1_OFF_GAP: begin
                    if (delay_complete(delay_count,
                                       WAIT_AFTER_GEN1_OFF_CYCLES)) begin
                        delay_count <= 32'd0;
                        seq_state   <= S_GEN3_WAIT;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_GEN3_WAIT: begin
                    if (phy_ctrl_debug_state == 8'h04) begin
                        delay_count <= 32'd0;
                        seq_state   <= S_GEN3_HOLD;
                    end
                end

                S_GEN3_HOLD: begin
                    if (delay_complete(delay_count, GEN3_HOLD_CYCLES)) begin
                        delay_count <= 32'd0;
                        seq_state   <= S_DONE;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_DONE: begin
                    seq_state   <= S_DONE;
                    delay_count <= 32'd0;
                end

                default: begin
                    seq_state   <= S_RESET;
                    delay_count <= 32'd0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
