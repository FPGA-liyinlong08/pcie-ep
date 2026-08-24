`timescale 1ns/1ps
`default_nettype none

// K02 rate-change event recorder.
//
// The recorder keeps timestamps relative to the latest real Gen3 rate-change
// start. It intentionally does not decide PASS/FAIL; software/ILA can compare
// the timestamps of QPLL lock, PhyStatus and bring-up states from one run.
module k02_phy_event_recorder (
    input  wire        clk,
    input  wire        rst,
    input  wire        qpll1lock,
    input  wire        qpll1reset,
    input  wire [1:0]  phy_rate,
    input  wire        phy_phystatus,
    input  wire [3:0]  seq_state,
    output wire [117:0] record_bus
);

    logic        qpll1lock_d;
    logic        qpll1reset_d;
    logic [1:0]  phy_rate_d;
    logic        phy_phystatus_d;
    logic [3:0]  seq_state_d;
    logic        active;
    logic [15:0] elapsed;
    logic [5:0]  valid;
    logic [15:0] qpll_lock_fall_ts;
    logic [15:0] qpll_lock_rise_ts;
    logic [15:0] qpll_lock_reloss_ts;
    logic [15:0] phystatus_rise_ts;
    logic [15:0] gen3_wait_ts;
    logic [15:0] done_ts;

    // Start at the earliest Gen3 indication (rate command or sequence entry),
    // before the GT necessarily asserts QPLL1RESET.  The QPLL reset edge is a
    // fallback for a wrapper that does not expose either earlier indication.
    // Once active, later reset pulses must not erase the first transition log.
    wire start_evt = !active &&
                     (((phy_rate == 2'b10) && (phy_rate_d != 2'b10)) ||
                      ((seq_state == 4'd6) && (seq_state_d != 4'd6)) ||
                      (qpll1reset && !qpll1reset_d &&
                       ((phy_rate == 2'b10) || (seq_state == 4'd6))));

    always_ff @(posedge clk) begin
        if (rst) begin
            qpll1lock_d       <= 1'b0;
            qpll1reset_d      <= 1'b0;
            phy_rate_d        <= 2'b00;
            phy_phystatus_d   <= 1'b0;
            seq_state_d       <= 4'd0;
            active            <= 1'b0;
            elapsed           <= 16'd0;
            valid             <= 6'd0;
            qpll_lock_fall_ts <= 16'd0;
            qpll_lock_rise_ts <= 16'd0;
            qpll_lock_reloss_ts <= 16'd0;
            phystatus_rise_ts <= 16'd0;
            gen3_wait_ts      <= 16'd0;
            done_ts           <= 16'd0;
        end else begin
            qpll1lock_d     <= qpll1lock;
            qpll1reset_d    <= qpll1reset;
            phy_rate_d      <= phy_rate;
            phy_phystatus_d <= phy_phystatus;
            seq_state_d     <= seq_state;

            if (start_evt) begin
                active  <= 1'b1;
                elapsed <= 16'd0;
                valid   <= 6'd0;
                qpll_lock_fall_ts <= 16'd0;
                qpll_lock_rise_ts <= 16'd0;
                qpll_lock_reloss_ts <= 16'd0;
                phystatus_rise_ts <= 16'd0;
                gen3_wait_ts      <= 16'd0;
                done_ts           <= 16'd0;
                // If lock is already low at the start edge, record that
                // fact as the first observed lock-loss event.
                if (!qpll1lock) begin
                    valid[0] <= 1'b1;
                    qpll_lock_fall_ts <= 16'd0;
                end
                if (seq_state == 4'd6) begin
                    valid[4] <= 1'b1;
                    gen3_wait_ts <= 16'd0;
                end
            end else if (active) begin
                if (!valid[0] && qpll1lock_d && !qpll1lock) begin
                    valid[0] <= 1'b1;
                    qpll_lock_fall_ts <= elapsed;
                end
                if (valid[0] && !valid[1] && !qpll1lock_d && qpll1lock) begin
                    valid[1] <= 1'b1;
                    qpll_lock_rise_ts <= elapsed;
                end
                if (valid[1] && !valid[2] && qpll1lock_d && !qpll1lock) begin
                    valid[2] <= 1'b1;
                    qpll_lock_reloss_ts <= elapsed;
                end
                if (!valid[3] && !phy_phystatus_d && phy_phystatus) begin
                    valid[3] <= 1'b1;
                    phystatus_rise_ts <= elapsed;
                end
                if (!valid[4] && seq_state_d != 4'd6 && seq_state == 4'd6) begin
                    valid[4] <= 1'b1;
                    gen3_wait_ts <= elapsed;
                end
                if (!valid[5] && seq_state_d != 4'd8 && seq_state == 4'd8) begin
                    valid[5] <= 1'b1;
                    done_ts <= elapsed;
                end
                elapsed <= elapsed + 1'b1;
            end
        end
    end

    // [117:102] elapsed, [101:86] QPLL fall, [85:70] QPLL rise,
    // [69:54] QPLL re-loss, [53:38] PhyStatus rise,
    // [37:22] S_GEN3_WAIT, [21:6] S_DONE, [5:0] valid flags.
    assign record_bus = {elapsed, qpll_lock_fall_ts, qpll_lock_rise_ts,
                         qpll_lock_reloss_ts, phystatus_rise_ts,
                         gen3_wait_ts, done_ts, valid};

endmodule

`default_nettype wire
