//-----------------------------------------------------------------------------
//
// (c) Copyright 2012-2012 Xilinx, Inc. All rights reserved.
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
//-----------------------------------------------------------------------------
//
// Project    : Ultrascale FPGA Gen3 Integrated Block for PCI Express
// File       : board.v
// Version    : 4.4 
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// Description: Top level testbench
//
//------------------------------------------------------------------------------

`timescale 1ns/1ns

`include "board_common.vh"

`define SIMULATION

module board;

  parameter          REF_CLK_FREQ       = 0 ;      // 0 - 100 MHz, 1 - 125 MHz,  2 - 250 MHz


  localparam         REF_CLK_HALF_CYCLE = (REF_CLK_FREQ == 0) ? 5000 :
                                          (REF_CLK_FREQ == 1) ? 4000 :
                                          (REF_CLK_FREQ == 2) ? 2000 : 0;

  localparam   [2:0] PF0_DEV_CAP_MAX_PAYLOAD_SIZE = 3'hx2;
  `ifdef LINKWIDTH
  localparam   [3:0] LINK_WIDTH = 4'h`LINKWIDTH;
  `else
  localparam   [3:0] LINK_WIDTH = 4'h1;
  `endif
  `ifdef LINKSPEED
  localparam   [2:0] LINK_SPEED = 3'h`LINKSPEED;
  `else
  localparam   [2:0] LINK_SPEED = 3'h4;
  `endif

  localparam EXT_PIPE_SIM = "FALSE";


    //localparam C_DATA_WIDTH                 = board.EP.pcie3_ultrascale_0_i.inst.C_DATA_WIDTH;
    //localparam KEEP_WIDTH                   = board.EP.pcie3_ultrascale_0_i.inst.KEEP_WIDTH;
    localparam PL_LINK_CAP_MAX_LINK_WIDTH   = 3'h4;

   localparam AXI4_DATA_WIDTH              = 64;
   localparam KEEP_WIDTH      = 2;

  integer            i;

  // System-level clock and reset
  reg                sys_rst_n;

  wire               ep_sys_clk_p;
  wire               ep_sys_clk_n;
  wire               rp_sys_clk_p;
  wire               rp_sys_clk_n;
  wire               ep_sys_clk;
  wire               rp_sys_clk;

  //
  // PCI-Express Serial Interconnect
  //
 
  wire  [(LINK_WIDTH-1):0]  ep_pci_exp_txn;
  wire  [(LINK_WIDTH-1):0]  ep_pci_exp_txp;
  wire  [(LINK_WIDTH-1):0]  rp_pci_exp_txn;
  wire  [(LINK_WIDTH-1):0]  rp_pci_exp_txp;
  wire  [6:0] rp_txn;
  wire  [6:0] rp_txp;
 

