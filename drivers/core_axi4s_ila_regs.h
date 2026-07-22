/* TODO:
* We are doe till CLK_FREQ_REG
*/
/*******************************************************************************
 * @file core_axi4s_ila_regs.h
 * @author Y.U.P.
 * @brief CoreAXI4S_ILA register definitions
 *
 * @details This file contains the register definitions for the CoreAXI4S_ILA module, including register offsets, field offsets, masks, and descriptions. It serves as a reference for software developers to interact with the CoreAXI4S_ILA hardware. 
 * 
 * Currently, the field definitions are based on the default configuration of the CoreAXI4S_ILA module. If the module is synthesized with different parameters, the register definitions may need to be updated accordingly.
 * 
 * Honestly speaking its useless, number of input/output registers very according to synthesis and this file needs to be updated after every synthesis. But we can use it as a template for future reference.
 */
 
#ifndef __CORE_AXI4S_ILA_REGISTERS_H
#define __CORE_AXI4S_ILA_REGISTERS_H    1

#ifndef CORE_AXI4S_ILA_DATA_WIDTH
#define CORE_AXI4S_ILA_DATA_WIDTH 64u
#warning "CORE_AXI4S_ILA_DATA_WIDTH is not defined, using default value of 64. Please define it in your project settings or in a header file before including this file."
#endif

// Using 3 here as the default value
#ifndef CORE_AXI4S_ILA_SIGNAL_WIDTH
#define CORE_AXI4S_ILA_SIGNAL_WIDTH 3u
#warning "CORE_AXI4S_ILA_SIGNAL_WIDTH is not defined, using default value of 3. Please define it in your project settings or in a header file before including this file."
#endif

#ifndef CORE_AXI4S_ILA_STRIDE_WIDTH
#define CORE_AXI4S_ILA_STRIDE_WIDTH (CORE_AXI4S_ILA_DATA_WIDTH/32 + 1)
#warning "CORE_AXI4S_ILA_STRIDE_WIDTH is not defined, using default value of (CORE_AXI4S_ILA_DATA_WIDTH/32 + 1)."
#endif

#ifndef CORE_AXI4S_ILA_SAMP_BUFF_DEPTH
#define CORE_AXI4S_ILA_SAMP_BUFF_DEPTH 1024u
#warning "CORE_AXI4S_ILA_SAMP_BUFF_DEPTH is not defined, using default value of 1024. Please define it in your project settings or in a header file before including this file."
#endif

// We are already harrassing the user to define these variables, why not add frequency too?
#ifndef CORE_AXI4S_ILA_SAMP_FREQ_HZ
#define CORE_AXI4S_ILA_SAMP_FREQ_HZ 1000000000u
#warning "CORE_AXI4S_ILA_SAMP_FREQ_HZ is not defined, using default value of 100 MHz. Please define it in your project settings or in a header file before including this file."
#endif

#define CORE_AXI4S_ILA_N_IP_REGS 4 + CORE_AXI4S_ILA_DATA_WIDTH/32 * 2
#define CORE_AXI4S_ILA_N_OP_REGS 8 + CORE_AXI4S_ILA_STRIDE_WIDTH * CORE_AXI4S_ILA_SAMP_BUFF_DEPTH

#define CORE_AXI4S_ILA_N_CTRL_REGS CORE_AXI4S_ILA_N_IP_REGS + CORE_AXI4S_ILA_N_OP_REGS

#define CORE_AXI4S_ILA_OP_REGS_OFFSET CORE_AXI4S_ILA_N_IP_REGS * 4

/*******************************************************************************
 * Register: TRIG_COND_REG
 *
 * Description: This register is used to configure the trigger condition for the ILA. It allows the user to set specific conditions that will trigger the ILA to start capturing data.
 */
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_OFFSET       0x00U
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_RW_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_RO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_WRITE_MASK   0xFFFFFFFFU

