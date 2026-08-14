`timescale 1ns / 1ns
// ********************************************************************/
// Microchip Corporation Proprietary and Confidential
// Copyright 2024 Microchip Corporation.  All rights reserved.
//
// ANY USE OR REDISTRIBUTION IN PART OR IN WHOLE MUST BE HANDLED IN
// ACCORDANCE WITH THE MICROSEMI LICENSE AGREEMENT AND MUST BE APPROVED
// IN ADVANCE IN WRITING.
//
// Description:  COREAXI4INTERCONNECT. 
//
// SVN Revision Information:
// SVN $Revision: 44524 $
// SVN $Date: 2023-10-16 18:55:34 +0530 (Mon, 16 Oct 2023) $
//
//
// Notes:
//
// *********************************************************************/
module caxi4interconnect_DWC_RChannel_SlvRid_Arb #
(
  parameter integer       ID_WIDTH        = 1,
  parameter integer       TOTAL_IDS       = (2 ** ID_WIDTH),
  parameter integer       FIXED_PRIORITY  = 0
)
(
  input                       ACLK,
  input                       sysReset,
  input  [TOTAL_IDS-1:0]      req_n,  
  input  [TOTAL_IDS-1:0]      arb_ctrl,
  output reg [TOTAL_IDS-1:0]  grant_n
);

wire  [ID_WIDTH-1:0] binary_encode;
reg                  all_req_inactive; 
reg                  arb_enable;


// Onehot to binary conveter

genvar k,l;
generate
  for (k=0; k<ID_WIDTH; k=k+1)
    begin : kl
  	  wire [TOTAL_IDS-1:0] tmp_mask;
  	  for (l=0; l<TOTAL_IDS; l=l+1)
  	    begin : ll
  		  assign tmp_mask[l] = l[k];
  	    end	
  	  assign binary_encode[k] = |(tmp_mask & ~grant_n);
    end	
endgenerate

//

// Enable signal when first time any bit of data fifo empty goes low. This signal is used to control 
// arb_enable. 

  always@(posedge ACLK or negedge sysReset)
   if(~sysReset)
     all_req_inactive <= 1'b1;
   else if(~(& req_n))
     all_req_inactive <= 1'b0;
   else if((& req_n) & (~(| arb_ctrl)))
     all_req_inactive <= 1'b1;

// After reset, all the fifos are empty so arbitration enable should be high. When first time any bit of 
// data fifo empty goes high, arb_enable is driven to zero. It is again asserted to one when the particular 
// bit of data fifo empty goes high and the same bit of arb_ctrl signal goes low. arb_ctrl signal is MASTER_RVALID
// which indicates data is sent to the master. 
 
  always@(*)
   if(all_req_inactive)
     arb_enable = 1'b1;
   else 
     arb_enable = ((req_n[binary_encode] == 1'b1) && (arb_ctrl[binary_encode] == 1'b0));


generate 
  if(FIXED_PRIORITY == 1)
    begin 
      always@(posedge ACLK or negedge sysReset)
        if(~sysReset)
          grant_n <= {TOTAL_IDS{1'b1}};
       	else if(arb_enable)
          grant_n <= (~(~req_n & ~(~req_n-1)));      
	end 
  else 
    begin 
	  reg  [TOTAL_IDS-1:0]   rotate_prio;
	  wire [2*TOTAL_IDS-1:0] double_req = {~req_n,~req_n};
	  wire [2*TOTAL_IDS-1:0] double_grant = double_req & ~(double_req-rotate_prio);
	  
	  always@(posedge ACLK or negedge sysReset)
	    if(~sysReset)
		  rotate_prio <= 1;
		else if(~arb_enable)
		  rotate_prio <= ~{grant_n[TOTAL_IDS-2:0],grant_n[TOTAL_IDS-1]};
	  
      always@(posedge ACLK or negedge sysReset)
        if(~sysReset)
          grant_n <= {TOTAL_IDS{1'b1}};
       	else if(arb_enable)
          grant_n <= ~(double_grant[TOTAL_IDS-1:0] | double_grant[2*TOTAL_IDS-1:TOTAL_IDS]);	  
    end 	
endgenerate	


endmodule 