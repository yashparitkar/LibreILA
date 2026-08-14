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
 
 
module caxi4interconnect_CDC_wrCtrl (
                   //  input ports
                   clk,
                   rst,
                   rdPtr_gray,
                   wrPtr_gray,
                   nextwrPtr_gray,
                   infoInValid,
 
                   //  output ports
                   fifoWe,
                   readyForInfo
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
   input     [ADDR_WIDTH - 1:0] nextwrPtr_gray;
   wire      [ADDR_WIDTH - 1:0] nextwrPtr_gray;
   input            infoInValid;
   wire             infoInValid;
//  output ports
   output           fifoWe;
   wire             fifoWe;
   output           readyForInfo;
   wire             readyForInfo;
//  local signals
   wire             ptrsEq_wrZone;
   wire             rdEqWrP1;
   reg              full;
 
 
   always
      @( posedge clk or negedge rst )
   begin   :WrCtrl
 
      if (!rst)
      begin
         full <= 1'b0;
      end
      else
      begin
         if (ptrsEq_wrZone)
         begin
         end
         else
         begin
            if (rdEqWrP1)
            begin
               if (fifoWe)
               begin
                  full <= 1'b1;
               end
               else
               begin
                  full <= 1'b0;
               end
            end
            else
            begin
               full <= 1'b0;
            end
         end
      end
   end
 
   assign ptrsEq_wrZone = (rdPtr_gray == wrPtr_gray);
   assign rdEqWrP1 = (rdPtr_gray == nextwrPtr_gray);
 
   assign fifoWe = infoInValid & readyForInfo;
   assign readyForInfo = !full;
 
 
endmodule

