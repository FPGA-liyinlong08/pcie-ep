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
// File       : phy_ctrl_pat_gen_lane.v
// Version    : 1.0 
//-----------------------------------------------------------------------------
//--
//-- Description:  PCI Express Endpoint example FPGA design
//--
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "phy_ctrl_defines.vh"

module phy_ctrl_pat_gen_lane #(

  parameter integer   DW                 = 64,
  parameter                          TCQ = 1

)(                                                         

   input  wire                       CLK,                          
   input  wire                       RST,  

   // Control

   input   wire                      EN,
   input   wire [2:0]                PHY_RATE,
  
   // TX Data 
   output  wire [DW-1:0]             PHY_TXDATA,            
   output  wire [1:0]                PHY_TXDATAK,    
   output  wire [0:0]                PHY_TXDATA_VALID,
   output  wire [0:0]                PHY_TXSTART_BLOCK,      
   output  wire [1:0]                PHY_TXSYNC_HEADER,
   output  wire                      PHY_TXELECIDLE

);

localparam PAT_GEN_HOME          = 8'h00;
localparam PAT_GEN_GEN12_SKP_1   = 8'h01;
localparam PAT_GEN_GEN12_SKP_2   = 8'h02;
localparam PAT_GEN_GEN12_PAT     = 8'h03;

localparam PAT_GEN_GEN3_EIEOS_1  = 8'h10;
localparam PAT_GEN_GEN3_EIEOS_2  = 8'h11;
localparam PAT_GEN_GEN3_EIEOS_3  = 8'h12;
localparam PAT_GEN_GEN3_EIEOS_4  = 8'h13;
localparam PAT_GEN_GEN3_PAT_ST   = 8'h14;
localparam PAT_GEN_GEN3_PAT_Z0   = 8'h15;
localparam PAT_GEN_GEN3_PAT_Z1   = 8'h16;
localparam PAT_GEN_GEN3_PAT_Z2   = 8'h17;
localparam PAT_GEN_GEN3_PAT_Z3   = 8'h18;
localparam PAT_GEN_GEN3_PAT_ST1  = 8'h19;
localparam PAT_GEN_GEN3_PAT_Z01  = 8'h1A;
localparam PAT_GEN_GEN3_PAT_Z11  = 8'h1B;
localparam PAT_GEN_GEN3_PAT_Z21  = 8'h1C;
localparam PAT_GEN_GEN3_PAT_Z4   = 8'h1D;

localparam PAT_GEN_GEN4_EIEOS_1  = 8'h20;
localparam PAT_GEN_GEN4_EIEOS_2  = 8'h21;
localparam PAT_GEN_GEN4_EIEOS_3  = 8'h22;
localparam PAT_GEN_GEN4_EIEOS_4  = 8'h23;

localparam PAT_GEN_GEN4_PAT_ST   = 8'h24;
localparam PAT_GEN_GEN4_PAT_Z0   = 8'h25;
localparam PAT_GEN_GEN4_PAT_Z1   = 8'h26;

localparam PAT_GEN_GEN4_SKP_0    = 8'h27;
localparam PAT_GEN_GEN4_SKP_1    = 8'h28;
localparam PAT_GEN_GEN4_SKP_2    = 8'h29;
localparam PAT_GEN_GEN4_SKP_3    = 8'h2A;

localparam PAT_GEN_GEN4_DAT_ST   = 8'h2B;
localparam PAT_GEN_GEN4_DAT_Z0   = 8'h2C;
localparam PAT_GEN_GEN4_DAT_Z1   = 8'h2D;
localparam PAT_GEN_GEN4_DAT_ED0   = 8'h2E;
localparam PAT_GEN_GEN4_DAT_ED1   = 8'h2F;

localparam PAT_GEN_GEN3_EIOS_1   = 8'h30;
localparam PAT_GEN_GEN3_EIOS_2   = 8'h31;
localparam PAT_GEN_GEN3_EIOS_3   = 8'h32;
localparam PAT_GEN_GEN3_EIOS_4   = 8'h33;
localparam PAT_GEN_GEN3_EIOS_5   = 8'h34;


reg       PHY_TXELECIDLE_w;
reg  [7:0] state_m;
reg  [7:0] state_r;
wire [7:0] state_w;

