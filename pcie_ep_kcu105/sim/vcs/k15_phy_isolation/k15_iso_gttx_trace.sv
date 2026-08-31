`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- GTHE3 TX beat tracer.
//
// The PIPE TXSYNC_HEADER/TXSTART_BLOCK/TXDATA_VALID reach the secureip TX
// gearbox packed into TXCTRL0 (see gtwizard_top: txctrl0_in = {header,
// start_block, data_valid}).  This tracer captures every GT TX beat in the
// Gen3 acquisition window, exposing the wire block structure exactly as the
// TX gearbox consumes it, including any secureip-side substitution while
// TXDATA_VALID is low.
module k15_iso_gttx_trace #(
    parameter integer MAX_LINES = 0
) (
    input wire         txusrclk2,
    input wire [31:0]  txdata,
    input wire [15:0]  txctrl0
);
    reg        armed;
    integer    lines;
    reg [3:0]  txvalid, txstart;
    reg [1:0]  txhdr;

    initial begin
        armed = 0;
        lines = 0;
    end

    always @(posedge txusrclk2) begin
        armed <= ($time > 123500000) && ($time < 125200000);
    end

    always @(posedge txusrclk2) begin
        if (armed) begin
            txvalid = txctrl0[2];
            txstart = txctrl0[3];
            txhdr   = txctrl0[5:4];
            if (lines < MAX_LINES || MAX_LINES == 0) begin
                $display("K15_ISO_GTTX time_ps=%0t inst=%m valid=%0b start=%0b hdr=%02b data=%08h",
                         $time, txctrl0[2], txctrl0[3], txctrl0[5:4], txdata);
                lines = lines + 1;
            end
        end
    end
endmodule

bind GTHE3_CHANNEL k15_iso_gttx_trace k15_iso_gttx_check (
    .txusrclk2(TXUSRCLK2),
    .txdata(TXDATA[31:0]),
    .txctrl0(TXCTRL0[15:0])
);

`default_nettype wire
