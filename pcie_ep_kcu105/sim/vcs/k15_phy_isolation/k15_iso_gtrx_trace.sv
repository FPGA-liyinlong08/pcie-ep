`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- GT RX data tracer.
//
// Bound into the generated PHY core top of every PHY instance.  Captures
// the first non-zero GT-side RX parallel words (phy_rxdata_32b, before
// the PHY pipeline) and the corresponding PIPE output (phy_rxdata_int),
// so a dead GT receiver can be separated from a stalled PCS pipeline.
module k15_iso_gtrx_trace #(
    parameter integer MAX_LINES = 12
) (
    input wire        clk,
    input wire [31:0] rxdata_32b,
    input wire        rxvalid_32b,
    input wire [31:0] rxdata_int,
    input wire        rxvalid_int
);
    reg        armed;
    integer    lines;

    initial begin
        armed = 0;
        lines = 0;
        #123000000;
        $display("K15_ISO_GTRX_ARMED inst=%m");
    end

    always @(posedge clk) begin
        armed <= ($time > 123000000) && ($time < 127000000);
    end

    always @(posedge clk) begin
        if (armed && (rxdata_32b !== 32'h0000_0000 || rxdata_int !== 32'h0000_0000)) begin
            if (lines < MAX_LINES) begin
                $display("K15_ISO_GTRX time_ps=%0t inst=%m rxdata_32b=%08h rxvalid_32b=%0b rxdata_int=%08h rxvalid_int=%0b",
                         $time, rxdata_32b, rxvalid_32b, rxdata_int, rxvalid_int);
                lines = lines + 1;
            end
        end
    end
endmodule

bind pcie_phy_x1_gen3_core_top k15_iso_gtrx_trace k15_iso_gtrx_check (
    .clk(phy_pclk),
    .rxdata_32b(phy_rxdata_32b),
    .rxvalid_32b(phy_rxdata_valid_32b),
    .rxdata_int(phy_rxdata_int),
    .rxvalid_int(phy_rxdata_valid_int)
);

`default_nettype wire
