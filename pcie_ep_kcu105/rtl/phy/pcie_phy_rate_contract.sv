`timescale 1ns/1ps
`default_nettype none

// K13 PHY rate contract.  This is the only owner of the raw PHY_RATE command.
// The protocol side submits a semantic request and observes a completion result;
// it never infers completion from the command value itself.
module pcie_phy_rate_contract #(
    parameter integer RATE_TIMEOUT_CYCLES     = 1_000_000,
    parameter integer GEN1_RELEASE_GAP_CYCLES = 2500,
    // The generated PCIe PHY does not expose GT_PCIEUSERGEN3RDY on its
    // public PIPE interface.  In the UltraScale model PhyStatus precedes
    // that internal ready indication by several PCLKs.  Keep TxElecIdle
    // asserted long enough that the first EIEOS/SDS is not consumed while
    // the Gen3 transmitter is still starting.
    parameter integer GEN3_TX_SETTLE_CYCLES   = 32
) (
    input  wire       clk,
    input  wire       rst_n,
    // link_ready seeds the contract after K11 reaches its first L0.  It is
    // intentionally not used as a live Recovery gate.
    input  wire       link_ready,
    // Assert while LTSSM is back in Detect/PHY bring-up.  This resets the
    // physical-rate context to Gen1 without requiring a PIPE reset.
    input  wire       reinitialize_gen1,

    input  wire       rate_req_valid,
    input  wire [1:0] rate_req_target,
    input  wire       fallback_req,
    output wire       rate_req_ready,
    input  wire       phy_phystatus,

    output reg  [1:0] phy_rate_cmd,
    output reg        force_txelecidle,
    output wire [1:0] active_rate,
    output wire       rate_busy,
    // Both result signals are one-cycle pulses.  timeout_sticky is the
    // persistent diagnostic; rate_failed is not sticky.
    output wire       rate_done,
    output wire       rate_failed,

    output wire [3:0] dbg_state,
    output wire       phystatus_seen,
    output wire       timeout_sticky,
    output wire       illegal_target_sticky
);
    localparam [1:0] RATE_GEN1 = 2'b00;
    localparam [1:0] RATE_RESERVED = 2'b11;

    localparam [3:0] RC_DISABLED       = 4'h0;
    localparam [3:0] RC_RDY2_STABLE    = 4'h4;
    localparam [3:0] RC_RELEASE_RDY3   = 4'h5;
    localparam [3:0] RC_RDY0_GAP       = 4'h2;
    localparam [3:0] RC_APPLY_RDY1     = 4'h3;
    localparam [3:0] RC_WAIT_PHYSTATUS = 4'hA;
    localparam [3:0] RC_COMMIT_RDY2    = 4'hB;
    localparam [3:0] RC_FALLBACK_WAIT  = 4'hC;
    localparam [3:0] RC_NOOP_DONE      = 4'hD;
    localparam [3:0] RC_GEN3_TX_SETTLE = 4'h6;
    localparam [3:0] RC_ERROR          = 4'hF;

    localparam integer TIMEOUT_LIMIT =
        (RATE_TIMEOUT_CYCLES < 1) ? 1 : RATE_TIMEOUT_CYCLES;
    localparam integer GAP_LIMIT =
        (GEN1_RELEASE_GAP_CYCLES < 1) ? 1 : GEN1_RELEASE_GAP_CYCLES;
    localparam integer GEN3_SETTLE_LIMIT =
        (GEN3_TX_SETTLE_CYCLES < 1) ? 1 : GEN3_TX_SETTLE_CYCLES;

    reg [3:0]  state_r;
    reg [1:0]  active_rate_r;
    reg [1:0]  target_rate_r;
    reg        initialized_r;
    reg [31:0] gap_count_r;
    reg [31:0] timeout_count_r;
    reg        phystatus_seen_r;
    reg        phystatus_prev_r;
    reg        phystatus_pulse_r;
    reg        rate_done_pulse_r;
    reg        rate_failed_pulse_r;
    reg        timeout_sticky_r;
    reg        illegal_target_sticky_r;

    wire legal_target = (rate_req_target != RATE_RESERVED);
    wire same_rate = (rate_req_target == active_rate_r);
    wire timeout_expired = timeout_count_r >= (TIMEOUT_LIMIT - 1);
    wire gap_expired = gap_count_r >= (GAP_LIMIT - 1);
    wire phystatus_rising = phy_phystatus && !phystatus_prev_r;

    // Once initial L0 has been observed, Recovery may safely hold the
    // contract ready even though LTSSM's link_up output is low.
    assign rate_req_ready = initialized_r &&
                            ((state_r == RC_RDY2_STABLE) ||
                             (state_r == RC_ERROR));

    always @* begin
        case (state_r)
            RC_APPLY_RDY1, RC_WAIT_PHYSTATUS, RC_COMMIT_RDY2,
            RC_GEN3_TX_SETTLE, RC_FALLBACK_WAIT, RC_ERROR:
                phy_rate_cmd = target_rate_r;
            default:
                phy_rate_cmd = active_rate_r;
        endcase
    end

    always @* begin
        force_txelecidle = (state_r == RC_RELEASE_RDY3) ||
                           (state_r == RC_RDY0_GAP) ||
                           (state_r == RC_APPLY_RDY1) ||
                           (state_r == RC_WAIT_PHYSTATUS) ||
                           (state_r == RC_GEN3_TX_SETTLE) ||
                           (state_r == RC_COMMIT_RDY2) ||
                           (state_r == RC_FALLBACK_WAIT) ||
                           (state_r == RC_ERROR);
    end

    assign active_rate = active_rate_r;
    assign rate_busy = (state_r != RC_DISABLED) &&
                       (state_r != RC_RDY2_STABLE);
    assign rate_done = rate_done_pulse_r;
    assign rate_failed = rate_failed_pulse_r;
    assign dbg_state = state_r;
    assign phystatus_seen = phystatus_pulse_r | phystatus_rising;
    assign timeout_sticky = timeout_sticky_r;
    assign illegal_target_sticky = illegal_target_sticky_r;

