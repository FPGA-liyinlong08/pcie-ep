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
// File       : phy_ctrl_pat_gen.v
// Version    : 1.0 
//-----------------------------------------------------------------------------
//--
//-- Description:
//--    PCIE4 PHY Controller
//--
//-------------------------------------------------------------------------------
`timescale 1ns/1ps
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
   output wire   [PHY_LANE-1:0]      PHY_TXELECIDLE

);


  genvar i;

  generate

    for(i = 0; i < PHY_LANE; i = i + 1) begin : pat_gen_lane

      phy_ctrl_pat_gen_lane #(.DW(DW), .TCQ(TCQ)) pat_gen_lane (

        .CLK(CLK),
        .RST(RST),
        .EN(EN),
        .PHY_RATE(PHY_RATE),

        .PHY_TXDATA(PHY_TXDATA[(DW*i)+(DW-1):(DW*i)+0]),
        .PHY_TXELECIDLE (PHY_TXELECIDLE[i]),
        .PHY_TXDATAK(PHY_TXDATAK[(2*i)+1:(2*i)+0]),
        .PHY_TXDATA_VALID(PHY_TXDATA_VALID[i]),
        .PHY_TXSTART_BLOCK(PHY_TXSTART_BLOCK[i]),
        .PHY_TXSYNC_HEADER(PHY_TXSYNC_HEADER[(2*i)+1:(2*i)+0])
      );

    end

  endgenerate

endmodule
