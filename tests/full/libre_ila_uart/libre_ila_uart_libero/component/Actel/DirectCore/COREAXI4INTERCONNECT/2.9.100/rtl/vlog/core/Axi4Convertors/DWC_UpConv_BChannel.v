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



module caxi4interconnect_DWC_UpConv_BChannel #

	(
		parameter integer	ID_WIDTH	= 1,
		parameter integer	USER_WIDTH	= 1,
		parameter integer	ADDR_FIFO_DEPTH	= 3,
		parameter           READ_INTERLEAVE = 0

	)
	(

		input wire                    sysReset,
		input wire                    ACLK,

		// W channel
		output wire [ID_WIDTH-1:0]    MASTER_BID,
		output wire [1:0] 		      MASTER_BRESP,
		output wire [USER_WIDTH-1:0]  MASTER_BUSER,
		output wire                   MASTER_BVALID,
		input wire                    MASTER_BREADY,

		// W channel
		input wire[ID_WIDTH-1:0]      SLAVE_BID,
		input wire[1:0]               SLAVE_BRESP,
		input wire[USER_WIDTH-1:0]    SLAVE_BUSER,
		input wire                    SLAVE_BVALID,
		output wire                   SLAVE_BREADY,

        output wire                   bchan_cmd_fifo_full,
		input wire		   	          wr_en_cmd,
		input wire[ID_WIDTH:0]		  BRespFifoWrData
	);

	
    localparam           TOTAL_IDS       = READ_INTERLEAVE ? (2 ** ID_WIDTH) : 1;
	
	
	wire [TOTAL_IDS-1:0] cmd_fifo_empty_temp;
	wire                 cmd_fifo_empty;
	

	wire                 rd_en_cmd;
    
	

genvar id_range; 
	
generate  
  if(READ_INTERLEAVE)
    begin 
	  wire [TOTAL_IDS-1:0] BRespFifoRdData;
      wire [TOTAL_IDS-1:0] cmd_fifo_full;
	  
	  assign bchan_cmd_fifo_full = (| cmd_fifo_full);
	  
      for(id_range = 0; id_range < TOTAL_IDS; id_range = id_range+1)
        begin 
      
	      caxi4interconnect_FIFO #
	      	(
	      		.MEM_DEPTH( ADDR_FIFO_DEPTH ),
	      		.DATA_WIDTH_IN ( 1 ),
	      		.DATA_WIDTH_OUT ( 1 ), 
	      		.NEARLY_FULL_THRESH ( ADDR_FIFO_DEPTH - 1 ),
	      		.NEARLY_EMPTY_THRESH ( 0 )
	      	)
	      cmd_fifo (
	      		.rst (sysReset ),
	      		.clk ( ACLK ),
	      		.wr_en ( wr_en_cmd & (BRespFifoWrData[ID_WIDTH:1] == id_range) ),
	      		.rd_en ( rd_en_cmd & (SLAVE_BID == id_range)),
	      		.data_in ( BRespFifoWrData[0] ),
	      		.data_out ( BRespFifoRdData[id_range] ),
	      		.zero_data ( 1'b0 ),
	      		.fifo_full ( ),
	      		.fifo_empty ( cmd_fifo_empty_temp[id_range] ),
	      		.fifo_nearly_full ( cmd_fifo_full[id_range] ),
	      		.fifo_nearly_empty ( ),
	      		.fifo_one_from_full ( )
	        );	      
	    end

		assign cmd_fifo_empty = MASTER_BVALID ? cmd_fifo_empty_temp[MASTER_BID] : cmd_fifo_empty_temp[SLAVE_BID];

	    caxi4interconnect_DWC_brespCtrl #
		(
			.ID_WIDTH ( ID_WIDTH ),
			.USER_WIDTH ( USER_WIDTH )
		)
	    brespCtrl( 
            .SLAVE_BREADY(SLAVE_BREADY),
            .SLAVE_BRESP(SLAVE_BRESP),
            .SLAVE_BUSER(SLAVE_BUSER),
            .SLAVE_BVALID(SLAVE_BVALID),
            .SLAVE_BID(SLAVE_BID),
            .BRespFifoRdData(BRespFifoRdData[SLAVE_BID]),
            .bresp_fifo_empty(cmd_fifo_empty),
            .brespFifore(rd_en_cmd),
            .ACLK(ACLK),
            .sysReset(sysReset),
            .MASTER_BID(MASTER_BID),
            .MASTER_BREADY(MASTER_BREADY),
            .MASTER_BRESP(MASTER_BRESP),
            .MASTER_BUSER(MASTER_BUSER),
            .MASTER_BVALID(MASTER_BVALID) 
        );

	end 
  else 
    begin 
	
	  wire [ID_WIDTH:0] BRespFifoRdData;
	  wire              cmd_fifo_full;
	  
   	  assign bchan_cmd_fifo_full = cmd_fifo_full;

	  
	  caxi4interconnect_FIFO #
		(
			.MEM_DEPTH( ADDR_FIFO_DEPTH ),
			.DATA_WIDTH_IN ( 1 + ID_WIDTH ),
			.DATA_WIDTH_OUT ( 1 +  ID_WIDTH ), 
			.NEARLY_FULL_THRESH ( ADDR_FIFO_DEPTH - 1 ),
			.NEARLY_EMPTY_THRESH ( 0 )
		)
	    cmd_fifo (
			.rst (sysReset ),
			.clk ( ACLK ),
			.wr_en ( wr_en_cmd ),
			.rd_en ( rd_en_cmd ),
			.data_in ( BRespFifoWrData ),
			.data_out ( BRespFifoRdData ),
			.zero_data ( 1'b0 ),
			.fifo_full ( ),
			.fifo_empty ( cmd_fifo_empty ),
			.fifo_nearly_full ( cmd_fifo_full ),
			.fifo_nearly_empty ( ),
			.fifo_one_from_full ( )
	    );
		
	    caxi4interconnect_DWC_brespCtrl #
		(
			.ID_WIDTH ( ID_WIDTH ),
			.USER_WIDTH ( USER_WIDTH )
		)
	    brespCtrl( 
           .SLAVE_BREADY(SLAVE_BREADY),
           .SLAVE_BRESP(SLAVE_BRESP),
           .SLAVE_BUSER(SLAVE_BUSER),
           .SLAVE_BVALID(SLAVE_BVALID),
           .SLAVE_BID(BRespFifoRdData[ID_WIDTH:1]),
           .BRespFifoRdData(BRespFifoRdData[0]),
           .bresp_fifo_empty(cmd_fifo_empty),
           .brespFifore(rd_en_cmd),
           .ACLK(ACLK),
           .sysReset(sysReset),
           .MASTER_BID(MASTER_BID),
           .MASTER_BREADY(MASTER_BREADY),
           .MASTER_BRESP(MASTER_BRESP),
           .MASTER_BUSER(MASTER_BUSER),
           .MASTER_BVALID(MASTER_BVALID) 
        );
		
	
	end 
	
endgenerate


endmodule
