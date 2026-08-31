`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- RXEQ FSM tracer.
//
// Bound into the generated PHY's RX equalization engine.  In the failing
// isolation runs the receiver detects electrical-idle exit (rxelecidle
// drops at the same time as the passing golden) but never reaches block
// lock.  This tracer records the rxeq FSM phases so the divergence point
// between the passing golden and the failing K15 runs can be located.
module k15_iso_rxeq_trace #(
    parameter integer LABEL = 0
) (
    input wire        clk,
    input wire [2:0]  phy_rxeq_fsm,
    input wire        RXEQ_ADAPT_DONE,
    input wire        RXEQ_DONE,
    input wire        RXEQ_LFFS_SEL
);
    reg [2:0]  last_fsm;
    reg        last_adapt, last_done, last_lffs;
    reg        armed;
    integer    lines;

    initial begin
        last_fsm   = 3'bxxx;
        last_adapt = 1'bx;
        last_done  = 1'bx;
        last_lffs  = 1'bx;
        armed      = 0;
        lines      = 0;
    end

    always @(posedge clk) begin
        armed <= ($time > 100000000) && ($time < 200000000);
    end

    always @(posedge clk) begin
        if (armed && ((phy_rxeq_fsm !== last_fsm) ||
                      (RXEQ_ADAPT_DONE !== last_adapt) ||
                      (RXEQ_DONE !== last_done) ||
                      (RXEQ_LFFS_SEL !== last_lffs))) begin
            if (lines < 200) begin
                $display("K15_ISO_RXEQ label=%0d time_ps=%0t fsm=%03b->%03b adapt_done=%0b done=%0b lffs_sel=%0b",
                         LABEL, $time, last_fsm, phy_rxeq_fsm,
                         RXEQ_ADAPT_DONE, RXEQ_DONE, RXEQ_LFFS_SEL);
                lines = lines + 1;
            end
            last_fsm   = phy_rxeq_fsm;
            last_adapt = RXEQ_ADAPT_DONE;
            last_done  = RXEQ_DONE;
            last_lffs  = RXEQ_LFFS_SEL;
        end
    end
endmodule

bind pcie_phy_x1_gen3_us_gt_phy_rxeq k15_iso_rxeq_trace #(.LABEL(0)) k15_iso_rxeq_check (
    .clk(RXEQ_CLK),
    .phy_rxeq_fsm(phy_rxeq_fsm),
    .RXEQ_ADAPT_DONE(RXEQ_ADAPT_DONE),
    .RXEQ_DONE(RXEQ_DONE),
    .RXEQ_LFFS_SEL(RXEQ_LFFS_SEL)
);

`default_nettype wire
