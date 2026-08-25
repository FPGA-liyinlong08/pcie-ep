`timescale 1ns/1ps
`default_nettype none

// K13 diagnostic-only replay of the K02 Golden PHY command envelope.
//
// This block deliberately does not touch any GT primitive control.  It only
// owns the public PIPE command bundle during one Gen3 rate transaction:
// hold P0/TXEI, keep all auxiliary commands benign, wait the same 10 us
// release gap used by the K02 Golden stimulus, then request Gen3 and hold the
// bundle until PhyStatus.  The surrounding K13 LTSSM/retrain environment and
// the generated PHY remain unchanged.
module k13_golden_rate_replay #(
    parameter integer RELEASE_GAP_CYCLES = 2500
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       reinitialize_gen1,
    input  wire       start,
    input  wire       phy_phystatus,

    output wire       active,
    output wire       done,
    output wire [1:0] phy_rate,
    output wire [1:0] phy_powerdown,
    output wire       phy_txelecidle,
    output wire       phy_txdetectrx,
    output wire [1:0] phy_txeq_ctrl,
    output wire [3:0] phy_txeq_preset,
    output wire [5:0] phy_txeq_coeff,
    output wire [1:0] phy_rxeq_ctrl,
    output wire [3:0] phy_rxeq_txpreset,
    output wire       as_mac_in_detect,
    output wire       as_cdr_hold_req
);
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_GAP  = 2'd1;
    localparam [1:0] S_RATE = 2'd2;
    localparam [1:0] S_DONE = 2'd3;

    localparam integer GAP_LIMIT =
        (RELEASE_GAP_CYCLES < 1) ? 1 : RELEASE_GAP_CYCLES;

    reg [1:0] state_r;
    reg [31:0] gap_count_r;
    reg done_r;
    reg phystatus_d;

    assign active = (state_r != S_IDLE) && (state_r != S_DONE);
    assign done = done_r;

    // K02 Golden command envelope: P0, no receiver detect, no TX/RX EQ
    // transaction, and CDR held throughout the physical rate operation.
    assign phy_powerdown   = 2'b00;
    assign phy_txelecidle  = active;
    assign phy_txdetectrx  = 1'b0;
    assign phy_txeq_ctrl   = 2'b00;
    assign phy_txeq_preset = 4'd0;
    assign phy_txeq_coeff  = 6'd0;
    assign phy_rxeq_ctrl   = 2'b00;
    assign phy_rxeq_txpreset = 4'd0;
    assign as_mac_in_detect = 1'b0;
    assign as_cdr_hold_req  = active;
    assign phy_rate = (state_r == S_RATE) ? 2'b10 : 2'b00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r     <= S_IDLE;
            gap_count_r <= 32'd0;
            done_r      <= 1'b0;
            phystatus_d <= 1'b0;
        end else if (reinitialize_gen1) begin
            state_r     <= S_IDLE;
            gap_count_r <= 32'd0;
            done_r      <= 1'b0;
            phystatus_d <= phy_phystatus;
        end else begin
            done_r <= 1'b0;
            phystatus_d <= phy_phystatus;
            case (state_r)
                S_IDLE: begin
                    gap_count_r <= 32'd0;
                    if (start)
                        state_r <= S_GAP;
                end
                S_GAP: begin
                    if (gap_count_r >= (GAP_LIMIT - 1)) begin
                        gap_count_r <= 32'd0;
                        state_r <= S_RATE;
                    end else begin
                        gap_count_r <= gap_count_r + 1'b1;
                    end
                end
                S_RATE: begin
                    if (phy_phystatus && !phystatus_d) begin
                        state_r <= S_DONE;
                        done_r  <= 1'b1;
                    end
                end
                S_DONE: begin
                    // Return ownership to K13 production control on the next
                    // cycle; a new transaction requires a fresh retrain.
                    if (!start)
                        state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