// Ltssm debug signal
 wire [5:0]     cfg_ltssm_state;
 assign cfg_ltssm_state   =  board.EP.pcie3_ultrascale_0_i.inst.cfg_ltssm_state;

 wire [5:0]     rp_cfg_ltssm_state;
 wire [2:0]     ep_cfg_current_speed;
 wire [3:0]     ep_cfg_negotiated_width;
 wire [1:0]     ep_cfg_phy_link_status;
 wire           ep_cfg_phy_link_down;
 wire           ep_user_lnk_up;
 wire [2:0]     rp_cfg_current_speed;
 wire [3:0]     rp_cfg_negotiated_width;
 wire [1:0]     rp_cfg_phy_link_status;
 wire           rp_cfg_phy_link_down;
 wire           rp_user_lnk_up;

 assign rp_cfg_ltssm_state = RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.cfg_ltssm_state;
 assign ep_cfg_current_speed = EP.pcie3_ultrascale_0_i.inst.cfg_current_speed;
 assign ep_cfg_negotiated_width = EP.pcie3_ultrascale_0_i.inst.cfg_negotiated_width;
 assign ep_cfg_phy_link_status = EP.pcie3_ultrascale_0_i.inst.cfg_phy_link_status;
 assign ep_cfg_phy_link_down = EP.pcie3_ultrascale_0_i.inst.cfg_phy_link_down;
 assign ep_user_lnk_up = EP.user_lnk_up;
 assign rp_cfg_current_speed = RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.cfg_current_speed;
 assign rp_cfg_negotiated_width = RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.cfg_negotiated_width;
 assign rp_cfg_phy_link_status = RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.cfg_phy_link_status;
 assign rp_cfg_phy_link_down = RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.cfg_phy_link_down;
 assign rp_user_lnk_up = RP.user_lnk_up;

 // RXEQ observability for demo-vs-EP comparison.  These are the lane-0
 // PIPE-side command/feedback signals inside the generated EP core.
 wire [1:0] ep_pipe_rx_eqcontrol = EP.pcie3_ultrascale_0_i.inst.pipe_rx_eqcontrol[1:0];
 wire [3:0] ep_pipe_rx_eq_txpreset = EP.pcie3_ultrascale_0_i.inst.pipe_rx_eq_txpreset[3:0];
 wire       ep_pipe_rx_eqdone = EP.pcie3_ultrascale_0_i.inst.pipe_rx_eqdone[0];
 wire       ep_pipe_rx_eq_adapt_done = EP.pcie3_ultrascale_0_i.inst.pipe_rx_eq_adapt_done[0];
 wire [2:0] ep_phy_rxeq_fsm = EP.pcie3_ultrascale_0_i.inst.phy_rxeq_fsm[2:0];
 reg trace_ltssm;

 // Bounded golden PIPE capture for Gen3 Recovery.Equalization.  The hard-IP
 // demo is the protocol reference used by the soft endpoint integration.
 integer ep_gen3_pipe_words;
 integer rp_gen3_pipe_words;
 integer ep_gen3_gt_starts;
 integer ep_gen3_gt_words;
 reg [1:0] ep_last_eq_phase;
 reg [1:0] rp_last_eq_phase;
 wire golden_ep_ts1, golden_ep_ts2, golden_ep_malformed;
 wire [7:0] golden_ep_link, golden_ep_lane, golden_ep_nfts;
 wire [7:0] golden_ep_rate, golden_ep_control, golden_ep_eq_control;
 wire [23:0] golden_ep_eq_data;
 wire golden_ep_link_pad, golden_ep_lane_pad, golden_ep_idle;
 wire golden_rp_ts1, golden_rp_ts2, golden_rp_malformed;
 wire [7:0] golden_rp_link, golden_rp_lane, golden_rp_nfts;
 wire [7:0] golden_rp_rate, golden_rp_control, golden_rp_eq_control;
 wire [23:0] golden_rp_eq_data;
 wire golden_rp_link_pad, golden_rp_lane_pad, golden_rp_idle;
 wire [1:0] ep_pl_eq_phase = EP.pcie3_ultrascale_0_i.inst.pl_eq_phase;
 wire [1:0] rp_pl_eq_phase =
   RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pl_eq_phase;

 initial begin
   ep_gen3_pipe_words = 0;
   rp_gen3_pipe_words = 0;
   ep_gen3_gt_starts = 0;
   ep_gen3_gt_words = 0;
   ep_last_eq_phase = 2'b11;
   rp_last_eq_phase = 2'b11;
 end

 // Compare the hard-IP Endpoint's exact lane-0 GT contract against the soft
 // Endpoint PHY.  Keep the capture bounded to the first startup blocks.
 always @(posedge EP.pcie3_ultrascale_0_i.inst.pipe_clk) begin
   if (trace_ltssm &&
       (cfg_ltssm_state == 6'h28) &&
       EP.pcie3_ultrascale_0_i.inst.gt_pcierategen3_o[0] &&
       EP.pcie3_ultrascale_0_i.inst.pipe_tx0_data_valid &&
       (ep_gen3_gt_words < 32)) begin
     $display("[%t] GOLDEN_EP_TX_BEAT n=%0d start=%0d header=%02b data=%08x",
              $realtime, ep_gen3_gt_words,
              EP.pcie3_ultrascale_0_i.inst.pipe_tx0_start_block,
              EP.pcie3_ultrascale_0_i.inst.pipe_tx0_syncheader,
              EP.pcie3_ultrascale_0_i.inst.pipe_tx0_data);
     ep_gen3_gt_words = ep_gen3_gt_words + 1;
   end
   if (trace_ltssm &&
       EP.pcie3_ultrascale_0_i.inst.pipe_tx0_start_block &&
       (ep_gen3_gt_starts < 24)) begin
     $display("[%t] GOLDEN_EP_GT n=%0d rate_gen3=%0d txresetdone=%0d data=%08x ctrl=%04x",
              $realtime, ep_gen3_gt_starts,
              EP.pcie3_ultrascale_0_i.inst.gt_pcierategen3_o[0],
              EP.pcie3_ultrascale_0_i.inst.gt_txresetdone[0],
              EP.pcie3_ultrascale_0_i.inst.pipe_tx0_data,
              {10'd0, EP.pcie3_ultrascale_0_i.inst.pipe_tx0_syncheader,
               EP.pcie3_ultrascale_0_i.inst.pipe_tx0_start_block,
               EP.pcie3_ultrascale_0_i.inst.pipe_tx0_data_valid, 2'd0});
     ep_gen3_gt_starts = ep_gen3_gt_starts + 1;
   end
 end

 pcie_gen3_os_rx golden_ep_os_rx (
   .clk(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk),
   .rst_n(sys_rst_n), .enable(1'b1),
   .in_valid(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0]),
   .start_block(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_start_block[0]),
   .sync_header(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_syncheader[1:0]),
   .in_data(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[31:0]),
   .ts1_valid(golden_ep_ts1), .ts2_valid(golden_ep_ts2),
   .malformed(golden_ep_malformed), .idle_valid(golden_ep_idle),
   .link_number(golden_ep_link), .link_is_pad(golden_ep_link_pad),
   .lane_number(golden_ep_lane), .lane_is_pad(golden_ep_lane_pad),
   .n_fts(golden_ep_nfts), .rate_id(golden_ep_rate),
   .training_control(golden_ep_control),
   .eq_control(golden_ep_eq_control), .eq_data(golden_ep_eq_data)
 );

 pcie_gen3_os_rx golden_rp_os_rx (
   .clk(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk),
   .rst_n(sys_rst_n), .enable(1'b1),
   .in_valid(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid),
   .start_block(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block),
   .sync_header(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_syncheader),
   .in_data(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data),
   .ts1_valid(golden_rp_ts1), .ts2_valid(golden_rp_ts2),
   .malformed(golden_rp_malformed), .idle_valid(golden_rp_idle),
   .link_number(golden_rp_link), .link_is_pad(golden_rp_link_pad),
   .lane_number(golden_rp_lane), .lane_is_pad(golden_rp_lane_pad),
   .n_fts(golden_rp_nfts), .rate_id(golden_rp_rate),
   .training_control(golden_rp_control),
   .eq_control(golden_rp_eq_control), .eq_data(golden_rp_eq_data)
 );

 always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk) begin
   if (trace_ltssm && (golden_ep_ts1 || golden_ep_ts2))
     $display("[%t] GOLDEN_EP_TS ts1=%0d ts2=%0d phase=%0d link=%02x lane=%02x rate=%02x ctrl=%02x eq_ctrl=%02x eq_data=%06x",
              $realtime, golden_ep_ts1, golden_ep_ts2, ep_pl_eq_phase,
              golden_ep_link, golden_ep_lane, golden_ep_rate,
              golden_ep_control, golden_ep_eq_control, golden_ep_eq_data);
   if (trace_ltssm && (golden_rp_ts1 || golden_rp_ts2))
     $display("[%t] GOLDEN_RP_TS ts1=%0d ts2=%0d phase=%0d link=%02x lane=%02x rate=%02x ctrl=%02x eq_ctrl=%02x eq_data=%06x",
              $realtime, golden_rp_ts1, golden_rp_ts2, rp_pl_eq_phase,
              golden_rp_link, golden_rp_lane, golden_rp_rate,
              golden_rp_control, golden_rp_eq_control, golden_rp_eq_data);
 end

 // Observe the official EP stream at the Root Port PIPE receive boundary;
 // this avoids depending on generated-EP internal pipeline instance names.
 always @(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data) begin
   if (ep_pl_eq_phase != ep_last_eq_phase) begin
     ep_last_eq_phase = ep_pl_eq_phase;
     ep_gen3_pipe_words = 0;
   end
   if (trace_ltssm &&
       (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b10) &&
       RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0] &&
       (ep_gen3_pipe_words < 64)) begin
     $display("[%t] GOLDEN_EP_PIPE n=%0d ltssm=%02h eq_phase=%0d start=%0d header=%02b data=%08x",
              $realtime, ep_gen3_pipe_words, cfg_ltssm_state,
              ep_pl_eq_phase,
              RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_start_block[0],
              RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_syncheader[1:0],
              RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[31:0]);
     ep_gen3_pipe_words = ep_gen3_pipe_words + 1;
   end
 end

 always @(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data) begin
   if (rp_pl_eq_phase != rp_last_eq_phase) begin
     rp_last_eq_phase = rp_pl_eq_phase;
     rp_gen3_pipe_words = 0;
   end
   if (trace_ltssm &&
       (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b10) &&
       RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid &&
       (rp_gen3_pipe_words < 64)) begin
     $display("[%t] GOLDEN_RP_PIPE n=%0d ltssm=%02h eq_phase=%0d start=%0d header=%02b data=%08x",
              $realtime, rp_gen3_pipe_words, rp_cfg_ltssm_state,
              rp_pl_eq_phase,
              RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
              RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_syncheader,
              RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data);
     rp_gen3_pipe_words = rp_gen3_pipe_words + 1;
   end
 end

 // Optional targeted waveform dump for PCIe Gen3 link training.
 // Enable with +DUMP_WAVEFORM. The output is written in the current run directory.
 initial begin
   if ($test$plusargs("DUMP_WAVEFORM")) begin
     $dumpfile("pcie_training.vcd");
     $dumpvars(0, cfg_ltssm_state);
     $dumpvars(0, rp_cfg_ltssm_state);
     $dumpvars(0, ep_cfg_current_speed);
     $dumpvars(0, ep_cfg_negotiated_width);
     $dumpvars(0, ep_cfg_phy_link_status);
     $dumpvars(0, ep_cfg_phy_link_down);
     $dumpvars(0, ep_user_lnk_up);
     $dumpvars(0, rp_cfg_current_speed);
     $dumpvars(0, rp_cfg_negotiated_width);
     $dumpvars(0, rp_cfg_phy_link_status);
     $dumpvars(0, rp_cfg_phy_link_down);
     $dumpvars(0, rp_user_lnk_up);
     $dumpvars(0, EP.pcie3_ultrascale_0_i.inst.pipe_tx_rate_i);
     $dumpvars(0, EP.pcie3_ultrascale_0_i.inst.pipe_tx_elec_idle);
     $dumpvars(0, EP.pcie3_ultrascale_0_i.inst.pipe_rx_elec_idle);
     $dumpvars(0, EP.pcie3_ultrascale_0_i.inst.gt_pcierategen3_o);
     $dumpvars(0, EP.pcie3_ultrascale_0_i.inst.pipe_rx_phy_status);
     $dumpvars(0, ep_pipe_rx_eqcontrol);
     $dumpvars(0, ep_pipe_rx_eq_txpreset);
     $dumpvars(0, ep_pipe_rx_eqdone);
     $dumpvars(0, ep_pipe_rx_eq_adapt_done);
     $dumpvars(0, ep_phy_rxeq_fsm);
   end
 end

 always @(ep_pipe_rx_eqcontrol or ep_pipe_rx_eq_txpreset or
          ep_pipe_rx_eqdone or ep_pipe_rx_eq_adapt_done or ep_phy_rxeq_fsm) begin
   if (trace_ltssm)
     $display("[%t] EP RXEQ ctrl=%02b txpreset=%0d done=%0d adapt_done=%0d fsm=%0d",
              $realtime, ep_pipe_rx_eqcontrol, ep_pipe_rx_eq_txpreset,
              ep_pipe_rx_eqdone, ep_pipe_rx_eq_adapt_done, ep_phy_rxeq_fsm);
 end

 initial trace_ltssm = $test$plusargs("TRACE_LTSSM");

 always @(cfg_ltssm_state) begin
   if (trace_ltssm)
     $display("[%t] EP LTSSM=0x%02h speed=%0d width=%0d phy_status=%b phy_down=%b link_up=%b",
              $realtime, cfg_ltssm_state, ep_cfg_current_speed,
              ep_cfg_negotiated_width, ep_cfg_phy_link_status,
              ep_cfg_phy_link_down, ep_user_lnk_up);
 end

 always @(rp_cfg_ltssm_state) begin
   if (trace_ltssm)
     $display("[%t] RP LTSSM=0x%02h speed=%0d width=%0d phy_status=%b phy_down=%b link_up=%b",
              $realtime, rp_cfg_ltssm_state, rp_cfg_current_speed,
              rp_cfg_negotiated_width, rp_cfg_phy_link_status,
              rp_cfg_phy_link_down, rp_user_lnk_up);
 end

 

 

 











  //------------------------------------------------------------------------------//
  // Generate system clock
  //------------------------------------------------------------------------------//

  sys_clk_gen_ds # (
    .halfcycle(REF_CLK_HALF_CYCLE),
    .offset(0)
  )
  CLK_GEN_RP (
    .sys_clk_p(rp_sys_clk_p),
    .sys_clk_n(rp_sys_clk_n)
  );

  sys_clk_gen_ds # (
    .halfcycle(REF_CLK_HALF_CYCLE),
    .offset(0)
  )
  CLK_GEN_EP (
    .sys_clk_p(ep_sys_clk_p),
    .sys_clk_n(ep_sys_clk_n)
  );

  //------------------------------------------------------------------------------//
  // Generate system-level reset
  //------------------------------------------------------------------------------//
  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge rp_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  //------------------------------------------------------------------------------//
  // EndPoint DUT with PIO Slave
  //
   
  //------------------------------------------------------------------------------//
  //
  // PCI-Express Endpoint Instance
  //
  xilinx_pcie3_uscale_ep 
   EP (
    // SYS Interface
    .sys_clk_n(ep_sys_clk_n),
    .sys_clk_p(ep_sys_clk_p),
    .sys_rst_n(sys_rst_n),

    
    // PCI-Express Serial Interface
    .pci_exp_txn(ep_pci_exp_txn),
    .pci_exp_txp(ep_pci_exp_txp),
    .pci_exp_rxn(rp_pci_exp_txn),
    .pci_exp_rxp(rp_pci_exp_txp)
  
 
  );
  
  //------------------------------------------------------------------------------//
  // Simulation Root Port Model
  // (Comment out this module to interface EndPoint with BFM)
  
  //------------------------------------------------------------------------------//
  //
  // PCI-Express Model Root Port Instance
  //

  xilinx_pcie3_uscale_rp
  #(
     .PF0_DEV_CAP_MAX_PAYLOAD_SIZE(PF0_DEV_CAP_MAX_PAYLOAD_SIZE)
     //ONLY FOR RP
  ) RP (
    // SYS Interface
    .sys_clk_n(rp_sys_clk_n),
    .sys_clk_p(rp_sys_clk_p),
    .sys_rst_n(sys_rst_n),

     
    // PCI-Express Serial Interface
    .pci_exp_txn({rp_txn,rp_pci_exp_txn}),
    .pci_exp_txp({rp_txp,rp_pci_exp_txp}),
    .pci_exp_rxn({7'b0,ep_pci_exp_txn}),
    .pci_exp_rxp({7'b0,ep_pci_exp_txp})
  
  
  );
  
 


endmodule // BOARD
