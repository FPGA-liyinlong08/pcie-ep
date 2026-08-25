`timescale 1ns/1ps
`default_nettype none

// Gen1 PHY command boundary.  The LTSSM selects a semantic profile and owns
// protocol timeout/state policy; this block is the sole owner of raw PIPE/PHY
// commands and translates PhyStatus into a same-cycle semantic completion.
module pcie_phy_command_ctrl (
    input  wire        phy_pclk,
    input  wire        pipe_rst_n,

    input  wire [2:0]  cmd_profile,
    input  wire        op_valid,
    input  wire        op_kind,
    output wire        op_ready,
    output wire        op_done,
    output wire [1:0]  op_result,

    input  wire        phy_phystatus,
    input  wire [2:0]  phy_rxstatus,

    output reg  [1:0]  phy_powerdown,
    output reg         phy_txdetectrx,
    output reg         phy_txelecidle,
    output wire [1:0]  phy_rate,
    output wire [1:0]  phy_txeq_ctrl,
    output wire [3:0]  phy_txeq_preset,
    output wire [5:0]  phy_txeq_coeff,
    output wire [1:0]  phy_rxeq_ctrl,
    output wire [3:0]  phy_rxeq_txpreset,
    output reg         as_mac_in_detect,
    output reg         as_cdr_hold_req,
    output wire        phy_txcompliance,
    output wire        phy_rxpolarity,
    output wire [2:0]  phy_txmargin,
    output wire        phy_txswing,
    output wire        phy_txdeemph
);
    localparam [2:0] PROFILE_DETECT_QUIET = 3'd0;
    localparam [2:0] PROFILE_DETECT_ACTIVE = 3'd1;
    localparam [2:0] PROFILE_PHY_POWERUP = 3'd2;
    localparam [2:0] PROFILE_G9_REMOTE_WAIT = 3'd3;
    localparam [2:0] PROFILE_ACTIVE = 3'd4;
    localparam [2:0] PROFILE_RECOVERY_SPEED = 3'd5;

    localparam       OP_RECEIVER_DETECT = 1'b0;
    localparam [1:0] RESULT_SUCCESS = 2'd1;
    localparam [1:0] RESULT_NOT_PRESENT = 2'd2;

    // The controller is always able to accept the profile selected for the
    // current LTSSM state.  Completion deliberately uses the current
    // PhyStatus beat; no completion pipeline is inserted at this boundary.
    assign op_ready = pipe_rst_n;
    assign op_done = pipe_rst_n && op_valid && op_ready && phy_phystatus;
    assign op_result = !op_done ? 2'd0 :
        ((op_kind == OP_RECEIVER_DETECT) && (phy_rxstatus != 3'b011)) ?
            RESULT_NOT_PRESENT : RESULT_SUCCESS;

    always @* begin
        phy_powerdown = 2'b00;
        phy_txdetectrx = 1'b0;
        phy_txelecidle = 1'b0;
        as_mac_in_detect = 1'b0;
        as_cdr_hold_req = 1'b0;
        case (cmd_profile)
            PROFILE_DETECT_QUIET: begin
                phy_powerdown = 2'b10;
                phy_txelecidle = 1'b1;
                as_mac_in_detect = 1'b1;
            end
            PROFILE_DETECT_ACTIVE: begin
                phy_powerdown = 2'b10;
                phy_txdetectrx = 1'b1;
                phy_txelecidle = 1'b1;
                as_mac_in_detect = 1'b1;
            end
            PROFILE_PHY_POWERUP: begin
                phy_txelecidle = 1'b1;
            end
            PROFILE_G9_REMOTE_WAIT: begin
                phy_txelecidle = 1'b1;
                as_mac_in_detect = 1'b1;
            end
            PROFILE_RECOVERY_SPEED: begin
                as_cdr_hold_req = 1'b1;
            end
            default: begin
                // Polling, Configuration, Recovery, L0 and Hot Reset use
                // the active Gen1 P0 profile.
            end
        endcase
    end

    // Phase B/C is intentionally Gen1-only.  Compliance, polarity, margin,
    // swing, deemphasis and all equalization controls have one centralized
    // zero owner here.
    assign phy_rate = 2'b00;
    assign phy_txeq_ctrl = 2'b00;
    assign phy_txeq_preset = 4'd0;
    assign phy_txeq_coeff = 6'd0;
    assign phy_rxeq_ctrl = 2'b00;
    assign phy_rxeq_txpreset = 4'd0;
    assign phy_txcompliance = 1'b0;
    assign phy_rxpolarity = 1'b0;
    assign phy_txmargin = 3'b000;
    assign phy_txswing = 1'b0;
    assign phy_txdeemph = 1'b0;

    wire _unused = &{1'b0, phy_pclk, PROFILE_ACTIVE};
endmodule

`default_nettype wire
