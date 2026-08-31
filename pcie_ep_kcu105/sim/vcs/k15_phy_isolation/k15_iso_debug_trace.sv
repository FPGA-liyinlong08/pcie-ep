`timescale 1ps/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment -- receiver FSM tracer.
//
// Both receiver instances expose a `debug_state` wire (the generated PHY
// wrapper's debug FSM).  Dump every transition in the 100..200 us window
// together with the PIPE status inputs (phystatus/rxvalid/rxstatus/
// rxelecidle) so a receiver stuck before block lock can be located.
module k15_iso_fsm_trace #(
    parameter integer LABEL = 0
) (
    input wire        clk,
    input wire [7:0]  debug_state,
    input wire        phystatus,
    input wire        rxvalid,
    input wire [2:0]  rxstatus,
    input wire        rxelecidle
);
    reg [7:0] last_state;
    reg       last_ei, last_rxv;
    reg [2:0] last_rxstat;
    reg       armed;
    integer   lines;

    initial begin
        last_state = 8'hxx;
        last_ei    = 1'bx;
        last_rxv   = 1'bx;
        last_rxstat = 3'bx;
        armed      = 0;
        lines      = 0;
    end

    always @(posedge clk) begin
        if ($time > 100000000 && $time < 200000000) begin
            armed <= 1'b1;
        end else begin
            armed <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (armed && ((debug_state !== last_state) || (rxelecidle !== last_ei) ||
                      (rxvalid !== last_rxv) || (rxstatus !== last_rxstat))) begin
            if (lines < 200) begin
                $display("K15_ISO_FSM label=%0d time_ps=%0t state=%02h->%02h phystatus=%0b rxvalid=%0b rxstatus=%03b rxelecidle=%0b",
                         LABEL, $time, last_state, debug_state,
                         phystatus, rxvalid, rxstatus, rxelecidle);
                lines = lines + 1;
            end
            last_state  = debug_state;
            last_ei     = rxelecidle;
            last_rxv    = rxvalid;
            last_rxstat = rxstatus;
        end
    end
endmodule

bind xilinx_pcie_phy_top k15_iso_fsm_trace #(.LABEL(0)) k15_iso_top_fsm (
    .clk(pipe_clk), .debug_state(debug_state), .phystatus(phy_phystatus),
    .rxvalid(phy_rxvalid), .rxstatus(phy_rxstatus), .rxelecidle(phy_rxelecidle)
);

`default_nettype wire