/**
 * Field Name: TREADY
 * 
 * Field Desc: Controls the trigger condition based on the TREADY signal. When set, the ILA will trigger when TREADY is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TREADY_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TREADY_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TREADY_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TREADY_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TREADY_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TREADY_FIELD_SHIFT)

/**
 * Field Name: TVALID
 * 
 * Field Desc: Controls the trigger condition based on the TVALID signal. When set, the ILA will trigger when TVALID is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TVALID_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TVALID_FIELD_SHIFT      (1U)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TVALID_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TVALID_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TVALID_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TVALID_FIELD_SHIFT)

/**
 * Field Name: TLAST
 * 
 * Field Desc: Controls the trigger condition based on the TLAST signal. When set, the ILA will trigger when TLAST is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TLAST_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TLAST_FIELD_SHIFT      (2U)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TLAST_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TLAST_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TLAST_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TLAST_FIELD_SHIFT)

/**
 * Field Name: TDATA
 * 
 * Field Desc: Controls the trigger condition based on the TDATA signal. When set, the ILA will trigger when TDATA is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TDATA_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TDATA_FIELD_SHIFT      (3U)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TDATA_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TDATA_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TDATA_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_COND_REG_TDATA_FIELD_SHIFT)

/**
 * Field Name: ANDOR
 * 
 * Field Desc: Controls the trigger condition based on the ANDOR signal. When set, the ILA will trigger when ANDOR is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_ANDOR_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_ANDOR_FIELD_SHIFT      (4U)
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_ANDOR_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_COND_REG_ANDOR_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_COND_REG_ANDOR_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_COND_REG_ANDOR_FIELD_SHIFT)

/*******************************************************************************
 * Register: TRIG_MASK_REG
 *
 * Description: This register is used to configure the trigger condition for the ILA. It allows the user to set specific conditions that will trigger the ILA to start capturing data.
 */
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_OFFSET       0x04U
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_RW_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_RO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_WRITE_MASK   0xFFFFFFFFU

/**
 * Field Name: TREADY
 * 
 * Field Desc: Controls the trigger condition based on the TREADY signal. When set, the ILA will trigger when TREADY is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TREADY_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TREADY_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TREADY_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TREADY_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TREADY_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TREADY_FIELD_SHIFT)

/**
 * Field Name: TVALID
 * 
 * Field Desc: Controls the trigger condition based on the TVALID signal. When set, the ILA will trigger when TVALID is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TVALID_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TVALID_FIELD_SHIFT      (1U)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TVALID_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TVALID_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TVALID_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TVALID_FIELD_SHIFT)

/**
 * Field Name: TLAST
 * 
 * Field Desc: Controls the trigger condition based on the TLAST signal. When set, the ILA will trigger when TLAST is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TLAST_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TLAST_FIELD_SHIFT      (2U)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TLAST_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TLAST_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TLAST_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TLAST_FIELD_SHIFT)

/**
 * Field Name: TDATA
 * 
 * Field Desc: Controls the trigger condition based on the TDATA signal. When set, the ILA will trigger when TDATA is high.
 */

#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TDATA_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TDATA_FIELD_SHIFT      (3U)
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TDATA_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TDATA_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TDATA_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_TRIG_MASK_REG_TDATA_FIELD_SHIFT)

/*******************************************************************************
 * Register: ARM_REG
 *
 * Description: Any write to this register will arm the ILA. The ILA will start capturing data based on the configured trigger conditions.
 */
#define CORE_AXI4S_ILA_REGS_ARM_REG_OFFSET       0x0CU
#define CORE_AXI4S_ILA_REGS_ARM_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_ARM_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_ARM_REG_RO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_ARM_REG_WO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_ARM_REG_READ_MASK    0x00000000U
#define CORE_AXI4S_ILA_REGS_ARM_REG_WRITE_MASK   0xFFFFFFFFU

/*******************************************************************************
 * Register: TRIG_DATA_COND_LSB_REG
 *
 * Description: This register is used to configure the trigger condition for the ILA. It allows the user to set specific conditions that will trigger the ILA to start capturing data. Total CORE_AXI4S_ILA_DATA_WIDTH/32 registers are used to configure the trigger condition for the ILA. It allows the user to set specific conditions that will trigger the ILA to start capturing data.
 */
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_OFFSET       0x10U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_RW_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_RO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB_REG_WRITE_MASK   0xFFFFFFFFU

