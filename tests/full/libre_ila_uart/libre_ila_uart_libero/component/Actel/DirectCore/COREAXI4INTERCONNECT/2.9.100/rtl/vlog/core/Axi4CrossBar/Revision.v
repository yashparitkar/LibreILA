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

module caxi4interconnect_revision ( devRevision );

output  [31:0]   devRevision;

wire    [7:0]    relYear;
wire    [7:0]    relMonth;
wire    [7:0]    relDay;
wire    [7:0]    buildNum;
wire    [31:0]   devRevision;

assign relYear            = 8'h15;      // Date: Year
assign relMonth           = 8'h06;      // Date: Month      
assign relDay             = 8'h29;      // Date: Day
assign buildNum           = 8'b0000001; // Build number


assign devRevision = {relYear,relMonth,relDay, buildNum};

endmodule
