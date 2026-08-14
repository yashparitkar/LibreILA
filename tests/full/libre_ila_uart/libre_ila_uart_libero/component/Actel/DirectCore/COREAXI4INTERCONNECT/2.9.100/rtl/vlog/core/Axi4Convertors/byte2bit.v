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
module caxi4interconnect_byte2bit (
                                 //  input ports
                                 shifted_slv_mask_bit,
                                 shifted_mst_mask_bit,
 
                                 //  output ports
                                 shifted_slv_mask_byte,
                                 shifted_mst_mask_byte
                                 );
 
   parameter        DATA_WIDTH_IN             = 32;
   parameter        DATA_WIDTH_OUT            = 32;
//  output ports
   output     [DATA_WIDTH_IN - 1:0] shifted_slv_mask_bit;
   wire      [DATA_WIDTH_IN - 1:0] shifted_slv_mask_bit;
   output     [DATA_WIDTH_OUT - 1:0] shifted_mst_mask_bit;
   wire      [DATA_WIDTH_OUT - 1:0] shifted_mst_mask_bit;
//  input ports
   input    [(DATA_WIDTH_IN / 8) - 1:0] shifted_slv_mask_byte;
   wire      [(DATA_WIDTH_IN / 8) - 1:0] shifted_slv_mask_byte;
   input    [(DATA_WIDTH_OUT / 8) - 1:0] shifted_mst_mask_byte;
   wire      [(DATA_WIDTH_OUT / 8) - 1:0] shifted_mst_mask_byte;

   genvar i;

   generate
     for (i=0;i<(DATA_WIDTH_IN/8);i=i+1) begin
       assign shifted_slv_mask_bit[(8*i)+:8] = {8{shifted_slv_mask_byte[i]}};
     end
   endgenerate

   generate
     for (i=0;i<(DATA_WIDTH_OUT/8);i=i+1) begin
       assign shifted_mst_mask_bit[(8*i)+:8] = {8{shifted_mst_mask_byte[i]}};
     end
   endgenerate

endmodule

