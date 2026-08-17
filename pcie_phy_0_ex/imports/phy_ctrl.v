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
// File       : phy_ctrl.v
// Version    : 1.0 
//-----------------------------------------------------------------------------
//-------------------------------------------------------------------------------
//--
//-- Description:
//--    PCIE4 PHY Controller
//--
//-------------------------------------------------------------------------------
`timescale 1ps/1ps

module phy_ctrl #(

   parameter integer   PHY_LANE  = 1,
   parameter integer   DW        = 32,
   parameter           TCQ       = 1


)(                                                         

   input  wire                       CLK,                          
   input  wire                       RST,  
  
   // TX Data 
   output  wire [(PHY_LANE*DW)-1:0]  PHY_TXDATA,            
   output  wire [(PHY_LANE* 2)-1:0]  PHY_TXDATAK,    
   output  wire [PHY_LANE-1:0]       PHY_TXDATA_VALID,
   output  wire [PHY_LANE-1:0]       PHY_TXSTART_BLOCK,      
   output  wire [(PHY_LANE* 2)-1:0]  PHY_TXSYNC_HEADER,                    

   input wire [(PHY_LANE*DW)-1:0]    PHY_RXDATA,            
   input wire [(PHY_LANE* 2)-1:0]    PHY_RXDATAK,       
   input wire [PHY_LANE-1:0]         PHY_RXDATA_VALID,         
   input wire [PHY_LANE-1:0]         PHY_RXSTART_BLOCK,        
   input wire [(PHY_LANE* 2)-1:0]    PHY_RXSYNC_HEADER,        

   // PHY Command
   output  wire                      PHY_TXDETECTRX,        
   output  wire [PHY_LANE-1:0]       PHY_TXELECIDLE,        
   output  wire [PHY_LANE-1:0]       PHY_TXCOMPLIANCE,      
   output  wire [PHY_LANE-1:0]       PHY_RXPOLARITY,        
   output  wire [1:0]                PHY_POWERDOWN,         
   output  wire [2:0]                PHY_RATE,              
    
   // PHY Status
   input wire [PHY_LANE-1:0]         PHY_RXVALID,               
   input wire [PHY_LANE-1:0]         PHY_PHYSTATUS,          
   input wire                        PHY_PHYSTATUS_RST,         
   input wire [PHY_LANE-1:0]         PHY_RXELECIDLE,         
   input wire [(PHY_LANE*3)-1:0]     PHY_RXSTATUS,                       
    
   // TX Driver
   output  wire [ 2:0]               PHY_TXMARGIN,          
   output  wire                      PHY_TXSWING,           
   output  wire                      PHY_TXDEEMPH,    
    
   // TX Equalization (Gen3/4)
   output  wire [(PHY_LANE*2)-1:0]   PHY_TXEQ_CTRL,      
   output  wire [(PHY_LANE*4)-1:0]   PHY_TXEQ_PRESET,       
   output  wire [(PHY_LANE*6)-1:0]   PHY_TXEQ_COEFF,                                                            

   input wire [ 5:0]                 PHY_TXEQ_FS,           
   input wire [ 5:0]                 PHY_TXEQ_LF,           
   input wire [(PHY_LANE*18)-1:0]    PHY_TXEQ_NEW_COEFF,        
   input wire [PHY_LANE-1:0]         PHY_TXEQ_DONE,         

   // RX Equalization (Gen3/4)
   output  wire [(PHY_LANE*2)-1:0]   PHY_RXEQ_CTRL,     
   output  wire [(PHY_LANE*4)-1:0]   PHY_RXEQ_TXPRESET,      

   input wire [PHY_LANE-1:0]         PHY_RXEQ_PRESET_SEL,    
   input wire [(PHY_LANE*18)-1:0]    PHY_RXEQ_NEW_TXCOEFF,   
   input wire [PHY_LANE-1:0]         PHY_RXEQ_ADAPT_DONE,     
   input wire [PHY_LANE-1:0]         PHY_RXEQ_DONE,


   output reg                        as_mac_in_detect, 
   output reg                        as_cdr_hold_req, 

   // Debug output

(* mark_debug *)   output wire [7:0]                  debug_state, 

   // Bringup Control Inputs
(* mark_debug *)   input wire                        tx_elec_idle,
(* mark_debug *)   input wire                        phy_ready_en,
(* mark_debug *)   input wire                        gen1_en,
(* mark_debug *)   input wire                        gen2_en,
(* mark_debug *)   input wire                        gen3_en,
(* mark_debug *)   input wire                        gen4_en
    

  );

  localparam      PHY_BUP_HOME     = 8'h00;
  localparam      PHY_BUP_PHY_PU   = 8'h01;
  localparam      PHY_BUP_PHY_RDY0 = 8'h02;
  localparam      PHY_BUP_PHY_RDY1 = 8'h03;
  localparam      PHY_BUP_PHY_RDY2 = 8'h04;
  localparam      PHY_BUP_PHY_RDY3 = 8'h05;

  reg             EN_m;
  reg             EN_r;
  wire            EN;

  reg  [7:0]      state_m;
  reg  [7:0]      state_r;
  wire [7:0]      state_w;

  reg  [1:0]      PHY_POWERDOWN_m;
  reg  [1:0]      PHY_POWERDOWN_r;

  reg  [2:0]      PHY_RATE_m;
  reg  [2:0]      PHY_RATE_r;

  reg             PHY_TXDEEMPH_m;
  reg             PHY_TXDEEMPH_r;

  wire            phy_ready;

  reg             no_rate_change_m;
  reg             no_rate_change_r;
  wire            no_rate_change_w;

  wire  [16:0]     rx_ei_to_rx_data_valid_m;
  reg  [16:0]     rx_ei_to_rx_data_valid_r;
(* mark_debug *)  wire [16:0]     rx_ei_to_rx_data_valid_w;

  reg  [PHY_LANE-1:0]   PHY_RXELECIDLE_r;         
  wire [PHY_LANE-1:0]   PHY_RXELECIDLE_w;         


  reg  [15:0]     ltssm_mimic_cnt;
  wire [5:0]      cfg_ltssm_state;

  always @(posedge CLK) begin
    if (RST)
      ltssm_mimic_cnt <= 'd0;
    else if (ltssm_mimic_cnt < 16'hFFF0)
      ltssm_mimic_cnt <= ltssm_mimic_cnt + 1'b1;
    else
      ltssm_mimic_cnt <= ltssm_mimic_cnt;
  end

  assign cfg_ltssm_state = ltssm_mimic_cnt[15:10];

  always @(posedge CLK) begin
    if (RST) begin
      as_cdr_hold_req    <= 1'b0;
      as_mac_in_detect   <= 1'b1;
    end 
    else begin
      // If LTSSM state is Recovery.Speed, L1.Entry, L1.Idle, Loopback.Entry_slave, or Loopback.Speed
      as_cdr_hold_req    <= (cfg_ltssm_state == 6'h0C) | (cfg_ltssm_state == 6'h17) |
      (cfg_ltssm_state == 6'h18) | (cfg_ltssm_state == 6'h24) |
      (cfg_ltssm_state == 6'h2D);
      // If LTSSM state is Detect.Quiet or Detect.Active
      as_mac_in_detect   <= (cfg_ltssm_state == 6'h00) | (cfg_ltssm_state == 6'h01);
    end
  end

  always @(*) begin

    PHY_TXDEEMPH_m = 'b0;
    EN_m = EN;
    PHY_RATE_m = PHY_RATE;
    PHY_POWERDOWN_m =  PHY_POWERDOWN;
    no_rate_change_m = no_rate_change_w;
    state_m = state_w;

    case (state_w)

      PHY_BUP_HOME : begin

        EN_m = 'b0;
        PHY_RATE_m = 'b0;
	PHY_POWERDOWN_m = 2'b10;

	// Power Up 
        if (phy_ready & ~|PHY_PHYSTATUS) begin
	  PHY_POWERDOWN_m = 2'b00;
          state_m = PHY_BUP_PHY_PU;
        end else begin
          state_m = PHY_BUP_HOME;
	end

      end

      PHY_BUP_PHY_PU : begin

        if (|PHY_PHYSTATUS)
          state_m = PHY_BUP_PHY_RDY0;
        else
          state_m = PHY_BUP_PHY_PU;

      end

      PHY_BUP_PHY_RDY0 : begin

        PHY_RATE_m = 'b0;

    	// Speed Change to Gen2/3/4
        if (phy_ready && (gen1_en || gen2_en || gen3_en || gen4_en)) begin
          EN_m = 1'b0;
	         if (gen1_en) begin
            PHY_RATE_m = 3'b000;
            no_rate_change_m = 1'b1;          
	         end else if (gen3_en && !gen4_en && (PHY_RATE != 3'b010))
            PHY_RATE_m = 3'b010;
          else if (gen3_en && gen4_en && (PHY_RATE != 3'b011))
            PHY_RATE_m = 3'b011;
          else if (gen3_en && !gen4_en && (PHY_RATE == 3'b010)) begin
            PHY_RATE_m = 3'b010;
            no_rate_change_m = 1'b1;
	         end else if (gen3_en && gen4_en && (PHY_RATE == 3'b011)) begin
            PHY_RATE_m = 3'b011;
            no_rate_change_m = 1'b1;
          end else if ( gen4_en && (PHY_RATE == 3'b011)) begin
            PHY_RATE_m = 3'b011;
            no_rate_change_m = 1'b1;
          end else if ( gen3_en && (PHY_RATE == 3'b010)) begin
            PHY_RATE_m = 3'b010;
            no_rate_change_m = 1'b1;
          end else if ( gen2_en && (PHY_RATE == 3'b01)) begin
            PHY_RATE_m = 3'b01;
            no_rate_change_m = 1'b1;
	         end else if (gen4_en) begin
            PHY_RATE_m = 3'b011;
          end else if (gen3_en) begin
            PHY_RATE_m = 3'b010;
          end else if (gen2_en) begin
            PHY_RATE_m = 3'b001;
          end else 
            PHY_RATE_m = 3'b000;
            state_m = PHY_BUP_PHY_RDY1;
        end else begin
          state_m = PHY_BUP_PHY_RDY0;
        end
      end

      PHY_BUP_PHY_RDY1 : begin

        EN_m = 1'b0;
        if ((|PHY_PHYSTATUS) || (no_rate_change_w == 1'b1))
          state_m = PHY_BUP_PHY_RDY2;
        else
          state_m = PHY_BUP_PHY_RDY1;
      
      end

      PHY_BUP_PHY_RDY2 : begin

        // Take it down to Gen1
        if (phy_ready && ~(gen1_en || gen2_en || gen3_en || gen4_en)) begin

          EN_m = 1'b0;
          PHY_RATE_m = 3'b000;
          state_m = PHY_BUP_PHY_RDY3;

        // Take it up to Gen4 . If Gen4 is set, go to Gen4
	end else if (phy_ready && gen4_en && PHY_RATE != 3'b011)  begin

          EN_m = 1'b0;
          PHY_RATE_m = 3'b011;
          state_m = PHY_BUP_PHY_RDY3;

         // Take it down to Gen3
	end else if (phy_ready && gen3_en  && PHY_RATE != 3'b010) begin

          EN_m = 1'b0;
          PHY_RATE_m = 3'b010;
          state_m = PHY_BUP_PHY_RDY3;

// Take it down to Gen2
	end else if (phy_ready && gen2_en  && PHY_RATE != 3'b001)  begin

          EN_m = 1'b0;
          PHY_RATE_m = 3'b001;
          state_m = PHY_BUP_PHY_RDY3;

// Take it down to Gen2
	end else if (phy_ready && gen1_en &&  PHY_RATE != 3'b000)  begin

          EN_m = 1'b0;
          PHY_RATE_m = 3'b001;
          state_m = PHY_BUP_PHY_RDY3;

	end else begin // Stay

          EN_m = 1'b1;
          state_m = PHY_BUP_PHY_RDY2;

	end	

      end

      PHY_BUP_PHY_RDY3 : begin

        EN_m = 1'b0;
      	if ((|PHY_PHYSTATUS) || (no_rate_change_w == 1'b1)) begin
          state_m = PHY_BUP_PHY_RDY0;
	         no_rate_change_m = 1'b0;
	      end else
          state_m = PHY_BUP_PHY_RDY3;
      
      end

      default : begin
        state_m = PHY_BUP_HOME;
      end

    endcase
  

  end


assign rx_ei_to_rx_data_valid_m = ((PHY_RXELECIDLE_w && PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0]) ? 'b0 : 
                                  ((!PHY_RXELECIDLE_w && PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0]) ? 'b0 :  
                                  (((PHY_RXELECIDLE_w && !PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0]) || ((!PHY_RXELECIDLE_w && !PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0])) ? rx_ei_to_rx_data_valid_w + 1'b1 : (!PHY_RXELECIDLE[0] && PHY_RXDATA_VALID[0]) ? rx_ei_to_rx_data_valid_w : rx_ei_to_rx_data_valid_r;

/*
  always @(*) begin
    if ((PHY_RXELECIDLE_w && PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0])
      rx_ei_to_rx_data_valid_m = 'b0;
    else if ((!PHY_RXELECIDLE_w && PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0])
      rx_ei_to_rx_data_valid_m = 'b0;
    else if (((PHY_RXELECIDLE_w && !PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0]) ||
             ((!PHY_RXELECIDLE_w && !PHY_RXELECIDLE[0]) && !PHY_RXDATA_VALID[0]))
      rx_ei_to_rx_data_valid_m = rx_ei_to_rx_data_valid_w + 1'b1;
    else if (!PHY_RXELECIDLE[0] && PHY_RXDATA_VALID[0])
      rx_ei_to_rx_data_valid_m = rx_ei_to_rx_data_valid_w;
  end
*/

  always @(posedge CLK) begin

    if (RST) begin

      EN_r <= #(TCQ) 'b0;
      state_r <= #(TCQ) PHY_BUP_HOME;
      PHY_POWERDOWN_r = #(TCQ) 2'b10;
      PHY_RATE_r <= #(TCQ) 'h0;
      PHY_TXDEEMPH_r <= #(TCQ) 'h0;  // Gen1/2 Deemph
      no_rate_change_r <= #(TCQ) 'b0;
      rx_ei_to_rx_data_valid_r <= #(TCQ) 'b0;
      PHY_RXELECIDLE_r <= #(TCQ) 'b0;         

    end else begin

      EN_r <= #(TCQ) EN_m;
      state_r <= #(TCQ) state_m;
      PHY_POWERDOWN_r = #(TCQ) PHY_POWERDOWN_m;
      PHY_RATE_r <= #(TCQ) PHY_RATE_m;
      PHY_TXDEEMPH_r <= #(TCQ) PHY_TXDEEMPH_m;
      no_rate_change_r <= #(TCQ) no_rate_change_m;
      rx_ei_to_rx_data_valid_r <= #(TCQ) rx_ei_to_rx_data_valid_m;
      PHY_RXELECIDLE_r <= #(TCQ) PHY_RXELECIDLE[0];         

    end

  end

  phy_ctrl_pat_gen #(

    .PHY_LANE(PHY_LANE),
    .DW(DW),
    .TCQ(TCQ)

  ) pat_gen (

    .CLK(CLK),
    .RST(RST),
    .EN(EN),
    .PHY_RATE(PHY_RATE),
    .PHY_TXELECIDLE (PHY_TXELECIDLE),
    .PHY_TXDATA(PHY_TXDATA),
    .PHY_TXDATAK(PHY_TXDATAK),
    .PHY_TXDATA_VALID(PHY_TXDATA_VALID),
    .PHY_TXSTART_BLOCK(PHY_TXSTART_BLOCK),
    .PHY_TXSYNC_HEADER(PHY_TXSYNC_HEADER)

  );

  assign PHY_TXDETECTRX = 'b0;        
  assign PHY_TXCOMPLIANCE = {PHY_LANE{1'b0}};      
  assign PHY_RXPOLARITY = {PHY_LANE{1'b0}};      
  assign PHY_TXMARGIN = 'b0;          
  assign PHY_TXSWING = 'b0;           
    
  // TX Equalization (Gen3/4)
  assign PHY_TXEQ_CTRL = 'b0;
  assign PHY_TXEQ_PRESET = 'b0;       
  assign PHY_TXEQ_COEFF = 'b0;                                                            

  // RX Equalization (Gen3/4)
  assign PHY_RXEQ_CTRL = 'b0;    
  assign PHY_RXEQ_TXPRESET = 'b0;      

 // assign PHY_TXELECIDLE = {PHY_LANE{tx_elec_idle}};//VG
//  assign PHY_TXELECIDLE = (gen1_en ) ? {PHY_LANE{tx_elec_idle}} : {PHY_LANE{~EN}};
  assign EN = EN_r;
  assign state_w = state_r;

  assign PHY_POWERDOWN = PHY_POWERDOWN_r;
  assign PHY_RATE = PHY_RATE_r;
  assign PHY_TXDEEMPH = PHY_TXDEEMPH_r;

  assign phy_ready = phy_ready_en;
  assign debug_state = state_r;

  assign no_rate_change_w = no_rate_change_r;

  assign rx_ei_to_rx_data_valid_w = rx_ei_to_rx_data_valid_r;
  assign PHY_RXELECIDLE_w = PHY_RXELECIDLE_r;         

endmodule
