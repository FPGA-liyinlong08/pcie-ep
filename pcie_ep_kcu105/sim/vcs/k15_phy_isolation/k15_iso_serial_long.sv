`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- long serial capture.
//
// Captures MAX_EDGE transitions of the board-level RP transmitter after
// the Gen3 electrical-idle exit so the full K15 bitstream (EIEOS + many
// payload blocks) can be diffed bit-for-bit against the passing golden.
module k15_iso_serial_long #(
    parameter integer MAX_EDGE = 400
) (
    input wire serial_p,
    input wire [2:0] phy_rate,
    input wire phy_txelecidle
);
    integer edge_count;
    time last_edge;

    initial begin
        edge_count = 0;
        last_edge  = 0;
    end

    always @(serial_p) begin
        if ((phy_rate == 3'b010) && !phy_txelecidle &&
            (edge_count < MAX_EDGE)) begin
            $display("K15_ISO_SERIAL_LONG n=%0d time_ps=%0t delta_ps=%0t value=%0d",
                     edge_count, $time, $time - last_edge, serial_p);
            last_edge  = $time;
            edge_count = edge_count + 1;
        end
    end
endmodule

bind board k15_iso_serial_long k15_iso_serial_long_rp (
    .serial_p(rp_pci_exp_txp[0]),
    .phy_rate(PCIE_PHY.phy_rate),
    .phy_txelecidle(PCIE_PHY.phy_txelecidle)
);

`default_nettype wire
