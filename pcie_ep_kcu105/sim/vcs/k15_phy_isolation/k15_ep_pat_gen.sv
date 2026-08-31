`timescale 1ns/1ps
`default_nettype none

// K15 EP TX/receiver isolation experiment.
//
// This module replaces the official `phy_ctrl_pat_gen` at elaboration by
// name binding: the official runner's source list simply omits
// phy_ctrl_pat_gen.v and compiles this file instead.  Everything else in
// the official 2x standalone PHY testbench is unchanged -- the generated
// PHY (pcie_phy_0), the official phy_ctrl reset/rate sequencer and the
// partner xilinx_pcie_phy_model receiver.
//
// Behavior:
//   * Gen1/Gen2: pass the official per-lane phy_ctrl_pat_gen_lane outputs
//     straight through, so the official bring-up and rate-change contract
//     is identical to the passing golden.
//   * Gen3 (EN && PHY_RATE == 010): drive the PIPE TX payload from K15's
//     pcie_gen3_os_tx (EIEOS -> SKP -> TS repeating), i.e. exactly the
//     stream the failing K15 EP presents at its PIPE interface.  TS field
//     constants mirror the K15 lane-0 Phase0 drive: link/lane 0, not pad,
//     n_fts=ff, rate_id=0e, training_control=01.
module phy_ctrl_pat_gen #(

  parameter integer   PHY_LANE  = 1,
  parameter integer   DW        = 32,
  parameter           TCQ       = 1

)(

   input  wire                       CLK,
   input  wire                       RST,

   // Control
   input   wire                      EN,
   input   wire [2:0]                PHY_RATE,

   // TX Data
   output  wire [(PHY_LANE*DW)-1:0]  PHY_TXDATA,
   output  wire [(PHY_LANE* 2)-1:0]  PHY_TXDATAK,
   output  wire [PHY_LANE-1:0]       PHY_TXDATA_VALID,
   output  wire [PHY_LANE-1:0]       PHY_TXSTART_BLOCK,
   output  wire [(PHY_LANE* 2)-1:0]  PHY_TXSYNC_HEADER,
   output  wire [PHY_LANE-1:0]       PHY_TXELECIDLE

);

  // Gen3 ownership follows the same trigger the official pat_gen uses:
  // the registered rate output of phy_ctrl while the bring-up EN is set.
  wire gen3_active = EN && (PHY_RATE[1:0] == 2'b10);

`ifdef K15_ISO_PHASE_SHIFT
  // Diagnostic: delay the K15 Gen3 launch by two pipe cycles so the K15
  // stream is launched at the same pipe cycles as the official pat_gen
  // golden (whose extra registered stages make it two cycles slower).
  reg [1:0] gen3_active_dly;
  always @(posedge CLK or posedge RST) begin
    if (RST)
      gen3_active_dly <= 2'b00;
    else
      gen3_active_dly <= {gen3_active_dly[0], gen3_active};
  end
  wire gen3_owns_tx = gen3_active_dly[1];
`else
  wire gen3_owns_tx = gen3_active;
`endif

  // Official lane payload (authoritative for Gen1/Gen2).
  wire [(PHY_LANE*DW)-1:0] lane_txdata;
  wire [(PHY_LANE* 2)-1:0] lane_txdatak;
  wire [PHY_LANE-1:0]      lane_txdata_valid;
  wire [PHY_LANE-1:0]      lane_txstart_block;
  wire [(PHY_LANE* 2)-1:0] lane_txsync_header;
  wire [PHY_LANE-1:0]      lane_txelecidle;

  genvar i;
  generate
    for (i = 0; i < PHY_LANE; i = i + 1) begin : official_lane

      phy_ctrl_pat_gen_lane #(.DW(DW), .TCQ(TCQ)) pat_gen_lane (

        .CLK(CLK),
        .RST(RST),
        .EN(EN),
        .PHY_RATE(PHY_RATE),

        .PHY_TXDATA       (lane_txdata[(DW*i)+(DW-1):(DW*i)+0]),
        .PHY_TXELECIDLE   (lane_txelecidle[i]),
        .PHY_TXDATAK      (lane_txdatak[(2*i)+1:(2*i)+0]),
        .PHY_TXDATA_VALID (lane_txdata_valid[i]),
        .PHY_TXSTART_BLOCK(lane_txstart_block[i]),
        .PHY_TXSYNC_HEADER(lane_txsync_header[(2*i)+1:(2*i)+0])
      );

    end
  endgenerate

  // K15 Gen3 ordered-set source, one instance per lane (x1 in this board).
  wire [(PHY_LANE*DW)-1:0] k15_txdata;
  wire [PHY_LANE-1:0]      k15_txdata_valid;
  wire [PHY_LANE-1:0]      k15_txstart_block;
  wire [(PHY_LANE* 2)-1:0] k15_txsync_header;

  generate
    for (i = 0; i < PHY_LANE; i = i + 1) begin : k15_lane

      pcie_gen3_os_tx u_k15_os_tx (
          .clk(CLK),
          .rst_n(!RST),
          .enable(gen3_owns_tx),
          .mode(2'd1),                       // TS1
          .link_number(8'h00),
          .link_is_pad(1'b0),
          .lane_number(8'(i)),
          .lane_is_pad(1'b0),
          .n_fts(8'hff),
          .rate_id(8'h0e),
          .training_control(8'h01),
          .eq_control(8'h00),
          .eq_data(24'h000000),
          .out_data          (k15_txdata[(DW*i)+(DW-1):(DW*i)+0]),
          .out_valid         (k15_txdata_valid[i]),
          .start_block       (k15_txstart_block[i]),
          .sync_header       (k15_txsync_header[(2*i)+1:(2*i)+0]),
          .os_complete       (),
          .word_index_debug  (),
          .eieos_active      (),
          .eieos_start       (),
          .lfsr_state_after_word()
      );

    end
  endgenerate

`ifdef K15_ISO_PASSTHROUGH
  // Diagnostic bisection: pass the official lane outputs straight through
  // in every rate, i.e. the stream is bit-identical to the passing golden
  // while still going through this substituted module.
  assign PHY_TXDATA        = lane_txdata;
  assign PHY_TXDATAK       = lane_txdatak;
  assign PHY_TXDATA_VALID  = lane_txdata_valid;
  assign PHY_TXSTART_BLOCK = lane_txstart_block;
  assign PHY_TXSYNC_HEADER = lane_txsync_header;
  assign PHY_TXELECIDLE    = lane_txelecidle;
`else
`ifdef K15_ISO_VALID_GAP_128
`define K15_ISO_VALID_GAP_ACTIVE
`elsif K15_ISO_VALID_GAP
`define K15_ISO_VALID_GAP_ACTIVE
`endif

`ifdef K15_ISO_VALID_GAP_128
  // Diagnostic: official-phase gaps for the 128-beat EIEOS cadence.  The
  // official pattern places a 1-beat TXDATA_VALID gap immediately before
  // every second EIEOS (offset 129 of its 130-beat period), so on the wire
  // every EIEOS is preceded by PHY-substituted SKP.  With K15's 128-beat
  // EIEOS period (K15_ISO_EIEOS_128) the matching phases are 64 and 127.
  reg [7:0] gap_phase;
  always @(posedge CLK or posedge RST) begin
    if (RST)
      gap_phase <= 8'd0;
    else if (gen3_owns_tx)
      gap_phase <= (gap_phase == 8'd127) ? 8'd0 : gap_phase + 1'b1;
    else
      gap_phase <= 8'd0;
  end
  wire valid_gap = gen3_owns_tx &&
                   ((gap_phase == 8'd64) || (gap_phase == 8'd127));
`elsif K15_ISO_VALID_GAP
  // Diagnostic: reproduce the official pat_gen's 1-beat TXDATA_VALID gap
  // (states PAT_GEN_GEN3_PAT_Z3/Z4, at Gen3 beat offsets 64 and 129 of its
  // 130-beat period) so the PHY substitutes real Gen3 SKP ordered sets on
  // the wire while the K15 os_tx stream continues underneath.  The gap beat
  // also clears TXSTART_BLOCK and TXSYNC_HEADER exactly like Z3/Z4.
  reg [7:0] gap_phase;
  always @(posedge CLK or posedge RST) begin
    if (RST)
      gap_phase <= 8'd0;
    else if (gen3_owns_tx)
      gap_phase <= (gap_phase == 8'd129) ? 8'd0 : gap_phase + 1'b1;
    else
      gap_phase <= 8'd0;
  end
  wire valid_gap = gen3_owns_tx &&
                   ((gap_phase == 8'd64) || (gap_phase == 8'd129));
`endif

  // Output mux: K15 stream owns the Gen3 PIPE payload, official lanes own
  // everything else.  Gen3 drives TXELECIDLE low and TXDATAK low, matching
  // both the official Gen3 pattern and the K15 EP drive.
  assign PHY_TXDATA        = gen3_owns_tx ? k15_txdata        : lane_txdata;
  assign PHY_TXDATAK       = gen3_owns_tx ? {PHY_LANE{2'b00}} : lane_txdatak;
  assign PHY_TXDATA_VALID  = gen3_owns_tx ?
`ifdef K15_ISO_VALID_GAP_ACTIVE
                             (valid_gap ? 1'b0 : k15_txdata_valid) :
`else
                             k15_txdata_valid :
`endif
                             lane_txdata_valid;
  assign PHY_TXSTART_BLOCK = gen3_owns_tx ?
`ifdef K15_ISO_VALID_GAP_ACTIVE
                             (valid_gap ? 1'b0 : k15_txstart_block) :
`else
                             k15_txstart_block :
`endif
                             lane_txstart_block;
  assign PHY_TXSYNC_HEADER = gen3_owns_tx ?
`ifdef K15_ISO_VALID_GAP_ACTIVE
                             (valid_gap ? 2'b00 : k15_txsync_header) :
`else
                             k15_txsync_header :
`endif
                             lane_txsync_header;
  assign PHY_TXELECIDLE    = gen3_owns_tx ? {PHY_LANE{1'b0}}  : lane_txelecidle;
`endif

endmodule

`default_nettype wire