/*******************************************************************************
 * Register: TRIG_DATA_MASK_LSB_REG
 *
 * Description: This register is used to configure the trigger condition mask for the ILA. It allows the user to set specific conditions that will trigger the ILA to start capturing data. Total CORE_AXI4S_ILA_DATA_WIDTH/32 registers are used to configure the trigger condition for the ILA. It allows the user to set specific conditions that will trigger the ILA to start capturing data.
 */
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_OFFSET       0x10U + CORE_AXI4S_ILA_DATA_WIDTH/32 * 4
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_RW_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_RO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB_REG_WRITE_MASK   0xFFFFFFFFU

/* HERE STARTS THE OUTPUT REGISTERS */
/*******************************************************************************
 * Register: STATUS_REG
 *
 * Description: This register is used to read the status of the ILA. It provides information about whether the ILA is idle, armed, triggered, or done capturing data.
 */
#define CORE_AXI4S_ILA_REGS_STATUS_REG_OFFSET       0x00U + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_STATUS_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_STATUS_REG_RW_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_STATUS_REG_RO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_STATUS_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_STATUS_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_STATUS_REG_WRITE_MASK   0xFFFFFFFFU

/**
 * Field Name: ARMED
 * 
 * Field Desc: Shows whether the ILA is armed. When set, the ILA is ready to capture data based on the configured trigger conditions. This bit is CDCed with 2FF.
 */

#define CORE_AXI4S_ILA_REGS_STATUS_REG_ARMED_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_ARMED_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_ARMED_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_STATUS_REG_ARMED_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_STATUS_REG_ARMED_FIELD_SHIFT)

/**
 * Field Name: TRIGD
 * 
 * Field Desc: Shows whether the ILA is triggered. When set, the ILA has detected a trigger event. This bit is CDCed with 2FF.
 */

#define CORE_AXI4S_ILA_REGS_STATUS_REG_TRIGD_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_TRIGD_FIELD_SHIFT      (1U)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_TRIGD_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_STATUS_REG_TRIGD_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_STATUS_REG_TRIGD_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_STATUS_REG_TRIGD_FIELD_SHIFT)

/**
 * Field Name: DONE
 * 
 * Field Desc: Shows whether the ILA is done capturing data. When set, the ILA has completed its data capture operation. This bit is CDCed with 2FF.
 */

#define CORE_AXI4S_ILA_REGS_STATUS_REG_DONE_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_DONE_FIELD_SHIFT      (2U)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_DONE_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_AXI4S_ILA_REGS_STATUS_REG_DONE_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_STATUS_REG_DONE_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_STATUS_REG_DONE_FIELD_SHIFT)

/**
 * Field Name: STATUS
 * 
 * Field Desc: Shows the current internal status of the ILA. This field is not CDCed and is a direct reflection of the internal state machine of the ILA.
 */

#define CORE_AXI4S_ILA_REGS_STATUS_REG_STATUS_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_STATUS_FIELD_SHIFT      (3U)
#define CORE_AXI4S_ILA_REGS_STATUS_REG_STATUS_FIELD_NS_MASK    ((uint32_t)(0x00000002UL))
#define CORE_AXI4S_ILA_REGS_STATUS_REG_STATUS_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_STATUS_REG_STATUS_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_STATUS_REG_STATUS_FIELD_SHIFT)

/*******************************************************************************
 * Register: MGCKEY_REG
 *
 * Description: This register stores the MAGIC_KEY value used to verify the AXI4Lite connection. It is used during initialization to ensure that the software can communicate with the hardware correctly.
 */
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_OFFSET       0x04U + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_RO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: MGCKEY
 * 
 * Field Desc: Constant value used to verify the AXI4Lite connection. The expected value is 0xb01dface. This field is read-only and is used during initialization to ensure that the software can communicate with the hardware correctly.
 */

#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_MGCKEY_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_AXI4S_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_CLK_FREQ_REG
 *
 * Description: This register stores the synthesis time clock frequency of the AXI4S signal. It is used to provide information about the clock frequency to the software for timing analysis and debugging purposes.
 */
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET       0x08U + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_RO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: SAMP_CLK_FREQ
 * 
 * Field Desc: Stores the synthesis time clock frequency of the AXI4S signal. This field is read-only and is used to provide information about the clock frequency to the software for timing analysis and debugging purposes.
 */

#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_SHIFT)

