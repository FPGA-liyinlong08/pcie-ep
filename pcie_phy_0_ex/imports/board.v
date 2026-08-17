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
// Project    : PCIE4 PHY IP Block 
// File       : board.v
// Version    : 1.0 
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// Project    : PCIE4 PHY IP 
// File       : board.v
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// Description: Top level testbench
//
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "board_common.vh"

`define SIMULATION

module board;

  parameter          REF_CLK_FREQ       = 0 ;      // 0 - 100 MHz, 1 - 125 MHz,  2 - 250 MHz
  parameter    [4:0] LINK_WIDTH         = 5'd1;

  localparam         REF_CLK_HALF_CYCLE = (REF_CLK_FREQ == 0) ? 5000 :
                                          (REF_CLK_FREQ == 1) ? 4000 :
                                          (REF_CLK_FREQ == 2) ? 2000 : 0;

  integer            i;

  // System-level clock and reset
  reg                sys_rst_n;

  //
  // PCI-Express Serial Interconnect
  //
  wire  [(LINK_WIDTH-1):0]  ep_pci_exp_txn;
  wire  [(LINK_WIDTH-1):0]  ep_pci_exp_txp;
  wire  [(LINK_WIDTH-1):0]  rp_pci_exp_txn;
  wire  [(LINK_WIDTH-1):0]  rp_pci_exp_txp;

  reg                       ep_tx_elec_idle;           
  reg                       ep_phy_ready_en;           
  reg                       ep_gen1_en;           
  reg                       ep_gen2_en;           
  reg                       ep_gen3_en;           
  reg                       ep_gen4_en;           
  wire                      ep_led_0;
  wire                      ep_led_1;
  wire                      ep_led_2;
  wire                      ep_led_3;
  wire                      ep_led_4;
  wire                      ep_led_5;
  wire                      ep_led_6;
  wire                      ep_led_7;

  wire [7:0]                ep_leds = {ep_led_7, ep_led_6, ep_led_5, ep_led_4, ep_led_3, ep_led_2, ep_led_1, ep_led_0};

  reg                       rp_tx_elec_idle;           
  reg                       rp_phy_ready_en;           
  reg                       rp_gen1_en;           
  reg                       rp_gen2_en;           
  reg                       rp_gen3_en;           
  reg                       rp_gen4_en;           
  wire                      rp_led_0;
  wire                      rp_led_1;
  wire                      rp_led_2;
  wire                      rp_led_3;
  wire                      rp_led_4;
  wire                      rp_led_5;
  wire                      rp_led_6;
  wire                      rp_led_7;

  wire [7:0]                rp_leds = {rp_led_7, rp_led_6, rp_led_5, rp_led_4, rp_led_3, rp_led_2, rp_led_1, rp_led_0};


  xilinx_pcie_phy_top PCIE_PHY ( 
    // SYS Inteface
    .sys_clk_n(rp_sys_clk_n),
    .sys_clk_p(rp_sys_clk_p),
    .sys_rst_n(sys_rst_n),
  
    // PCI-Express Interface
    .pci_exp_txn(rp_pci_exp_txn),
    .pci_exp_txp(rp_pci_exp_txp),
    .pci_exp_rxn(ep_pci_exp_txn),
    .pci_exp_rxp(ep_pci_exp_txp),

    .led_0(ep_led_0),
    .led_1(ep_led_1),
    .led_2(ep_led_2),
    .led_3(ep_led_3),
    .led_4(ep_led_4),
    .led_5(ep_led_5),
    .led_6(ep_led_6),
    .led_7(ep_led_7),

    .sys_rst_override_n(sys_rst_n),
    .tx_elec_idle(rp_tx_elec_idle),
    .phy_ready_en(rp_phy_ready_en),
    .gen1_en(rp_gen1_en),
    .gen2_en(rp_gen2_en),
    .gen3_en(rp_gen3_en),
    .gen4_en(rp_gen4_en)

  );

  //------------------------------------------------------------------------------//
  // Simulation endpoint with PIO Slave
  //------------------------------------------------------------------------------//
  //
  // PCI-Express Endpoint Instance
  //

  xilinx_pcie_phy_model PHY_MODEL (

    // SYS Inteface
    .sys_clk_n(ep_sys_clk_n),
    .sys_clk_p(ep_sys_clk_p),
    .sys_rst_n(sys_rst_n),

    // PCI-Express Interface
    .pci_exp_txn(ep_pci_exp_txn),
    .pci_exp_txp(ep_pci_exp_txp),
    .pci_exp_rxn(rp_pci_exp_txn),
    .pci_exp_rxp(rp_pci_exp_txp),

    .led_0(rp_led_0),
    .led_1(rp_led_1),
    .led_2(rp_led_2),
    .led_3(rp_led_3),
    .led_4(rp_led_4),
    .led_5(rp_led_5),
    .led_6(rp_led_6),
    .led_7(rp_led_7),

    .sys_rst_override_n(sys_rst_n),
    .tx_elec_idle(ep_tx_elec_idle),
    .phy_ready_en(ep_phy_ready_en),
    .gen1_en(ep_gen1_en),
    .gen2_en(ep_gen2_en),
    .gen3_en(ep_gen3_en),
    .gen4_en(ep_gen4_en)

  );



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


  initial begin

  $monitor($time,,,"EP %b -- RP %b",ep_leds, rp_leds);
  //
  // Power Down and Tx EI = 1
  //

  ep_phy_ready_en = 0;           
  ep_gen1_en = 0;           
  ep_gen2_en = 0;           
  ep_gen3_en = 0;           
  ep_gen4_en = 0;           

  rp_phy_ready_en = 0;           
  rp_gen1_en = 0;           
  rp_gen2_en = 0;           
  rp_gen3_en = 0;           
  rp_gen4_en = 0;           


  //
  // wait for sys_reset deassertion
  //
  wait (sys_rst_n == 1'b1);

  // 
  // Wait for phy_ready
  //
  wait ((ep_led_2 == 1'b1) && (rp_led_2 == 1'b1));

  #10000;

  // 
  // Power Up
  //
  ep_phy_ready_en = 1;           
  rp_phy_ready_en = 1;           
  ep_gen1_en = 1;           
  rp_gen1_en = 1; 

  #5000;

  // Gen1 ON 
            
  $display("[%t] : Gen1 ON",$realtime);
  wait ((ep_led_3 == 1'b1) && (rp_led_3 == 1'b1));
  #50000;     

  // Gen1 OFF
  ep_gen1_en = 0;           
  rp_gen1_en = 0;           
  $display("[%t] : Gen1 Off",$realtime);

  #10000;

//////////////////  Enter Gen2/Gen3/Gen4 based on Rate change requirement ////////////

   //Speed change to Gen3
   // Gen3 ON
   ep_gen3_en = 1;           
   rp_gen3_en = 1;
   $display("[%t] : Gen3 ON",$realtime);
    wait ((ep_led_3 == 1'b1) && (rp_led_3 == 1'b1));

    #80000;

    ep_gen3_en = 0;           
    rp_gen3_en = 0; 
    // Gen3 OFF
  #1000;
    $display("[%t] : PHY Traffic Has Tested @ 8.0 Gbps or Gen-3 Speed...", $realtime);
  #1000;
    $display("[%t] : Test Completed Successfully",$realtime);

  $finish;
end

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

/*
`ifdef PCIE_3_RTL
  initial begin
    $shm_open({"x8g3_rtl.shm"});
    $shm_probe(board, "AS");
  end 
`elsif NETLIST_SIM
  initial begin
    $shm_open({"x8g3_netlist.shm"});
    $shm_probe(board, "AS");
  end
`else
  initial begin
    $shm_open({"x8g3_linkup.shm"});
    $shm_probe(board, "AS");
  end  
`endif
*/  
 

endmodule // BOARD
