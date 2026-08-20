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
   end
 end

 reg trace_ltssm;
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
