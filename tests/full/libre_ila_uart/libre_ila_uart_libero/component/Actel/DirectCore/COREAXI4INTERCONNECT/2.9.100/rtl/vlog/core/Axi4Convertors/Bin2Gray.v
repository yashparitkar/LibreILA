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


module caxi4interconnect_Bin2Gray #
  (
  parameter integer n_bits = 4
  )
  (
   input wire [n_bits-1:0]  cntBinary,

   output wire [n_bits-1:0] nextGray
  );

  genvar i;
  generate
  for (i = 0; i < (n_bits-1) ; i = i + 1) 
    begin
      assign nextGray[i] = cntBinary[i] ^ cntBinary[i+1];
    end
  endgenerate

  assign nextGray[n_bits-1] = cntBinary[n_bits-1];

endmodule
