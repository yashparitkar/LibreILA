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

module caxi4interconnect_MasterAddressDecoder (
								masterAddr,
								match,					
								slaveMatched
							 );


//===================================================
// Parameter Declarations
//===================================================

	parameter NUM_SLAVES_WIDTH 	= 4;				// defines number bits for encoding slave number
	parameter NUM_SLAVES 		= 4;				// defines number of slaves	- includes derrSlave
	parameter SLAVE_NUM	 		= 0;				// defines slave that this decoder is for
	parameter ADDR_WIDTH 		= 32;				// number of address buts to be decoded
	
	parameter UPPER_COMPARE_BIT = 15;				// Defines the upper bit of range to compare
	parameter LOWER_COMPARE_BIT = 12;				// Defines lower bound of compare - bits below are 
													// dont care
													
	parameter [ADDR_WIDTH-1:0]      			        SLOT_BASE_ADDR = 0;		// Base address of Slot
	parameter [ADDR_WIDTH-1:0]                          SLOT_MIN_ADDR = 0;		// slot min address
	parameter [ADDR_WIDTH-1:0]                          SLOT_MAX_ADDR = 0;		// slot max address
	parameter [NUM_SLAVES-1:0]							CONNECTIVITY = {NUM_SLAVES{1'b1}};	// onnectivity map - ie which slaves this master can access
	
//==========================================================================
// I/O Declarations
//============================================================================

	input 	[ADDR_WIDTH-1:0]		masterAddr;		// address to be decoded

	output							match;			// Indictaes this slave matched address
	output 	[NUM_SLAVES_WIDTH-1:0] 	slaveMatched;	// encoded number of slave
	
	
//============================================================================
// Local Declarationes
//============================================================================


	reg								match;			// Indictaes this slave matched address
	wire 	[NUM_SLAVES_WIDTH-1:0] 	slaveMatched;	// encoded number of slave
	
 
 
//==============================================================================
// Simple decode matching
//==============================================================================

assign slaveMatched = SLAVE_NUM;		// simply return number of slave instance
/*

//SAR 94407 Change Start

always @( * )
begin
	match <= 		( masterAddr[ADDR_WIDTH-1:UPPER_COMPARE_BIT] == SLOT_BASE_ADDR			 )		// base address matches
				&	( masterAddr[UPPER_COMPARE_BIT-1:LOWER_COMPARE_BIT] >= SLOT_MIN_ADDR	 )
				&	( masterAddr[UPPER_COMPARE_BIT-1:LOWER_COMPARE_BIT] <= SLOT_MAX_ADDR	 )
				&	CONNECTIVITY[SLAVE_NUM];														// only match if master can access this slave

end

*/

always @( * )
begin
	match =    	( masterAddr[ADDR_WIDTH-1:0] >= SLOT_MIN_ADDR	 )
				&	( masterAddr[ADDR_WIDTH-1:0] <= SLOT_MAX_ADDR	 )
				&	CONNECTIVITY[SLAVE_NUM];														// only match if master can access this slave

end

//SAR 94407 Change End


endmodule // caxi4interconnect_MasterAddressDecoder.v
