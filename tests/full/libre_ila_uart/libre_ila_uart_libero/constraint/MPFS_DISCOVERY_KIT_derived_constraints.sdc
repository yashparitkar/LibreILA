# Microchip Technology Inc.
# Date: 2026-Aug-13 13:42:54
# This file was generated based on the following SDC source files:
#   /home/yash/LiberoWD/LibreILA_full/component/work/PF_CCC_C0/PF_CCC_C0_0/PF_CCC_C0_PF_CCC_C0_0_PF_CCC.sdc
#   /home/yash/LiberoWD/LibreILA_full/component/work/DMA_INITIATOR/DMA_INITIATOR_0/DMA_INITIATOR.sdc
#   /home/yash/LiberoWD/LibreILA_full/component/work/FIC0_INITIATOR/FIC0_INITIATOR_0/FIC0_INITIATOR.sdc
#   /home/yash/LiberoWD/LibreILA_full/component/work/MPFS_DISCOVERY_KIT_MSS/MPFS_DISCOVERY_KIT_MSS.sdc
# *** Any modifications to this file will be lost if derived constraints is re-run. ***
#

create_clock -name {REF_CLK_50MHz} -period 20 [ get_ports { REF_CLK_50MHz } ]
create_generated_clock -name {CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT0} -multiply_by 2 -source [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT0 } ]
create_generated_clock -name {CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT1} -multiply_by 5 -divide_by 2 -source [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT1 } ]
create_generated_clock -name {CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT2} -multiply_by 5 -divide_by 2 -source [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT2 } ]
create_generated_clock -name {CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT3} -divide_by 1 -source [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { CLOCKS_AND_RESETS_0/CCC_FIC_x_CLK/PF_CCC_C0_0/pll_inst_0/OUT3 } ]
set_false_path -through [ get_nets { FIC_0_PERIPHERALS_0/DMA_INITIATOR_inst_0/ARESETN* } ]
set_false_path -through [ get_nets { FIC_0_PERIPHERALS_0/FIC0_INITIATOR_inst_0/ARESETN* } ]
