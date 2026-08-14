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

module caxi4interconnect_RequestQual # 
	(
		parameter integer NUM_SLAVES 			= 8, 				// defines number of slaves requestors  
		parameter integer NUM_MASTERS_WIDTH		= 1, 				// defines number of bits to encode master number
		parameter integer ID_WIDTH   			= 1,
		parameter integer CROSSBAR_MODE			= 1				// defines whether non-blocking (ie set 1) or shared access data path
	)
	(
		input  wire [NUM_SLAVES-1:0]    								SLAVE_VALID,
		input  wire [3:0]                                   			MASTER_NUM,     // jhayes : change to width to match maximum width possible.
  		input  wire [NUM_SLAVES*(NUM_MASTERS_WIDTH+ID_WIDTH)-1:0] 		SLAVE_ID,
		input  wire [NUM_SLAVES-1:0]									READ_CONNECTIVITY,
		
		output  reg [NUM_SLAVES-1:0]    								slaveValidQual
	);
						 
//================================================================================================
// Local Parameters
//================================================================================================
	localparam MASTERID_WIDTH		= ( NUM_MASTERS_WIDTH + ID_WIDTH );			// defines width masterID - includes infrastructure ID plus ID


//=================================================================================================
// Local Declarationes
//=================================================================================================
	reg	[NUM_MASTERS_WIDTH-1:0]		slaveTargetID	[0:NUM_SLAVES-1];

//=================================================================================================

genvar i;
generate 
	for (i=0; i < NUM_SLAVES; i=i+1)
		begin
			always @(*)
				begin
				// pick out infrastructure component from SLAVE_ID - ie target master
				slaveTargetID[i] 	= SLAVE_ID[(i+1)*MASTERID_WIDTH-1:(i*MASTERID_WIDTH)+ ID_WIDTH];
			
				// Only assert slaveValidQual to arbitrator when slave valid is asserted and the SLAVE_ID is targetting this
				// master and READ_CONNECTIVITY is set for this slave
				slaveValidQual[i]	= READ_CONNECTIVITY[i] & SLAVE_VALID[i] &  
												( CROSSBAR_MODE ?  ( slaveTargetID[i] == MASTER_NUM[NUM_MASTERS_WIDTH-1:0] )    // jhayes : change to use relevant bits of MASTER_NUM for comparison.
															    : 1'b1 );	// all slaves arb togather in non-crossbar mode - does not
																			// matter which master they want to connect to - only one path
				end
		end
		
endgenerate


endmodule // caxi4interconnect_RequestQual.v
