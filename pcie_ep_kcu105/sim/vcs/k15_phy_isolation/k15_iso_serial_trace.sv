`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- RX-pin edge tracers.
//
// The official bind only captures board.rp_pci_exp_txp (top TX).  These
// tracers capture what each RECEIVER instance actually hears on its own
// serial RX pin around the Gen3 electrical-idle exit, so a receiver-side
// failure can be separated from a TX-side bitstream difference.
//
//   LABEL 0 -> xilinx_pcie_phy_top  RX pin (hears the model's TX)
//   LABEL 1 -> xilinx_pcie_phy_model RX pin (hears the top's K15 stream)
//
// Trigger: first transition after time > 100 us (Gen1 traffic has long
// settled; the next activity is the Gen3 EIEOS after electrical idle).
module k15_iso_serial_trace #(
    parameter integer LABEL   = 0,
    parameter integer MAX_EDGE = 40
) (
    input wire serial_p
);
    integer edge_count;
    reg    armed;
    time   last_edge;

    initial begin
        edge_count = 0;
        armed      = 0;
        last_edge  = 0;
    end

    always @(serial_p) begin
        if ($time > 100000000) begin
            if (!armed) begin
                armed     = 1;
                last_edge = $time;
                $display("K15_ISO_RXPIN_EDGE label=%0d n=0 time_ps=%0t delta_ps=%0t value=%0b",
                         LABEL, $time, $time, serial_p);
                edge_count = 1;
            end else if (edge_count < MAX_EDGE) begin
                $display("K15_ISO_RXPIN_EDGE label=%0d n=%0d time_ps=%0t delta_ps=%0t value=%0b",
                         LABEL, edge_count, $time, $time - last_edge, serial_p);
                edge_count = edge_count + 1;
                last_edge  = $time;
            end
        end
    end
endmodule

bind xilinx_pcie_phy_top k15_iso_serial_trace #(.LABEL(0)) k15_iso_top_rxpin_trace (
    .serial_p(pci_exp_rxp)
);

bind xilinx_pcie_phy_model k15_iso_serial_trace #(.LABEL(1)) k15_iso_model_rxpin_trace (
    .serial_p(pci_exp_rxp)
);

`default_nettype wire
