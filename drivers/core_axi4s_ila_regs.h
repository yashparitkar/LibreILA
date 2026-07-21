/*******************************************************************************
 * @file core_axi4s_ila_regs.h
 * @author Y.U.P.
 * @brief CoreAXI4S_ILA register definitions
 *
 * @details This file contains the register definitions for the CoreFPAD module, including register offsets, field offsets, masks, and descriptions. It serves as a reference for software developers to interact with the CoreFPAD hardware. Honestly speaking its useless, number of input/output registers very according to synthesis and this file needs to be updated after every synthesis. But we can use it as a template for future reference.
 */
 
#ifndef __CORE_AXI4S_ILA_REGISTERS_H
#define __CORE_AXI4S_ILA_REGISTERS_H    1

/*******************************************************************************
 * Register: CTRL_REG
 *
 * Description:  Control the state of the core, namely, clear counters, start_counters and calculate variance
 */
#define COREFPAD_REGS_CTRL_REG_OFFSET       0x00U
#define COREFPAD_REGS_CTRL_REG_LENGTH       0x04U
#define COREFPAD_REGS_CTRL_REG_RW_MASK      0xFFFFFFFFU
#define COREFPAD_REGS_CTRL_REG_RO_MASK      0x00000000U
#define COREFPAD_REGS_CTRL_REG_WO_MASK      0x00000000U
#define COREFPAD_REGS_CTRL_REG_READ_MASK    0xFFFFFFFFU
#define COREFPAD_REGS_CTRL_REG_WRITE_MASK   0xFFFFFFFFU

/**
 * Field Name: CLEAR
 * 
 * Field Desc: This is LSB of the control register. Rising edge clears the counters and variance registers.
 */

#define COREFPAD_REGS_CTRL_REG_CLEAR_FIELD_OFFSET     \
                (COREFPAD_REGS_CTRL_REG_OFFSET)
#define COREFPAD_REGS_CTRL_REG_CLEAR_FIELD_SHIFT      (0U)
#define COREFPAD_REGS_CTRL_REG_CLEAR_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define COREFPAD_REGS_CTRL_REG_CLEAR_FIELD_MASK \
      (COREFPAD_REGS_CTRL_REG_CLEAR_FIELD_NS_MASK << \
         COREFPAD_REGS_CTRL_REG_CLEAR_FIELD_SHIFT)


/**
 * Field Name: STRT_CNTR
 * 
 * Field Desc: This is LSB+1st of the control register. Rising edge starts the counters.
 */

#define COREFPAD_REGS_CTRL_REG_STRT_CNTR_FIELD_OFFSET     \
                (COREFPAD_REGS_CTRL_REG_OFFSET)
#define COREFPAD_REGS_CTRL_REG_STRT_CNTR_FIELD_SHIFT      (1U)
#define COREFPAD_REGS_CTRL_REG_STRT_CNTR_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define COREFPAD_REGS_CTRL_REG_STRT_CNTR_FIELD_MASK \
      (COREFPAD_REGS_CTRL_REG_STRT_CNTR_FIELD_NS_MASK << \
         COREFPAD_REGS_CTRL_REG_STRT_CNTR_FIELD_SHIFT)

/**
 * Field Name: CALC_VAR
 * 
 * Field Desc: This is LSB+2nd the control register. Rising edge calculates the variance.
 */

#define COREFPAD_REGS_CTRL_REG_CALC_VAR_FIELD_OFFSET     \
                (COREFPAD_REGS_CTRL_REG_OFFSET)
#define COREFPAD_REGS_CTRL_REG_CALC_VAR_FIELD_SHIFT      (2U)
#define COREFPAD_REGS_CTRL_REG_CALC_VAR_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define COREFPAD_REGS_CTRL_REG_CALC_VAR_FIELD_MASK \
      (COREFPAD_REGS_CTRL_REG_CALC_VAR_FIELD_NS_MASK << \
         COREFPAD_REGS_CTRL_REG_CALC_VAR_FIELD_SHIFT)


#endif /* __CORE_FPAD_REGISTERS_H */
