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
// File       : phy_ctrl_defines.vh
// Version    : 1.0 
//-----------------------------------------------------------------------------

`define GEN12_CHIK              2'b11
`define GEN12_SKP0_TX_DATA      64'h00000000_00001CBC
`define GEN12_SKP1_TX_DATA      64'h00000000_00001C1C

`define GEN12_TX_DATA           64'h00000000_0000A5A5
`define GEN3_EIOS_TX_DATA       64'h00000000_66666666
`define GEN34_SYNC_HDR_OS       2'b01
`define GEN34_SYNC_HDR_DS       2'b10
`define GEN3_EIEOS_TX_DATA      64'h00000000_FF00FF00
`define GEN4_EIEOS_TX_DATA      64'hFFFF0000_FFFF0000

`define GEN3_TX_DATA_PAT        64'h00000000_beefcafe
`define GEN4_TX_DATA_PAT        64'hdeadbeef_feedface
`define GEN4_TX_EDS_PAT         64'h0090801F_00000000
`define GEN4_TX_SKP_PAT_0       64'hAAAAAAAA_AAAAAAAA
`define GEN4_TX_SKP_PAT_1       64'h000000E1_AAAAAAAA

`define GEN4_TX_EDS_PAT0        32'h00000000
`define GEN4_TX_EDS_PAT1        32'h0090801F
