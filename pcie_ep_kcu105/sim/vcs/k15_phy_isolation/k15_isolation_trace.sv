`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- acquisition checker.
//
// Bound into both standalone PHY instances of the official board:
//   LABEL 0 -> xilinx_pcie_phy_top  (TX payload replaced by K15 source;
//                                     its RX sees the official pattern)
//   LABEL 1 -> xilinx_pcie_phy_model (receiver of the K15 Gen3 stream)
//
// Verdict is based on the LABEL 1 receiver: after the instance enters
// Gen3, does it produce RXDATA_VALID, and is the first valid block the
// EIEOS (ff00ff00, start=1, header=01) as in the passing official golden?
module k15_iso_rx_checker #(
    parameter integer LABEL = 0
) (
    input wire clk,
    input wire [2:0] phy_rate,
    input wire rxvalid,
    input wire rxstart,
    input wire [1:0] rxheader,
    input wire [31:0] rxdata
);
    localparam integer TIMEOUT_CYCLES = 20000;
    localparam integer CAPTURE_BEATS  = 16;

    integer gen3_cycles;
    integer beats_seen;
    reg verdict_done;
    reg seen_gen3;

    initial begin
        gen3_cycles = 0;
        beats_seen = 0;
        verdict_done = 0;
        seen_gen3 = 0;
    end

    always @(posedge clk) begin
        if (phy_rate[1:0] == 2'b10)
            seen_gen3 <= 1'b1;

        if (seen_gen3 && !verdict_done && (phy_rate[1:0] == 2'b10)) begin
            if (rxvalid) begin
                if (beats_seen < CAPTURE_BEATS)
                    $display("K15_ISO_RX_BEAT label=%0d n=%0d time_ps=%0t start=%0d header=%02b data=%08x",
                             LABEL, beats_seen, $time, rxstart, rxheader, rxdata);
                beats_seen = beats_seen + 1;
                if (beats_seen == 4) begin
                    verdict_done = 1'b1;
                    // Golden behavior: the first valid block is a complete
                    // EIEOS (start=1, header=01, ff00ff00 x4).
                    if (rxdata == 32'hff00_ff00)
                        $display("K15_ISO_RECEIVER_ACQ_PASS label=%0d time_ps=%0t first_block=EIEOS",
                                 LABEL, $time);
                    else
                        $display("K15_ISO_RECEIVER_ACQ_FAIL label=%0d time_ps=%0t reason=first_block_not_eieos data=%08x",
                                 LABEL, $time, rxdata);
                end
            end else begin
                gen3_cycles = gen3_cycles + 1;
                if (gen3_cycles == TIMEOUT_CYCLES) begin
                    verdict_done = 1'b1;
                    $display("K15_ISO_RECEIVER_ACQ_FAIL label=%0d time_ps=%0t reason=no_rxdata_valid cycles=%0d",
                             LABEL, $time, gen3_cycles);
                end
            end
        end
    end
endmodule

bind xilinx_pcie_phy_top k15_iso_rx_checker #(.LABEL(0))
    k15_iso_top_rx_check (
        .clk(pipe_clk), .phy_rate(phy_rate),
        .rxvalid(phy_rxdata_valid), .rxstart(phy_rxstart_block),
        .rxheader(phy_rxsync_header), .rxdata(phy_rxdata)
    );

bind xilinx_pcie_phy_model k15_iso_rx_checker #(.LABEL(1))
    k15_iso_model_rx_check (
        .clk(pipe_clk), .phy_rate(phy_rate),
        .rxvalid(phy_rxdata_valid), .rxstart(phy_rxstart_block),
        .rxheader(phy_rxsync_header), .rxdata(phy_rxdata)
    );

`default_nettype wire
