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

module caxi4interconnect_ResetSycnc  
	(
		input  wire             	sysClk,
		input  wire                 sysReset_L,			// active low reset synchronoise to RE AClk - asserted async.

		output reg					sysReset			// active low sysReset synchronised to sysClk
	) /* synthesis syn_preserve = 1 syn_noprune = 1 */ ;
   						 
						 
//================================================================================================
// Local Parameters
//================================================================================================

	
	
//=================================================================================================
// Local Declarationes
//=================================================================================================
 
reg   sysReset_f1;

//=================================================================================================
always @(posedge sysClk or negedge sysReset_L)
begin
	if( ~sysReset_L )
		sysReset_f1 <= 1'b0;			// active low reset on
	else
		sysReset_f1 <= 1'b1;			// active low reset off
end

always @(posedge sysClk or negedge sysReset_L)
begin
	if( ~sysReset_L )
		sysReset <= 1'b0;			// active low reset on
	else
		sysReset <= sysReset_f1;	// active low reset off
end

endmodule // caxi4interconnect_ResetSycnc.v
