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
 
module caxi4interconnect_CDC_rdCtrl (
                   //  input ports
                   clk,
                   rst,
                   rdPtr_gray,
                   wrPtr_gray,
                   nextrdPtr_gray,
                   readyForOut,
 
                   //  output ports
                   infoOutValid,
                   fifoRe
                   );
 
   parameter        ADDR_WIDTH       = 3;
//  input ports
   input            clk;
   wire             clk;
   input            rst;
   wire             rst;
   input     [ADDR_WIDTH - 1:0] rdPtr_gray;
   wire      [ADDR_WIDTH - 1:0] rdPtr_gray;
   input     [ADDR_WIDTH - 1:0] wrPtr_gray;
   wire      [ADDR_WIDTH - 1:0] wrPtr_gray;
   input     [ADDR_WIDTH - 1:0] nextrdPtr_gray;
   wire      [ADDR_WIDTH - 1:0] nextrdPtr_gray;
   input            readyForOut;
   wire             readyForOut;
//  output ports
   output           infoOutValid;
   wire             infoOutValid;
   output           fifoRe;
   wire             fifoRe;
//  local signals
   wire             ptrsEq_rdZone;
   wire             wrEqRdP1;
   reg              empty;
 
 
   always
      @( posedge clk or negedge rst )
   begin   :RdCtrl
 
      if (!rst)
      begin
         empty <= 1'b1;
      end
      else
      begin
         if (ptrsEq_rdZone)
         begin
         end
         else
         begin
            if (wrEqRdP1)
            begin
               if (fifoRe)
               begin
                  empty <= 1'b1;
               end
               else
               begin
                  empty <= 1'b0;
               end
            end
            else
            begin
               empty <= 1'b0;
            end
         end
      end
   end
 
   assign ptrsEq_rdZone = (rdPtr_gray == wrPtr_gray);
   assign wrEqRdP1 = (wrPtr_gray == nextrdPtr_gray);
 
   assign fifoRe = infoOutValid & readyForOut;
   assign infoOutValid = !empty;
 
 
endmodule

