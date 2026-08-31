`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- GTHE3 channel tracer.
//
// The receiver GT hears a bit-exact EIEOS on its RXP pin yet produces no
// parallel data.  This tracer sits inside every GTHE3_CHANNEL instance and
// records the RX reset/CDR/idle handshake plus the first non-zero RXDATA,
// separating a held GT RX reset from a CDR that never re-locks.
module k15_iso_gthe3_trace #(
    parameter integer MAX_LINES = 40
) (
    input wire         rxusrclk2,
    input wire         gtrxreset,
    input wire         rxpmaresetdone,
    input wire         rxcdrlock,
    input wire         rxelecidle,
    input wire [31:0]  rxdata,
    input wire         rxheadervalid,
    input wire         rxdatavalid,
    input wire [2:0]   rxbufstatus,
    input wire         rxresetdone
);
    reg        last_gtrxreset, last_done, last_cdr, last_ei;
    integer    lines;
    reg        armed;

    initial begin
        last_gtrxreset = 1'bx;
        last_done      = 1'bx;
        last_cdr       = 1'bx;
        last_ei        = 1'bx;
        lines          = 0;
        armed          = 0;
    end

    // report the reset/CDR handshake in the whole 100..150 us window
    always @(posedge rxusrclk2) begin
        armed <= ($time > 100000000) && ($time < 150000000);
    end

    always @(posedge rxusrclk2) begin
        if (armed && ((gtrxreset !== last_gtrxreset) || (rxresetdone !== last_done) ||
                      (rxcdrlock !== last_cdr) || (rxelecidle !== last_ei) ||
                      (rxdata !== 32'h0) || rxheadervalid)) begin
            if (lines < MAX_LINES) begin
                $display("K15_ISO_GTHE3 time_ps=%0t inst=%m gtrxreset=%0b rxresetdone=%0b cdrlock=%0b elecidle=%0b pma_done=%0b rxdata=%08h hdrvalid=%0b datavalid=%0b bufstatus=%03b",
                         $time, gtrxreset, rxresetdone, rxcdrlock, rxelecidle,
                         rxpmaresetdone, rxdata, rxheadervalid, rxdatavalid, rxbufstatus);
                lines = lines + 1;
            end
            last_gtrxreset = gtrxreset;
            last_done      = rxresetdone;
            last_cdr       = rxcdrlock;
            last_ei        = rxelecidle;
        end
    end
endmodule

bind GTHE3_CHANNEL k15_iso_gthe3_trace k15_iso_gthe3_check (
    .rxusrclk2(RXUSRCLK2),
    .gtrxreset(GTRXRESET),
    .rxpmaresetdone(RXPMARESETDONE),
    .rxcdrlock(RXCDRLOCK),
    .rxelecidle(RXELECIDLE),
    .rxdata(RXDATA[31:0]),
    .rxheadervalid(RXHEADERVALID[0]),
    .rxdatavalid(RXDATAVALID[0]),
    .rxbufstatus(RXBUFSTATUS),
    .rxresetdone(RXRESETDONE)
);

`default_nettype wire
