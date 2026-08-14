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



module caxi4interconnect_RAM_BLOCK #

	(
		parameter integer	MEM_DEPTH	 = 1024,
		parameter integer	ADDR_WIDTH	 = 10,
		parameter integer	DATA_WIDTH	 = 32,
		parameter integer	MASTER_BCHAN = 0
	)
	(
		input wire clk,

		input wire wr_en,
		input wire [ADDR_WIDTH-1:0] rd_addr,
		input wire [ADDR_WIDTH-1:0] wr_addr,
		input wire [DATA_WIDTH-1:0] data_in,

		output wire [DATA_WIDTH-1:0] data_out
	);

	
	
	
	generate 
	  if(MASTER_BCHAN)
	    begin
	      reg [DATA_WIDTH-1:0] mem [MEM_DEPTH-1:0] /* synthesis syn_ramstyle = "uram" */;
		  
		  assign data_out = mem[rd_addr];
		  
	      always @(posedge clk) 
		    begin
		      if (wr_en) 
			    begin
			      mem[wr_addr] <= data_in;
		        end
	        end
        end		
	  else 
	    begin 
	      reg [DATA_WIDTH-1:0] mem [MEM_DEPTH-1:0];
		  
		  assign data_out = mem[rd_addr];
		  
	      always @(posedge clk) 
		    begin
		      if (wr_en) 
			    begin
			      mem[wr_addr] <= data_in;
		        end
	        end
		end 
	endgenerate
endmodule