`ifndef SYNTHESIS
    // Contract invariants are checked one clock after NBA updates so the
    // assertions observe the externally visible result pulse together with
    // the committed active rate.
    reg [1:0] active_rate_assert_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || reinitialize_gen1) begin
            active_rate_assert_q <= RATE_GEN1;
        end else begin
            if (rate_done_pulse_r && rate_failed_pulse_r)
                $error("Rate Contract emitted done and failed together");
            if ((active_rate_r != active_rate_assert_q) &&
                !rate_done_pulse_r)
                $error("active_rate changed without rate_done");
            active_rate_assert_q <= active_rate_r;
        end
    end
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r                 <= RC_DISABLED;
            active_rate_r           <= RATE_GEN1;
            target_rate_r           <= RATE_GEN1;
            initialized_r           <= 1'b0;
            gap_count_r             <= 32'd0;
            timeout_count_r         <= 32'd0;
            phystatus_seen_r        <= 1'b0;
            phystatus_prev_r        <= 1'b0;
            phystatus_pulse_r       <= 1'b0;
            rate_done_pulse_r       <= 1'b0;
            rate_failed_pulse_r     <= 1'b0;
            timeout_sticky_r        <= 1'b0;
            illegal_target_sticky_r <= 1'b0;
        end else if (reinitialize_gen1) begin
            state_r             <= RC_DISABLED;
            active_rate_r       <= RATE_GEN1;
            target_rate_r       <= RATE_GEN1;
            initialized_r       <= 1'b0;
            gap_count_r         <= 32'd0;
            timeout_count_r     <= 32'd0;
            phystatus_seen_r    <= 1'b0;
            phystatus_prev_r    <= 1'b0;
            phystatus_pulse_r   <= 1'b0;
            rate_done_pulse_r   <= 1'b0;
            rate_failed_pulse_r <= 1'b0;
        end else begin
            rate_done_pulse_r   <= 1'b0;
            rate_failed_pulse_r <= 1'b0;
            phystatus_pulse_r   <= 1'b0;
            phystatus_prev_r    <= phystatus_seen_r;
            phystatus_seen_r    <= phy_phystatus;

            if (link_ready)
                initialized_r <= 1'b1;

            case (state_r)
                RC_DISABLED: begin
                    gap_count_r     <= 32'd0;
                    timeout_count_r <= 32'd0;
                    if (initialized_r || link_ready)
                        state_r <= RC_RDY2_STABLE;
                end

                RC_RDY2_STABLE: begin
                    gap_count_r     <= 32'd0;
                    timeout_count_r <= 32'd0;
                    if (rate_req_valid && rate_req_ready) begin
                        if (!legal_target) begin
                            illegal_target_sticky_r <= 1'b1;
                            rate_failed_pulse_r <= 1'b1;
                            state_r <= RC_ERROR;
                        end else if (same_rate) begin
                            // Complete one cycle after acceptance so the
                            // semantic requester cannot miss the pulse.
                            state_r <= RC_NOOP_DONE;
                        end else begin
                            target_rate_r <= rate_req_target;
                            if (fallback_req)
                                state_r <= RC_FALLBACK_WAIT;
                            else
                                state_r <= RC_RELEASE_RDY3;
                        end
                    end
                end

                RC_NOOP_DONE: begin
                    rate_done_pulse_r <= 1'b1;
                    state_r <= RC_RDY2_STABLE;
                end

                RC_RELEASE_RDY3: begin
                    gap_count_r     <= 32'd0;
                    timeout_count_r <= 32'd0;
                    state_r         <= RC_RDY0_GAP;
                end

                RC_RDY0_GAP: begin
                    if (gap_expired) begin
                        gap_count_r <= 32'd0;
                        state_r     <= RC_APPLY_RDY1;
                    end else begin
                        gap_count_r <= gap_count_r + 1'b1;
                    end
                end

                RC_APPLY_RDY1: begin
                    timeout_count_r <= 32'd0;
                    state_r         <= RC_WAIT_PHYSTATUS;
                end

                RC_WAIT_PHYSTATUS: begin
                    if (phystatus_rising) begin
                        phystatus_pulse_r <= 1'b1;
                        gap_count_r <= 32'd0;
                        state_r <= (target_rate_r == 2'b10) ?
                                   RC_GEN3_TX_SETTLE : RC_COMMIT_RDY2;
                    end else if (timeout_expired) begin
                        timeout_sticky_r    <= 1'b1;
                        rate_failed_pulse_r <= 1'b1;
                        // Keep TXEI asserted and expose the failed target
                        // until the semantic layer submits Gen1 fallback.
                        state_r <= RC_ERROR;
                    end else begin
                        timeout_count_r <= timeout_count_r + 1'b1;
                    end
                end

                RC_GEN3_TX_SETTLE: begin
                    // PhyStatus acknowledges the PIPE Rate operation, but
                    // the generated GT wrapper raises PCIEUSERGEN3RDY later.
                    // active_rate remains at the old value here, which keeps
                    // the Gen3 ordered-set generator reset while TXEI is high.
                    if (gap_count_r >= (GEN3_SETTLE_LIMIT - 1)) begin
                        gap_count_r <= 32'd0;
                        state_r <= RC_COMMIT_RDY2;
                    end else begin
                        gap_count_r <= gap_count_r + 1'b1;
                    end
                end

                RC_COMMIT_RDY2: begin
                    active_rate_r     <= target_rate_r;
                    rate_done_pulse_r <= 1'b1;
                    timeout_count_r   <= 32'd0;
                    state_r           <= RC_RDY2_STABLE;
                end

                RC_FALLBACK_WAIT: begin
                    if (phystatus_rising) begin
                        phystatus_pulse_r <= 1'b1;
                        active_rate_r     <= target_rate_r;
                        rate_done_pulse_r <= 1'b1;
                        timeout_count_r   <= 32'd0;
                        state_r           <= RC_RDY2_STABLE;
                    end else if (timeout_expired) begin
                        timeout_sticky_r    <= 1'b1;
                        rate_failed_pulse_r <= 1'b1;
                        // Fatal fallback failure remains in ERROR until the
                        // LTSSM reinitializes the Gen1 context.
                        state_r <= RC_ERROR;
                    end else begin
                        timeout_count_r <= timeout_count_r + 1'b1;
                    end
                end

                RC_ERROR: begin
                    // A failed normal operation can still accept exactly the
                    // explicit Gen1 fallback request.  A second failure stays
                    // here until Detect/PHY bring-up resets the context.
                    if (rate_req_valid && rate_req_ready) begin
                        if (fallback_req && (rate_req_target == RATE_GEN1)) begin
                            target_rate_r   <= RATE_GEN1;
                            timeout_count_r <= 32'd0;
                            state_r         <= RC_FALLBACK_WAIT;
                        end else begin
                            rate_failed_pulse_r <= 1'b1;
                        end
                    end
                end

                default: state_r <= RC_DISABLED;
            endcase
        end
    end

endmodule

`default_nettype wire
