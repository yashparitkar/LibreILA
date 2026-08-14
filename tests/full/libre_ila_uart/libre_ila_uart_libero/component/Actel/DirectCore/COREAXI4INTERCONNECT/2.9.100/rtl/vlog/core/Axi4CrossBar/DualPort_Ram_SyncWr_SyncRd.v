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

module caxi4interconnect_DualPort_RAM_SyncWr_SyncRd (
					// AHB global signals
					HCLK,

					// Write Port
					fifoWrAddr,	
					fifoWrite,
					fifoWrData,

					// Read Port
					fifoRdAddr,
					fifoRdData
				   
				);

   

//============================================
// Parameter Declarations
//============================================

	parameter FIFO_AWIDTH = 9;
	
	parameter FIFO_WIDTH = 8;
	
	parameter	HI_FREQ = 0;
	
	localparam FIFO_DEPTH = 1 << FIFO_AWIDTH;


//============================================================================
// I/O ports
//============================================================================

// Inputs - AHB
	input HCLK;								// ahb system clock

	
// Write Port signals
	input [FIFO_WIDTH-1:0]	fifoWrData;		// Data to be written to ram
	input [FIFO_AWIDTH-1:0] fifoWrAddr;		// Addr to be written to in RAM
	input fifoWrite;						// Indicates address defined by fifoWrAddr to be written

 // Read Port signals
	output [FIFO_WIDTH-1:0]	 fifoRdData;	// Data to be written to ram
	input  [FIFO_AWIDTH-1:0] fifoRdAddr;	// Addr to be read from RAM

   
//============================================
// I/O Declarations
//============================================

	wire [FIFO_WIDTH-1:0]		fifoRdData;		// Data to be read from register
	
	
//============================================
// Local Declarations
//============================================


	reg [FIFO_WIDTH-1:0] mem [0:FIFO_DEPTH-1];	// RAM array declaration

	reg [FIFO_AWIDTH-1:0] fifoRdAddrQ1;			// clocked address

	reg [FIFO_WIDTH-1:0]	fifoRdDataQ1;		// clocked ouput data
	
	
//====================================================================================
// Infer dual port ram - one sync write port - once async read port
//==================================================================================

assign fifoRdData = HI_FREQ ?  fifoRdDataQ1 : mem[fifoRdAddrQ1];

always@ (posedge HCLK )
begin

	fifoRdDataQ1 <= mem[fifoRdAddrQ1];

	fifoRdAddrQ1 <= fifoRdAddr;
	
	if (fifoWrite)
		mem[fifoWrAddr] <= fifoWrData;

end


endmodule // caxi4interconnect_DualPort_RAM_SyncWr_SyncRd.v
