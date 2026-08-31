`timescale 1ns/1ps
`default_nettype none

// Gen1 PHY command boundary.  The LTSSM selects a semantic profile and owns
// protocol timeout/state policy; this block is the sole owner of raw PIPE/PHY
// commands and translates PhyStatus into a same-cycle semantic completion.
module pcie_phy_command_ctrl #(
    parameter integer GOLDEN_RELEASE_GAP_CYCLES = 2_500,
    parameter integer RATE_TIMEOUT_CYCLES = 1_000_000,
    parameter integer GEN3_TX_SETTLE_CYCLES = 32,
    parameter integer EQ_TIMEOUT_CYCLES = 1_000_000,
    // K15 reversible A/B knobs.  The production default follows the PG239
    // Figure-1 canonical preset/query sequence; Query can be disabled for a
    // controlled preset-only comparison.
    parameter integer K15_AB_CDR_HOLD = 0,
    parameter integer K15_AB_PRERATE_TXEQ = 1,
    parameter integer K15_AB_PRERATE_QUERY = 1,
    parameter integer K15_AB_PRERATE_DWELL_CYCLES = 0,
    parameter integer K15_AB_PRERATE_PRESET = 4
) (
    input  wire        phy_pclk,
    input  wire        pipe_rst_n,

    input  wire [2:0]  cmd_profile,
    input  wire        op_valid,
    input  wire        op_kind,
    output wire        op_ready,
    output wire        op_done,
    output wire [1:0]  op_result,

    // Recovery.Speed semantic transaction.  The requester owns protocol
    // policy/timeouts; this block owns the complete raw PHY rate envelope.
    input  wire        rate_req_valid,
    input  wire [1:0]  rate_req_target,
    input  wire        prerate_preset_valid,
    input  wire [3:0]  prerate_preset,
    input  wire        rate_abort,
    output wire        rate_req_ready,
    output wire        rate_busy,
    output wire        rate_done,
    output wire [2:0]  rate_result,
    output wire [1:0]  active_rate,
    output wire [3:0]  rate_state,
    output wire        prerate_query_valid,
    output wire [17:0] prerate_query_coeff,

    // K15 semantic equalization request.  The protocol controller chooses the
    // operation; this block remains the sole owner of the raw PG239 pins.
    // 0=TX preset, 1=TX coefficient, 2=TX query, 3=RX adapt, 4=RX bypass.
    input  wire        eq_req_valid,
    input  wire [2:0]  eq_req_kind,
    input  wire [3:0]  eq_req_preset,
    input  wire [17:0] eq_req_coeff,
    output wire        eq_req_ready,
    output wire        eq_busy,
    output wire        eq_done,
    // 0=none, 1=success, 2=new RX proposal, 3=timeout,
    // 4=illegal request, 5=aborted.
    output wire [2:0]  eq_result,
    output wire        eq_rsp_preset_sel,
    output wire [17:0] eq_rsp_coeff,

    input  wire        phy_phystatus,
    input  wire [2:0]  phy_rxstatus,
    input  wire [5:0]  phy_txeq_fs,
    input  wire [5:0]  phy_txeq_lf,
    input  wire [17:0] phy_txeq_new_coeff,
    input  wire        phy_txeq_done,
    input  wire        phy_rxeq_preset_sel,
    input  wire [17:0] phy_rxeq_new_txcoeff,
    input  wire        phy_rxeq_adapt_done,
    input  wire        phy_rxeq_done,

    output reg  [1:0]  phy_powerdown,
    output reg         phy_txdetectrx,
    output reg         phy_txelecidle,
    output reg  [1:0]  phy_rate,
    output reg  [1:0]  phy_txeq_ctrl,
    output reg  [3:0]  phy_txeq_preset,
    output reg  [5:0]  phy_txeq_coeff,
    output reg  [1:0]  phy_rxeq_ctrl,
    output reg  [3:0]  phy_rxeq_txpreset,
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

    localparam [1:0] RATE_GEN1 = 2'b00;
    localparam [1:0] RATE_GEN3 = 2'b10;
    localparam [2:0] RATE_RESULT_NONE = 3'd0;
    localparam [2:0] RATE_RESULT_SUCCESS = 3'd1;
    localparam [2:0] RATE_RESULT_ILLEGAL = 3'd2;
    localparam [2:0] RATE_RESULT_PHYSTATUS_TIMEOUT = 3'd3;
    localparam [2:0] RATE_RESULT_ABORTED = 3'd4;

    localparam [3:0] RATE_STABLE = 4'd0;
    localparam [3:0] RATE_RELEASE = 4'd1;
    localparam [3:0] RATE_GOLDEN_GAP = 4'd2;
    localparam [3:0] RATE_APPLY = 4'd3;
    localparam [3:0] RATE_WAIT_PHYSTATUS = 4'd4;
    localparam [3:0] RATE_GEN3_SETTLE = 4'd5;
    localparam [3:0] RATE_COMPLETE = 4'd6;
    localparam [3:0] RATE_ERROR_HOLD = 4'd7;
    localparam [3:0] RATE_PRERATE_EQ = 4'd8;
    localparam [3:0] RATE_PRERATE_CLEAR = 4'd9;
    localparam [3:0] RATE_PRERATE_QUERY = 4'd10;
    localparam [3:0] RATE_PRERATE_QUERY_CLEAR = 4'd11;

    localparam [2:0] EQ_TX_PRESET = 3'd0;
    localparam [2:0] EQ_TX_COEFF  = 3'd1;
    localparam [2:0] EQ_TX_QUERY  = 3'd2;
    localparam [2:0] EQ_RX_ADAPT  = 3'd3;
    localparam [2:0] EQ_RX_BYPASS = 3'd4;
    localparam [2:0] EQ_RESULT_NONE = 3'd0;
    localparam [2:0] EQ_RESULT_SUCCESS = 3'd1;
    localparam [2:0] EQ_RESULT_PROPOSAL = 3'd2;
    localparam [2:0] EQ_RESULT_TIMEOUT = 3'd3;
    localparam [2:0] EQ_RESULT_ILLEGAL = 3'd4;
    localparam [2:0] EQ_RESULT_ABORTED = 3'd5;

    localparam integer GAP_LIMIT =
        (GOLDEN_RELEASE_GAP_CYCLES < 1) ? 1 : GOLDEN_RELEASE_GAP_CYCLES;
    localparam integer TIMEOUT_LIMIT =
        (RATE_TIMEOUT_CYCLES < 1) ? 1 : RATE_TIMEOUT_CYCLES;
    localparam integer SETTLE_LIMIT =
        (GEN3_TX_SETTLE_CYCLES < 1) ? 1 : GEN3_TX_SETTLE_CYCLES;
    localparam integer EQ_TIMEOUT_LIMIT =
        (EQ_TIMEOUT_CYCLES < 1) ? 1 : EQ_TIMEOUT_CYCLES;
    localparam [3:0] PRERATE_FALLBACK_PRESET =
        (K15_AB_PRERATE_PRESET <= 10) ? K15_AB_PRERATE_PRESET[3:0] : 4'd4;

    function automatic prerate_dwell_expired(input [31:0] count);
        integer signed dwell_last;
        begin
            dwell_last = K15_AB_PRERATE_DWELL_CYCLES - 1;
            prerate_dwell_expired = (dwell_last <= 0) ||
                                    (count >= dwell_last);
        end
    endfunction

    reg [3:0] rate_state_r;
    reg [1:0] active_rate_r;
    reg [1:0] target_rate_r;
    reg [31:0] gap_count_r;
    reg [31:0] timeout_count_r;
    reg [31:0] settle_count_r;
    reg [31:0] prerate_count_r;
    reg prerate_txeq_seen_r;
    reg [3:0] prerate_preset_r;
    reg prerate_query_valid_r;
    reg [17:0] prerate_query_coeff_r;
    reg phy_phystatus_q;
    reg rate_done_r;
    reg [2:0] rate_result_r;
    reg phy_txeq_done_q, phy_rxeq_done_q;
    reg eq_busy_r, eq_done_r;
    reg [2:0] eq_kind_r, eq_result_r;
    reg [3:0] eq_preset_r;
    reg [17:0] eq_coeff_r, eq_rsp_coeff_r;
    reg eq_rsp_preset_sel_r;
    reg [1:0] eq_coeff_cycle_r;
    reg [31:0] eq_timeout_count_r;
`ifndef SYNTHESIS
    reg phy_txelecidle_q;
`endif

    wire phystatus_rising = phy_phystatus && !phy_phystatus_q;
    wire txeq_done_rising = phy_txeq_done && !phy_txeq_done_q;
    wire rxeq_done_rising = phy_rxeq_done && !phy_rxeq_done_q;
    wire rate_envelope_active = (rate_state_r != RATE_STABLE);

    // The controller is always able to accept the profile selected for the
    // current LTSSM state.  Completion deliberately uses the current
    // PhyStatus beat; no completion pipeline is inserted at this boundary.
    assign op_ready = pipe_rst_n && !rate_envelope_active && !eq_busy_r;
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
                // K02 Golden keeps the CDR hold assist deasserted before and
                // throughout a Gen1->Gen3 rate transaction.
                as_cdr_hold_req = 1'b0;
            end
            default: begin
                // Polling, Configuration, Recovery, L0 and Hot Reset use
                // the active Gen1 P0 profile.
            end
        endcase

        // Golden Recovery.Speed envelope overrides only the semantic profile
        // mapping.  P0 is maintained, TX is held in Electrical Idle, Detect
        // assist and CDR hold are both disabled through completion.  This is
        // intentionally different from the retired K13 replay envelope.
        if (rate_envelope_active) begin
            phy_powerdown = 2'b00;
            phy_txdetectrx = 1'b0;
            phy_txelecidle = 1'b1;
            as_mac_in_detect = 1'b0;
            as_cdr_hold_req = (K15_AB_CDR_HOLD != 0);
        end
    end

    // Raw PHY_RATE changes only inside this controller.  The 10 us Golden
    // release gap holds the committed rate; APPLY/WAIT/SETTLE then hold the
    // requested rate continuously through PhyStatus completion.
    always @* begin
        case (rate_state_r)
            RATE_APPLY, RATE_WAIT_PHYSTATUS, RATE_GEN3_SETTLE,
            RATE_COMPLETE, RATE_ERROR_HOLD:
                phy_rate = target_rate_r;
            default:
                phy_rate = active_rate_r;
        endcase
    end

    assign rate_req_ready = pipe_rst_n && (rate_state_r == RATE_STABLE) &&
                            !eq_busy_r;
    assign rate_busy = rate_envelope_active;
    assign rate_done = rate_done_r;
    assign rate_result = rate_result_r;
    assign active_rate = active_rate_r;
    assign rate_state = rate_state_r;
    assign prerate_query_valid = prerate_query_valid_r;
    assign prerate_query_coeff = prerate_query_coeff_r;
    assign eq_req_ready = pipe_rst_n && (rate_state_r == RATE_STABLE) &&
                          !eq_busy_r && !rate_req_valid;
    assign eq_busy = eq_busy_r;
    assign eq_done = eq_done_r;
    assign eq_result = eq_result_r;
    assign eq_rsp_preset_sel = eq_rsp_preset_sel_r;
    assign eq_rsp_coeff = eq_rsp_coeff_r;

    // Raw EQ pins are centralized here.  Recovery.Speed drives only the
    // selected canonical preset/query waveform; post-rate operations arrive
    // through the semantic Equalization request interface below.
    always @* begin
        phy_txeq_ctrl = 2'b00;
        phy_txeq_preset = 4'd0;
        phy_txeq_coeff = 6'd0;
        phy_rxeq_ctrl = 2'b00;
        phy_rxeq_txpreset = 4'd0;
        if ((rate_state_r == RATE_PRERATE_EQ) &&
            (target_rate_r == RATE_GEN3) &&
            (K15_AB_PRERATE_TXEQ != 0)) begin
            phy_txeq_ctrl = 2'b01;
            phy_txeq_preset = prerate_preset_r;
        end else if ((rate_state_r == RATE_PRERATE_QUERY) &&
                     (target_rate_r == RATE_GEN3) &&
                     (K15_AB_PRERATE_TXEQ != 0) &&
                     (K15_AB_PRERATE_QUERY != 0)) begin
            phy_txeq_ctrl = 2'b11;
        end else if (eq_busy_r) begin
            case (eq_kind_r)
                EQ_TX_PRESET: begin
                    phy_txeq_ctrl = 2'b01;
                    phy_txeq_preset = eq_preset_r;
                end
                EQ_TX_COEFF: begin
                    phy_txeq_ctrl = 2'b10;
                    case (eq_coeff_cycle_r)
                        2'd0: phy_txeq_coeff = eq_coeff_r[17:12];
                        2'd1: phy_txeq_coeff = eq_coeff_r[11:6];
                        default: phy_txeq_coeff = eq_coeff_r[5:0];
                    endcase
                end
                EQ_TX_QUERY: phy_txeq_ctrl = 2'b11;
                EQ_RX_ADAPT: begin
                    phy_rxeq_ctrl = 2'b10;
                    phy_rxeq_txpreset = eq_preset_r;
                end
                EQ_RX_BYPASS: begin
                    phy_rxeq_ctrl = 2'b11;
                    phy_rxeq_txpreset = eq_preset_r;
                end
                default: begin end
            endcase
        end
    end

    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            rate_state_r <= RATE_STABLE;
            active_rate_r <= RATE_GEN1;
            target_rate_r <= RATE_GEN1;
            gap_count_r <= 32'd0;
            timeout_count_r <= 32'd0;
            settle_count_r <= 32'd0;
            prerate_count_r <= 32'd0;
            prerate_txeq_seen_r <= 1'b0;
            prerate_preset_r <= PRERATE_FALLBACK_PRESET;
            prerate_query_valid_r <= 1'b0;
            prerate_query_coeff_r <= 18'd0;
            phy_phystatus_q <= 1'b0;
            rate_done_r <= 1'b0;
            rate_result_r <= RATE_RESULT_NONE;
            phy_txeq_done_q <= 1'b0;
            phy_rxeq_done_q <= 1'b0;
            eq_busy_r <= 1'b0;
            eq_done_r <= 1'b0;
            eq_kind_r <= EQ_TX_PRESET;
            eq_result_r <= EQ_RESULT_NONE;
            eq_preset_r <= 4'd0;
            eq_coeff_r <= 18'd0;
            eq_rsp_coeff_r <= 18'd0;
            eq_rsp_preset_sel_r <= 1'b0;
            eq_coeff_cycle_r <= 2'd0;
            eq_timeout_count_r <= 32'd0;
        end else if (rate_abort) begin
            // PERST/hot-reset/link-loss recovery always returns to the signed
            // Gen1 command baseline; no in-flight transaction is retried.
            rate_state_r <= RATE_STABLE;
            active_rate_r <= RATE_GEN1;
            target_rate_r <= RATE_GEN1;
            gap_count_r <= 32'd0;
            timeout_count_r <= 32'd0;
            settle_count_r <= 32'd0;
            prerate_count_r <= 32'd0;
            prerate_txeq_seen_r <= 1'b0;
            prerate_preset_r <= PRERATE_FALLBACK_PRESET;
            prerate_query_valid_r <= 1'b0;
            prerate_query_coeff_r <= 18'd0;
            phy_phystatus_q <= phy_phystatus;
            rate_done_r <= rate_envelope_active;
            rate_result_r <= rate_envelope_active ? RATE_RESULT_ABORTED :
                                                    RATE_RESULT_NONE;
            phy_txeq_done_q <= phy_txeq_done;
            phy_rxeq_done_q <= phy_rxeq_done;
            eq_done_r <= eq_busy_r;
            eq_result_r <= eq_busy_r ? EQ_RESULT_ABORTED : EQ_RESULT_NONE;
            eq_busy_r <= 1'b0;
            eq_coeff_cycle_r <= 2'd0;
            eq_timeout_count_r <= 32'd0;
        end else begin
            phy_phystatus_q <= phy_phystatus;
            phy_txeq_done_q <= phy_txeq_done;
            phy_rxeq_done_q <= phy_rxeq_done;
            rate_done_r <= 1'b0;
            rate_result_r <= RATE_RESULT_NONE;
            eq_done_r <= 1'b0;
            eq_result_r <= EQ_RESULT_NONE;
            case (rate_state_r)
                RATE_STABLE: begin
                    gap_count_r <= 32'd0;
                    timeout_count_r <= 32'd0;
                    settle_count_r <= 32'd0;
                    prerate_count_r <= 32'd0;
                    prerate_txeq_seen_r <= 1'b0;
                    if (rate_req_valid && rate_req_ready) begin
                        if ((rate_req_target == 2'b11) ||
                            (rate_req_target == 2'b01)) begin
                            // Phase D admits only Gen1 and Gen3.  Gen2 and the
                            // reserved encoding are explicit semantic errors.
                            rate_done_r <= 1'b1;
                            rate_result_r <= RATE_RESULT_ILLEGAL;
                        end else if (rate_req_target == active_rate_r) begin
                            rate_done_r <= 1'b1;
                            rate_result_r <= RATE_RESULT_SUCCESS;
                        end else begin
                            target_rate_r <= rate_req_target;
                            if (rate_req_target == RATE_GEN3) begin
                                prerate_preset_r <=
                                    prerate_preset_valid &&
                                    (prerate_preset <= 4'd10) ?
                                    prerate_preset :
                                    PRERATE_FALLBACK_PRESET;
                                prerate_query_valid_r <= 1'b0;
                                prerate_query_coeff_r <= 18'd0;
                            end
                            rate_state_r <= RATE_RELEASE;
                            timeout_count_r <= 32'd0;
                        end
                    end
                end
                RATE_RELEASE: begin
                    gap_count_r <= 32'd0;
                    rate_state_r <= RATE_GOLDEN_GAP;
                end
                RATE_GOLDEN_GAP: begin
                    if (gap_count_r >= (GAP_LIMIT - 1)) begin
                        gap_count_r <= 32'd0;
                        prerate_count_r <= 32'd0;
                        prerate_txeq_seen_r <= 1'b0;
                        if ((target_rate_r == RATE_GEN3) &&
                            ((K15_AB_PRERATE_TXEQ != 0) ||
                             (K15_AB_PRERATE_DWELL_CYCLES > 0)))
                            rate_state_r <= RATE_PRERATE_EQ;
                        else
                            rate_state_r <= RATE_APPLY;
                    end else begin
                        gap_count_r <= gap_count_r + 1'b1;
                    end
                end
                RATE_PRERATE_EQ: begin
                    // Optional experiment window.  A0/A1 can use the same
                    // dwell without driving TXEQ, separating a preset effect
                    // from a pure pre-rate timing effect.  TXEQ_DONE must be
                    // a fresh edge when the TXEQ option is enabled.
                    if (txeq_done_rising)
                        prerate_txeq_seen_r <= 1'b1;
                    if (((K15_AB_PRERATE_TXEQ == 0) ||
                         prerate_txeq_seen_r || txeq_done_rising) &&
                        prerate_dwell_expired(prerate_count_r)) begin
                        timeout_count_r <= 32'd0;
                        rate_state_r <= RATE_PRERATE_CLEAR;
                    end else if (timeout_count_r >= (TIMEOUT_LIMIT - 1)) begin
                        rate_done_r <= 1'b1;
                        rate_result_r <= RATE_RESULT_PHYSTATUS_TIMEOUT;
                        rate_state_r <= RATE_ERROR_HOLD;
                    end else begin
                        timeout_count_r <= timeout_count_r + 1'b1;
                        if (!prerate_dwell_expired(prerate_count_r))
                            prerate_count_r <= prerate_count_r + 1'b1;
                    end
                end
                RATE_PRERATE_CLEAR: begin
                    // One explicit Gen1/P0 cycle clears preset apply before
                    // either the canonical query or the rate change.
                    timeout_count_r <= 32'd0;
                    prerate_txeq_seen_r <= 1'b0;
                    rate_state_r <= ((K15_AB_PRERATE_TXEQ != 0) &&
                                     (K15_AB_PRERATE_QUERY != 0)) ?
                                    RATE_PRERATE_QUERY : RATE_APPLY;
                end
                RATE_PRERATE_QUERY: begin
                    if (txeq_done_rising) begin
                        prerate_query_coeff_r <= phy_txeq_new_coeff;
                        prerate_query_valid_r <= 1'b1;
                        timeout_count_r <= 32'd0;
                        rate_state_r <= RATE_PRERATE_QUERY_CLEAR;
                    end else if (timeout_count_r >= (TIMEOUT_LIMIT - 1)) begin
                        rate_done_r <= 1'b1;
                        rate_result_r <= RATE_RESULT_PHYSTATUS_TIMEOUT;
                        rate_state_r <= RATE_ERROR_HOLD;
                    end else begin
                        timeout_count_r <= timeout_count_r + 1'b1;
                    end
                end
                RATE_PRERATE_QUERY_CLEAR: begin
                    // A second explicit idle command beat separates Query
                    // completion from PHY_RATE changing to the new speed.
                    timeout_count_r <= 32'd0;
                    rate_state_r <= RATE_APPLY;
                end
                RATE_APPLY: begin
                    timeout_count_r <= 32'd0;
                    rate_state_r <= RATE_WAIT_PHYSTATUS;
                end
                RATE_WAIT_PHYSTATUS: begin
                    if (phystatus_rising) begin
                        timeout_count_r <= 32'd0;
                        settle_count_r <= 32'd0;
                        rate_state_r <= (target_rate_r == RATE_GEN3) ?
                                        RATE_GEN3_SETTLE : RATE_COMPLETE;
                    end else if (timeout_count_r >= (TIMEOUT_LIMIT - 1)) begin
                        rate_done_r <= 1'b1;
                        rate_result_r <= RATE_RESULT_PHYSTATUS_TIMEOUT;
                        rate_state_r <= RATE_ERROR_HOLD;
                    end else begin
                        timeout_count_r <= timeout_count_r + 1'b1;
                    end
                end
                RATE_GEN3_SETTLE: begin
                    if (settle_count_r >= (SETTLE_LIMIT - 1)) begin
                        settle_count_r <= 32'd0;
                        rate_state_r <= RATE_COMPLETE;
                    end else begin
                        settle_count_r <= settle_count_r + 1'b1;
                    end
                end
                RATE_COMPLETE: begin
                    active_rate_r <= target_rate_r;
                    rate_done_r <= 1'b1;
                    rate_result_r <= RATE_RESULT_SUCCESS;
                    rate_state_r <= RATE_STABLE;
                end
                RATE_ERROR_HOLD: begin
                    // Preserve the failed raw target and Golden TXEI envelope
                    // for traceability. rate_abort or PIPE reset is the only
                    // safe return to the Gen1 baseline.
                    rate_state_r <= RATE_ERROR_HOLD;
                end
                default: begin
                    rate_state_r <= RATE_STABLE;
                    active_rate_r <= RATE_GEN1;
                    target_rate_r <= RATE_GEN1;
                end
            endcase

            // Post-rate semantic EQ executor.  Rate requests have admission
            // priority, and an active rate envelope prevents new EQ work.
            if (!eq_busy_r) begin
                eq_timeout_count_r <= 32'd0;
                eq_coeff_cycle_r <= 2'd0;
                if (eq_req_valid && eq_req_ready) begin
                    if (eq_req_kind > EQ_RX_BYPASS ||
                        ((eq_req_kind == EQ_TX_PRESET ||
                          eq_req_kind == EQ_RX_ADAPT ||
                          eq_req_kind == EQ_RX_BYPASS) &&
                         (eq_req_preset > 4'd10))) begin
                        eq_done_r <= 1'b1;
                        eq_result_r <= EQ_RESULT_ILLEGAL;
                    end else begin
                        eq_busy_r <= 1'b1;
                        eq_kind_r <= eq_req_kind;
                        eq_preset_r <= eq_req_preset;
                        eq_coeff_r <= eq_req_coeff;
                    end
                end
            end else begin
                if ((eq_kind_r == EQ_TX_COEFF) &&
                    (eq_coeff_cycle_r < 2'd2))
                    eq_coeff_cycle_r <= eq_coeff_cycle_r + 1'b1;

                if (((eq_kind_r <= EQ_TX_QUERY) && txeq_done_rising) ||
                    ((eq_kind_r >= EQ_RX_ADAPT) && rxeq_done_rising)) begin
                    eq_busy_r <= 1'b0;
                    eq_done_r <= 1'b1;
                    eq_timeout_count_r <= 32'd0;
                    if (eq_kind_r == EQ_TX_QUERY) begin
                        eq_rsp_coeff_r <= phy_txeq_new_coeff;
                        eq_result_r <= EQ_RESULT_SUCCESS;
                    end else if (eq_kind_r >= EQ_RX_ADAPT) begin
                        eq_rsp_preset_sel_r <= phy_rxeq_preset_sel;
                        eq_rsp_coeff_r <= phy_rxeq_new_txcoeff;
                        eq_result_r <= phy_rxeq_adapt_done ?
                                       EQ_RESULT_SUCCESS : EQ_RESULT_PROPOSAL;
                    end else begin
                        eq_result_r <= EQ_RESULT_SUCCESS;
                    end
                end else if (eq_timeout_count_r >=
                             (EQ_TIMEOUT_LIMIT - 1)) begin
                    eq_busy_r <= 1'b0;
                    eq_done_r <= 1'b1;
                    eq_result_r <= EQ_RESULT_TIMEOUT;
                    eq_timeout_count_r <= 32'd0;
                end else begin
                    eq_timeout_count_r <= eq_timeout_count_r + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // RATE_RELEASE plus RATE_GOLDEN_GAP is the explicit TXEI lead.  Keep this
    // assertion at the raw-pin owner so later state refactors cannot make the
    // preset command appear on the same first beat as Electrical Idle.
    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            phy_txelecidle_q <= 1'b0;
        end else begin
            if ((rate_state_r == RATE_PRERATE_EQ) &&
                (K15_AB_PRERATE_TXEQ != 0))
                assert (phy_txelecidle_q)
                    else $error("K15_PRERATE_TXEI_LEAD_VIOLATION");
            if ((rate_state_r == RATE_PRERATE_QUERY) && txeq_done_rising)
                $display("K15_PRERATE_QUERY raw=%05x pre=%0d main=%0d post=%0d",
                         phy_txeq_new_coeff,
                         phy_txeq_new_coeff[17:12],
                         phy_txeq_new_coeff[11:6],
                         phy_txeq_new_coeff[5:0]);
            phy_txelecidle_q <= phy_txelecidle;
        end
    end
`endif

    // Compliance, polarity, margin, swing and deemphasis retain centralized
    // safe values. Equalization controls above now share the same raw owner.
    assign phy_txcompliance = 1'b0;
    assign phy_rxpolarity = 1'b0;
    assign phy_txmargin = 3'b000;
    assign phy_txswing = 1'b0;
    assign phy_txdeemph = 1'b0;

    wire _unused = &{1'b0, PROFILE_ACTIVE, RATE_GEN1, phy_txeq_fs,
                     phy_txeq_lf};
endmodule

`default_nettype wire