reg  [7:0] pat_count_m;
reg  [7:0] pat_count_r;
wire [7:0] pat_count_w;

reg  [9:0] eieos_count_m;
reg  [9:0] eieos_count_r;
wire [9:0] eieos_count_w;

reg  [4:0] skp_count_m;
reg  [4:0] skp_count_r;
wire [4:0] skp_count_w;

reg  [DW-1:0] PHY_TXDATA_m;            
reg  [DW-1:0] PHY_TXDATA_r;            
reg  [1:0]    PHY_TXDATAK_m;    
reg  [1:0]    PHY_TXDATAK_r;    
reg           PHY_TXELECIDLE_r;
reg  [0:0]    PHY_TXDATA_VALID_m;
reg  [0:0]    PHY_TXDATA_VALID_r;
reg  [0:0]    PHY_TXSTART_BLOCK_m;      
reg  [0:0]    PHY_TXSTART_BLOCK_r;      
reg  [1:0]    PHY_TXSYNC_HEADER_m;                    
reg  [1:0]    PHY_TXSYNC_HEADER_r;                    
reg  flag;
wire flag_w;
reg  flag_r;
reg [2:0] gen4_eie_cnt;
reg [2:0] gen4_eie_cnt_r;
always @(*) begin

  state_m = state_w;
  flag = flag_w;
  gen4_eie_cnt = gen4_eie_cnt_r;
  pat_count_m = pat_count_w; 
  eieos_count_m = eieos_count_w; 
  skp_count_m = skp_count_w; 
  PHY_TXDATA_m = 'b0;
  PHY_TXDATAK_m = 'b0;
  PHY_TXDATA_VALID_m = 'b0; 
  PHY_TXSTART_BLOCK_m = 'b1;
  PHY_TXSYNC_HEADER_m = 'b0;
  PHY_TXELECIDLE_w      = 'b1;
  case (state_w)

    PAT_GEN_HOME : begin

      pat_count_m = 'b0; 
      eieos_count_m = 'b0;
      skp_count_m = 'b0; 
      PHY_TXELECIDLE_w = PHY_TXELECIDLE_w;
      if (EN)  begin
        if (PHY_RATE == 3'b000)
          state_m = PAT_GEN_GEN12_SKP_1;
        else if (PHY_RATE == 3'b001)
          state_m = PAT_GEN_GEN12_SKP_1;
        else if (PHY_RATE == 3'b010)
          state_m = PAT_GEN_GEN3_EIEOS_1;
        else // (PHY_RATE == 3'b011)
          state_m = PAT_GEN_GEN4_EIEOS_1;
      end else begin
        state_m = PAT_GEN_HOME;
      end

    end

    // Gen12
    
    PAT_GEN_GEN12_SKP_1 : begin

      if (EN & ((PHY_RATE == 3'b000) || (PHY_RATE == 3'b001))) begin

        PHY_TXDATA_m = `GEN12_SKP0_TX_DATA;
        PHY_TXDATAK_m = `GEN12_CHIK;
        PHY_TXDATA_VALID_m = 'b1; 
        state_m = PAT_GEN_GEN12_SKP_2;
        PHY_TXELECIDLE_w = 1'b0;
      end else begin

        state_m = PAT_GEN_HOME;

      end 

    end
    PAT_GEN_GEN12_SKP_2 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN12_SKP1_TX_DATA;
      PHY_TXDATAK_m = `GEN12_CHIK;
      PHY_TXDATA_VALID_m = 'b1; 
      state_m = PAT_GEN_GEN12_PAT;

    end
    PAT_GEN_GEN12_PAT : begin
      PHY_TXELECIDLE_w = 1'b0;
      if (pat_count_w == 64) begin

        PHY_TXDATA_m = `GEN12_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
	       pat_count_m = 'b0;
        state_m = PAT_GEN_GEN12_SKP_1;

      end else begin

        PHY_TXDATA_m = `GEN12_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
        pat_count_m = pat_count_w + 1'b1; 
        state_m = PAT_GEN_GEN12_PAT;

      end

    end

    // Gen3
        
    PAT_GEN_GEN3_EIEOS_1 : begin
	    
      if ((EN) && (PHY_RATE == 3'b010)) begin
        PHY_TXELECIDLE_w = 1'b0;
        PHY_TXDATA_m = `GEN3_EIEOS_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
        PHY_TXSTART_BLOCK_m = 'b1;
        PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
        state_m = PAT_GEN_GEN3_EIEOS_2;     
    
      end else begin
        PHY_TXELECIDLE_w = 1'b1;
        state_m = PAT_GEN_HOME;
      end 
    end

    PAT_GEN_GEN3_EIEOS_2 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_EIEOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_EIEOS_3;

    end
    PAT_GEN_GEN3_EIEOS_3 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_EIEOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_EIEOS_4;

    end
    PAT_GEN_GEN3_EIEOS_4 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_EIEOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_PAT_ST;

    end
    PAT_GEN_GEN3_PAT_ST : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b1;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_PAT_Z0;

    end
    PAT_GEN_GEN3_PAT_Z0 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
      state_m = PAT_GEN_GEN3_PAT_Z1;

    end
    PAT_GEN_GEN3_PAT_Z1 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
      state_m = PAT_GEN_GEN3_PAT_Z2;

    end
    PAT_GEN_GEN3_PAT_Z2 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      if (pat_count_w == 14) begin

        pat_count_m = 'b0; 
        state_m = PAT_GEN_GEN3_PAT_Z3;

      end else begin // Continue Pat

        pat_count_m = pat_count_w + 1'b1; 
        state_m = PAT_GEN_GEN3_PAT_ST;

      end

    end



  PAT_GEN_GEN3_EIOS_1 : begin
	          PHY_TXELECIDLE_w = 1'b0;
        PHY_TXDATA_m = `GEN3_EIOS_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
        PHY_TXSTART_BLOCK_m = 'b1;
        PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

        state_m = PAT_GEN_GEN3_EIOS_2;
     
      end 

    PAT_GEN_GEN3_EIOS_2 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_EIOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_EIOS_3;

    end
    PAT_GEN_GEN3_EIOS_3 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_EIOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_EIOS_4;

    end
    PAT_GEN_GEN3_EIOS_4 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_EIOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_EIOS_5;

    end

    PAT_GEN_GEN3_EIOS_5 : begin
      PHY_TXELECIDLE_w = 1'b1;
      PHY_TXDATA_m =       'b0;
      PHY_TXDATA_VALID_m = 'b0; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = 'b0;

      state_m = PAT_GEN_HOME;
    end


    PAT_GEN_GEN3_PAT_Z3 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = 64'b0;
      PHY_TXDATA_VALID_m = 'b0; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = 2'b00;
      state_m =  PAT_GEN_GEN3_PAT_ST1;
    end
    PAT_GEN_GEN3_PAT_ST1 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b1;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN3_PAT_Z01;

    end
    PAT_GEN_GEN3_PAT_Z01 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
      state_m = PAT_GEN_GEN3_PAT_Z11;

    end
    PAT_GEN_GEN3_PAT_Z11 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
      state_m = PAT_GEN_GEN3_PAT_Z21;

    end
    PAT_GEN_GEN3_PAT_Z21 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN3_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      if (pat_count_w == 15) begin

        pat_count_m = 'b0; 

        state_m = PAT_GEN_GEN3_PAT_Z4;

      end else begin // Continue Pat

        pat_count_m = pat_count_w + 1'b1; 
        state_m = PAT_GEN_GEN3_PAT_ST1;

      end

    end
    PAT_GEN_GEN3_PAT_Z4 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = 64'b0;
      PHY_TXDATA_VALID_m = 'b0; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = 2'b00;
      state_m = PAT_GEN_GEN3_EIEOS_1;

    end

    // Gen4
        
    PAT_GEN_GEN4_EIEOS_1 : begin

      if ((EN) && (PHY_RATE == 3'b011)) begin
      PHY_TXELECIDLE_w = 1'b0;
        PHY_TXDATA_m = `GEN4_EIEOS_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
        PHY_TXSTART_BLOCK_m = 'b1;
        PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
        
        state_m = PAT_GEN_GEN4_EIEOS_2;
        if (flag == 0)
            gen4_eie_cnt = gen4_eie_cnt + 1'b1;
        else 
            gen4_eie_cnt = gen4_eie_cnt;
      end else begin
      PHY_TXELECIDLE_w = 1'b1;
        state_m = PAT_GEN_HOME;

      end 

    end
    
     PAT_GEN_GEN4_EIEOS_2 : begin

      if ((EN) && (PHY_RATE == 3'b011)) begin
      PHY_TXELECIDLE_w = 1'b0;
        PHY_TXDATA_m = `GEN4_EIEOS_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
        PHY_TXSTART_BLOCK_m = 'b0;
        PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

        state_m = PAT_GEN_GEN4_EIEOS_3;

      end else begin
      PHY_TXELECIDLE_w = 1'b1;
        state_m = PAT_GEN_HOME;

      end 

    end
    
    
     PAT_GEN_GEN4_EIEOS_3 : begin

      if ((EN) && (PHY_RATE == 3'b011)) begin
      PHY_TXELECIDLE_w = 1'b0;
        PHY_TXDATA_m = `GEN4_EIEOS_TX_DATA;
        PHY_TXDATA_VALID_m = 'b1; 
        PHY_TXSTART_BLOCK_m = 'b1;
        PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

        state_m = PAT_GEN_GEN4_EIEOS_4;

      end else begin
      PHY_TXELECIDLE_w = 1'b1;
        state_m = PAT_GEN_HOME;

      end 

    end
    
    
    PAT_GEN_GEN4_EIEOS_4: begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_EIEOS_TX_DATA;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      pat_count_m = pat_count_w + 1'b1; 

      if (flag == 1'b0) begin
          state_m =  PAT_GEN_GEN4_EIEOS_1;
      end else if (eieos_count_w == 127) begin

        state_m = PAT_GEN_GEN4_SKP_0;

      end else begin

        state_m = PAT_GEN_GEN4_PAT_ST;

      end
      flag  =  (gen4_eie_cnt == 2'h3) ? 1'b1 : 1'b0; 

    end
    PAT_GEN_GEN4_PAT_ST : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b1;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
      state_m = PAT_GEN_GEN4_PAT_Z0;

    end
    PAT_GEN_GEN4_PAT_Z0 : begin
      PHY_TXELECIDLE_w = 1'b0;      
      PHY_TXDATA_m = `GEN4_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;
      if (pat_count_w == 30) begin

        pat_count_m = 'b0; 
        eieos_count_m = eieos_count_w + 1;

        state_m = PAT_GEN_GEN4_PAT_Z1;

      end else begin // Continue Pat

        pat_count_m = pat_count_w + 1'b1; 
        state_m = PAT_GEN_GEN4_PAT_ST;

      end

    end
    PAT_GEN_GEN4_PAT_Z1 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = 64'b0;
      PHY_TXDATA_VALID_m = 'b0; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = 2'b00;

      state_m = PAT_GEN_GEN4_EIEOS_1;

    end

    // Data Stream Phase

    PAT_GEN_GEN4_SKP_0 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_SKP_PAT_0;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b1;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN4_SKP_1;

    end
    
    
    PAT_GEN_GEN4_SKP_1 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_SKP_PAT_0;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN4_SKP_2;

    end
    
    
    PAT_GEN_GEN4_SKP_2 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_SKP_PAT_0;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      state_m = PAT_GEN_GEN4_SKP_3;

    end
    
    
    PAT_GEN_GEN4_SKP_3 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_SKP_PAT_1;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_OS;

      pat_count_m = pat_count_w + 1'b1; 
      state_m = PAT_GEN_GEN4_PAT_ST ;//PAT_GEN_GEN4_DAT_ST;

    end
    PAT_GEN_GEN4_DAT_ST : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b1;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_DS;
      if ((skp_count_w == 22) & ((pat_count_w == 29) | (pat_count_w == 31))) begin

        state_m = PAT_GEN_GEN4_DAT_ED0;

      end else begin

        state_m = PAT_GEN_GEN4_DAT_Z0;

      end

    end
    PAT_GEN_GEN4_DAT_Z0 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_DATA_PAT;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_DS;
      if (pat_count_w == 31) begin

        pat_count_m = 'b0; 

        state_m = PAT_GEN_GEN4_DAT_Z1;

      end else begin // Continue Pat

        pat_count_m = pat_count_w + 1'b1; 

        state_m = PAT_GEN_GEN4_DAT_ST;

      end

    end
    PAT_GEN_GEN4_DAT_Z1 : begin

      if ((EN) && (PHY_RATE == 3'b011)) begin
         PHY_TXELECIDLE_w = 1'b0;
         PHY_TXDATA_m = {DW{1'b0}};
         PHY_TXDATA_VALID_m = 'b0; 
         PHY_TXSTART_BLOCK_m = 'b0;
         PHY_TXSYNC_HEADER_m = 2'b00;
   
         if (skp_count_w == 22) begin
   
           skp_count_m = 'h0;
   
           state_m = PAT_GEN_GEN4_SKP_0;
   
         end else begin

           skp_count_m = skp_count_w + 1'b1; 
   
           state_m = PAT_GEN_GEN4_DAT_ST;
   
         end

      end else begin

        state_m = PAT_GEN_HOME;

      end 

    end
    PAT_GEN_GEN4_DAT_ED0 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_EDS_PAT0;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_DS;
      state_m = PAT_GEN_GEN4_DAT_ED1;
    end  
      
    PAT_GEN_GEN4_DAT_ED1 : begin
      PHY_TXELECIDLE_w = 1'b0;
      PHY_TXDATA_m = `GEN4_TX_EDS_PAT1;
      PHY_TXDATA_VALID_m = 'b1; 
      PHY_TXSTART_BLOCK_m = 'b0;
      PHY_TXSYNC_HEADER_m = `GEN34_SYNC_HDR_DS;  
      
      if (pat_count_w == 29) begin

        pat_count_m = pat_count_w + 1; 

        state_m = PAT_GEN_GEN4_SKP_0;

      end else begin // (pat_count_w == 30)

        pat_count_m = 0; 

        state_m = PAT_GEN_GEN4_DAT_Z1;

      end
    end
    default : begin
      state_m = PAT_GEN_HOME;
      PHY_TXELECIDLE_w = 1'b1;
    end

  endcase
   
end

always @(posedge CLK) begin

  if (RST) begin
    PHY_TXELECIDLE_r <= #(TCQ) 1'b0;
    state_r <= #(TCQ) 'b0;
    flag_r <= #(TCQ) 'd0;
    gen4_eie_cnt_r <= #(TCQ) 'd0;
    pat_count_r <= #(TCQ) 'b0;
    eieos_count_r <= #(TCQ) 'b0;
    skp_count_r <= #(TCQ) 'b0;
    PHY_TXDATA_r <= #(TCQ) 'b0;
    PHY_TXDATAK_r <= #(TCQ) 'b0;
    PHY_TXDATA_VALID_r <= #(TCQ)'b0; 
    PHY_TXSTART_BLOCK_r <= #(TCQ) 'b1;
    PHY_TXSYNC_HEADER_r <= #(TCQ) 'b0;

  end else begin

    state_r <= #(TCQ) state_m;
    flag_r <= #(TCQ) flag;
    gen4_eie_cnt_r <= #(TCQ) gen4_eie_cnt;
    pat_count_r <= #(TCQ) pat_count_m;
    eieos_count_r <= #(TCQ) eieos_count_m;
    skp_count_r <= #(TCQ) skp_count_m;
    PHY_TXDATA_r <= #(TCQ) PHY_TXDATA_m; 
    PHY_TXDATAK_r <= #(TCQ) PHY_TXDATAK_m; 
    PHY_TXELECIDLE_r <= #(TCQ) PHY_TXELECIDLE_w;
    PHY_TXDATA_VALID_r <= #(TCQ) PHY_TXDATA_VALID_m;
    PHY_TXSTART_BLOCK_r <= #(TCQ) PHY_TXSTART_BLOCK_m;      
    PHY_TXSYNC_HEADER_r <= #(TCQ) PHY_TXSYNC_HEADER_m;                    

  end

end

assign state_w = state_r;
assign flag_w = flag_r;
assign pat_count_w = pat_count_r;
assign eieos_count_w = eieos_count_r;
assign skp_count_w = skp_count_r;
assign PHY_TXDATA = PHY_TXDATA_r;
assign PHY_TXELECIDLE = PHY_TXELECIDLE_r;
assign PHY_TXDATAK = PHY_TXDATAK_r; 
assign PHY_TXDATA_VALID = PHY_TXDATA_VALID_r;
assign PHY_TXSTART_BLOCK = PHY_TXSTART_BLOCK_r;      
assign PHY_TXSYNC_HEADER = PHY_TXSYNC_HEADER_r;                    

endmodule
