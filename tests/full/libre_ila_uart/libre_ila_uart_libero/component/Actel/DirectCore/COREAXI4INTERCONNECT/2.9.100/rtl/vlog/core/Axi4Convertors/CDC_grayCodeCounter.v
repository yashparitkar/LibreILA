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


module caxi4interconnect_CDC_grayCodeCounter #
  (
    parameter bin_rstValue = 1,
    parameter gray_rstValue = 0,
    parameter integer n_bits = 4
  )
  (
    input wire clk,
    input wire sysRst,

    input wire syncRst,
    input wire inc,

    output wire syncRstOut,
    output reg [n_bits-1:0] cntGray

  );
  
  reg  [n_bits-1:0]  cntBinary;
  wire [n_bits-1:0]  nextGray, cntBinary_next;

  always @ (posedge clk or negedge sysRst)
  begin
  if (!sysRst)
    begin
        cntBinary               <= bin_rstValue;
        cntGray                 <= gray_rstValue;
    end
  else
    begin
      if (inc)
      begin
        if (!syncRst)
        begin
          cntBinary               <= bin_rstValue;
          cntGray                 <= gray_rstValue;
        end
        else
        begin
          cntBinary                 <= cntBinary_next;
          cntGray                   <= nextGray;
        end
     end	
    end
  end
  
assign cntBinary_next = cntBinary + 1;
assign syncRstOut = (cntBinary == 0) ? 1'b0 : 1'b1;

caxi4interconnect_Bin2Gray #
(
        .n_bits(n_bits)
)
 bin2gray_inst(
        .cntBinary(cntBinary),
        .nextGray(nextGray)
);

endmodule