/*******************************************************************************
 * Register: WIDTH_REG
 *
 * Description: This register stores the synthesis time width of the AXI4S signal. It is used to provide information about the bus width and signal width to the software for timing analysis and debugging purposes.
 */
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_OFFSET       0x0CU + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_RO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: DATA_WIDTH
 * 
 * Field Desc: Stores the synthesis time width of the AXI4S signal. This field is read-only and is used to provide information about the bus width and signal width to the software for timing analysis and debugging purposes.
 */

#define CORE_AXI4S_ILA_REGS_WIDTH_REG_DATA_WIDTH_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_WIDTH_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_DATA_WIDTH_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_DATA_WIDTH_FIELD_NS_MASK    ((uint32_t)(0x0000FFFFUL))
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_DATA_WIDTH_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_WIDTH_REG_DATA_WIDTH_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_WIDTH_REG_DATA_WIDTH_FIELD_SHIFT)

/**
 * Field Name: SIGNAL_WIDTH
 * 
 * Field Desc: Stores the synthesis time width of the AXI4S signal. This field is read-only and is used to provide information about the bus width and signal width to the software for timing analysis and debugging purposes.
 */

#define CORE_AXI4S_ILA_REGS_WIDTH_REG_SIGNAL_WIDTH_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_WIDTH_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_SIGNAL_WIDTH_FIELD_SHIFT      (16U)
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_SIGNAL_WIDTH_FIELD_NS_MASK    ((uint32_t)(0x0000FFFFUL))
#define CORE_AXI4S_ILA_REGS_WIDTH_REG_SIGNAL_WIDTH_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_WIDTH_REG_SIGNAL_WIDTH_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_WIDTH_REG_SIGNAL_WIDTH_FIELD_SHIFT)
         
/*******************************************************************************
 * Register: BUFF_DEPTH_REG
 *
 * Description: This register stores the synthesis time depth of the sampling buffer.
 */
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_OFFSET       0xF0U + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_RO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: BUFF_DEPTH
 * 
 * Field Desc: Stores the synthesis time depth of the sampling buffer. This field is read-only and is used to provide information about the buffer depth to the software for timing analysis and debugging purposes.
 */

#define CORE_AXI4S_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_DEPTH_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_AXI4S_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_SHIFT)
        
/*******************************************************************************
 * Register: SAMP_BUFF_TRIG_IDX_REG
 *
 * Description: This register stores the index of the sample buffer where the trigger event occurred.
 */
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET       0xF8U + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_RO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: SAMP_BUFF_TRIG_IDX
 * 
 * Field Desc: Stores the index of the sample buffer where the trigger event occurred.
 */

#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_BUFF_DEPTH_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_BUFF_DEPTH_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_BUFF_DEPTH_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_BUFF_DEPTH_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_BUFF_DEPTH_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_BUFF_DEPTH_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_BUFF_FRST_IDX_REG
 *
 * Description: This register stores the index of the sample buffer where the trigger event occurred.
 */
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET       0xFCU + CORE_AXI4S_ILA_OP_REGS_OFFSET
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_LENGTH       0x04U
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_RW_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_RO_MASK      0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_WO_MASK      0x00000000U
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_READ_MASK    0xFFFFFFFFU
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: SAMP_BUFF_FRST_IDX
 * 
 * Field Desc: Stores the index of the sample buffer where the trigger event occurred.
 */

#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_BUFF_DEPTH_FIELD_OFFSET     \
                (CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET)
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_BUFF_DEPTH_FIELD_SHIFT      (0U)
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_BUFF_DEPTH_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_BUFF_DEPTH_FIELD_MASK \
      (CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_BUFF_DEPTH_FIELD_NS_MASK << \
         CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_BUFF_DEPTH_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_BUFF_BASE_REG
 *
 * Description: This is the base address of the sample buffer. It marks the starting point of the sample buffer in memory. The sample buffer is used to store captured data from the ILA.
 * 
 * Look at the docs to see how data is stored and how to read it.
 */
#define CORE_AXI4S_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET       0x00U + CORE_AXI4S_ILA_N_CTRL_REGS * 4

#endif /* __CORE_AXI4S_ILA_REGISTERS_H */
