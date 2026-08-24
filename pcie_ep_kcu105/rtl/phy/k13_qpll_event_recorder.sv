`timescale 1ns/1ps
`default_nettype none

// K13 diagnostic recorder.  It records relative events without enlarging the
// ILA capture depth.  qpll1lock/qpll1reset are retargeted to the actual
// GTHE3_COMMON primitive pins by the implementation Tcl.
module k13_qpll_event_recorder (
    input  wire         clk,
    input  wire         rst,
    input  wire         qpll1lock,
    input  wire         qpll1reset,
    input  wire [1:0]   phy_rate,
    input  wire         phy_phystatus,
    input  wire         cdr_hold,
    input  wire         pcierategen3,
    input  wire         pcieusergen3rdy,
    output wire [207:0] record_bus
);
    logic       lock_d, reset_d, phystatus_d;
    logic       cdr_hold_d, rategen3_d, usergen3rdy_d;
    logic [1:0] rate_d;
    logic       active;
    logic [15:0] elapsed;
    logic [15:0] rate_start_ts;
    logic [15:0] qpll_reset_rise_ts;
    logic [15:0] qpll_reset_fall_ts;
    logic [15:0] qpll_lock_fall_ts;
    logic [15:0] qpll_lock_rise_ts;
    logic [15:0] qpll_reloss_ts;
    logic [15:0] phystatus_rise_ts;
    logic [15:0] cdr_hold_rise_ts;
    logic [15:0] cdr_hold_fall_ts;
    logic [15:0] rategen3_rise_ts;
    logic [15:0] usergen3rdy_rise_ts;
    logic [15:0] valid;

    wire rate_start = !active && (phy_rate == 2'b10) && (rate_d != 2'b10);

    always_ff @(posedge clk) begin
        if (rst) begin
            lock_d            <= 1'b0;
            reset_d           <= 1'b0;
            rate_d            <= 2'b00;
            phystatus_d       <= 1'b0;
            cdr_hold_d        <= 1'b0;
            rategen3_d        <= 1'b0;
            usergen3rdy_d     <= 1'b0;
            active            <= 1'b0;
            elapsed           <= 16'd0;
            rate_start_ts     <= 16'd0;
            qpll_reset_rise_ts<= 16'd0;
            qpll_reset_fall_ts<= 16'd0;
            qpll_lock_fall_ts <= 16'd0;
            qpll_lock_rise_ts <= 16'd0;
            qpll_reloss_ts    <= 16'd0;
            phystatus_rise_ts <= 16'd0;
            cdr_hold_rise_ts  <= 16'd0;
            cdr_hold_fall_ts  <= 16'd0;
            rategen3_rise_ts  <= 16'd0;
            usergen3rdy_rise_ts <= 16'd0;
            valid             <= 16'd0;
        end else begin
            lock_d      <= qpll1lock;
            reset_d     <= qpll1reset;
            rate_d      <= phy_rate;
            phystatus_d <= phy_phystatus;
            cdr_hold_d  <= cdr_hold;
            rategen3_d  <= pcierategen3;
            usergen3rdy_d <= pcieusergen3rdy;

            if (rate_start) begin
                active        <= 1'b1;
                elapsed       <= 16'd0;
                rate_start_ts <= 16'd0;
                qpll_reset_rise_ts <= 16'd0;
                qpll_reset_fall_ts <= 16'd0;
                qpll_lock_fall_ts  <= 16'd0;
                qpll_lock_rise_ts  <= 16'd0;
                qpll_reloss_ts     <= 16'd0;
                phystatus_rise_ts  <= 16'd0;
                cdr_hold_rise_ts   <= 16'd0;
                cdr_hold_fall_ts   <= 16'd0;
                rategen3_rise_ts   <= 16'd0;
                usergen3rdy_rise_ts <= 16'd0;
                valid         <= 16'd0;
                valid[0]      <= 1'b1;
                if (!qpll1lock) begin
                    valid[4]          <= 1'b1;
                    qpll_lock_fall_ts <= 16'd0;
                end
                if (qpll1reset) begin
                    valid[1]           <= 1'b1;
                    qpll_reset_rise_ts <= 16'd0;
                end
                if (cdr_hold) begin
                    valid[8]          <= 1'b1;
                    cdr_hold_rise_ts  <= 16'd0;
                end
                if (pcierategen3) begin
                    valid[10]         <= 1'b1;
                    rategen3_rise_ts  <= 16'd0;
                end
                if (pcieusergen3rdy) begin
                    valid[11]            <= 1'b1;
                    usergen3rdy_rise_ts  <= 16'd0;
                end
            end else if (active) begin
                if (!valid[1] && !reset_d && qpll1reset) begin
                    valid[1]           <= 1'b1;
                    qpll_reset_rise_ts <= elapsed;
                end
                if (!valid[2] && reset_d && !qpll1reset) begin
                    valid[2]          <= 1'b1;
                    qpll_reset_fall_ts<= elapsed;
                end
                if (!valid[4] && lock_d && !qpll1lock) begin
                    valid[4]          <= 1'b1;
                    qpll_lock_fall_ts <= elapsed;
                end
                if (valid[4] && !valid[5] && !lock_d && qpll1lock) begin
                    valid[5]          <= 1'b1;
                    qpll_lock_rise_ts <= elapsed;
                end
                if (valid[5] && !valid[6] && lock_d && !qpll1lock) begin
                    valid[6]       <= 1'b1;
                    qpll_reloss_ts <= elapsed;
                end
                if (!valid[7] && !phystatus_d && phy_phystatus) begin
                    valid[7]          <= 1'b1;
                    phystatus_rise_ts <= elapsed;
                end
                if (!valid[8] && !cdr_hold_d && cdr_hold) begin
                    valid[8]         <= 1'b1;
                    cdr_hold_rise_ts <= elapsed;
                end
                if (!valid[9] && cdr_hold_d && !cdr_hold) begin
                    valid[9]        <= 1'b1;
                    cdr_hold_fall_ts <= elapsed;
                end
                if (!valid[10] && !rategen3_d && pcierategen3) begin
                    valid[10]         <= 1'b1;
                    rategen3_rise_ts <= elapsed;
                end
                if (!valid[11] && !usergen3rdy_d && pcieusergen3rdy) begin
                    valid[11]            <= 1'b1;
                    usergen3rdy_rise_ts <= elapsed;
                end
                if (elapsed != 16'hffff)
                    elapsed <= elapsed + 1'b1;
            end
        end
    end

    // [207:192] elapsed, [191:176] rate start, [175:160] QPLL reset rise,
    // [159:144] reset fall, [143:128] lock fall, [127:112] lock rise,
    // [111:96] reloss, [95:80] PhyStatus rise, [79:64] CDR hold rise,
    // [63:48] CDR hold fall, [47:32] PCIERATEGEN3 rise,
    // [31:16] PCIEUSERGEN3RDY rise, [15:0] valid flags.
    assign record_bus = {elapsed, rate_start_ts, qpll_reset_rise_ts,
                         qpll_reset_fall_ts, qpll_lock_fall_ts,
                         qpll_lock_rise_ts, qpll_reloss_ts,
                         phystatus_rise_ts, cdr_hold_rise_ts,
                         cdr_hold_fall_ts, rategen3_rise_ts,
                         usergen3rdy_rise_ts, valid};
endmodule

`default_nettype wire
