/*******************************************************************************
 * @file core_libre_ila_regs.h
 * @author Y.U.P. (paritkary25)
 * @brief CoreLibreILA register definitions
 *
 * @note Last Modified: 2026-07-27 Mon
 *
 * @details This file contains the register definitions for the CoreLibreILA module, including register offsets, field offsets, masks, and descriptions. It serves as a reference for software developers to interact with the CoreLibreILA hardware.
 *
 * Currently, the field definitions are based on the default configuration of the CoreLibreILA module. If the module is synthesized with different parameters, the register definitions may need to be updated accordingly.
 *
 * Honestly speaking its useless, number of input/output registers very according to synthesis and this file needs to be updated after every synthesis. But we can use it as a template for future reference.
 *
 * Nothing in here knows what the probed bits mean. The ILA samples a probe word
 * of CORE_LIBRE_ILA_PROBE_WIDTH bits and this driver treats it as an opaque bit
 * vector throughout. Naming the individual bits is the project's job, do it in
 * your own header on top of the bit helpers below.
 *
 *******************************************************************************
 * REGISTER MAP
 *
 * Everything below scales with a = CORE_LIBRE_ILA_STRIDE_WIDTH, the register
 * stride the HDL uses for both the trigger vector and the sample buffer.
 *
 * Input registers (read/write), byte offsets from the AXI4Lite base address:
 *
 *   0x00                        TRIG_POS   position of the trigger sample
 *                                          inside the captured window
 *   0x04                        ARM_FT     any write arms the ILA, or forces a
 *                                          trigger when it is already armed
 *   0x08                        TRIG_CFG   bit0 = ANDOR, 0 -> AND, 1 -> OR
 *   0x0C                        RSVD       reserved
 *   0x10 + 4*n, n = 0..a-1      TRIG_COND  trigger vector condition
 *   0x10 + 4*(a+n), n = 0..a-1  TRIG_MASK  trigger vector mask
 *
 * Output registers (read only), byte offsets from CORE_LIBRE_ILA_OP_REGS_OFFSET:
 *
 *   0x00  STATUS              ARMED / TRIGD / DONE / STATE
 *   0x04  MGCKEY              0xb01dface
 *   0x08  SAMP_CLK_FREQ       synthesis time sampling clock frequency
 *   0x0C  WIDTH               total probed bits
 *   0x10  DEPTH               sample buffer depth
 *   0x14  RSVD                reserved
 *   0x18  SAMP_BUFF_TRIG_IDX  buffer index of the trigger sample
 *   0x1C  SAMP_BUFF_FRST_IDX  buffer index of the oldest sample
 *
 * Sample buffer, starting at CORE_LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET,
 * a registers per sample.
 *
 *******************************************************************************
 * PROBE WORD AND TRIGGER VECTOR
 *
 * One sample of the probe word is stored little endian across the first
 * CORE_LIBRE_ILA_N_LANES registers of its stride, probe bit i sitting in
 * register i/32 at shift i%32. Registers between CORE_LIBRE_ILA_N_LANES and the
 * stride boundary are padding and read back as zero.
 *
 * The trigger is no longer a handful of per signal flags, it is one bit per
 * probed bit, and both halves of it use that exact same layout:
 *
 *   TRIG_COND bit i   value probe bit i has to take to match
 *   TRIG_MASK bit i   1 lets probe bit i take part, 0 makes it a don't care
 *
 * TRIG_CFG.ANDOR then reduces the enabled bits:
 *
 *   ANDOR = 1 (OR)   trigger when any enabled bit matches
 *   ANDOR = 0 (AND)  trigger when every enabled bit matches
 *
 * @note An all zero TRIG_MASK in AND mode matches vacuously, so the ILA fires
 *       on the first sample after it is armed. Use OR mode with an all zero
 *       mask if the intent is "never trigger on the probe".
 */

#ifndef __CORE_LIBRE_ILA_REGISTERS_H
#define __CORE_LIBRE_ILA_REGISTERS_H    1

#include <stdint.h>

/* Total number of probed bits, G_PROBE_WIDTH in the HDL, reported whole by the
 * WIDTH register. The hardware does not split it and neither does this driver.
 * The default is the stock AXI4S build, 64 bits of TDATA plus the three
 * signalling ports. */
#ifndef CORE_LIBRE_ILA_PROBE_WIDTH
#define CORE_LIBRE_ILA_PROBE_WIDTH 67u
#warning "CORE_LIBRE_ILA_PROBE_WIDTH is not defined, using default value of 67. Please define it in your project settings or in a header file before including this file."
#endif

#ifndef CORE_LIBRE_ILA_SAMP_BUFF_DEPTH
#define CORE_LIBRE_ILA_SAMP_BUFF_DEPTH 2048u
#warning "CORE_LIBRE_ILA_SAMP_BUFF_DEPTH is not defined, using default value of 2048. Please define it in your project settings or in a header file before including this file."
#endif

// We are already harrassing the user to define these variables, why not add frequency too?
#ifndef CORE_LIBRE_ILA_SAMP_FREQ_HZ
#define CORE_LIBRE_ILA_SAMP_FREQ_HZ 100000000u
#warning "CORE_LIBRE_ILA_SAMP_FREQ_HZ is not defined, using default value of 100 MHz. Please define it in your project settings or in a header file before including this file."
#endif

/* Registers a single sample actually occupies, the probe word packed 32 bits
 * at a time. Mirrors C_N_LANES in the HDL. */
#define CORE_LIBRE_ILA_N_LANES  ((CORE_LIBRE_ILA_PROBE_WIDTH + 31u) / 32u)

/* Register stride, the next power of two above the lane count with a minimum
 * of 4 so the control registers always fit. Mirrors the HDL get_stride().
 * Do not confuse this with the lane count, a 64 bit probe uses 3 lanes but a
 * stride of 4. */
#ifndef CORE_LIBRE_ILA_STRIDE_WIDTH
#define CORE_LIBRE_ILA_STRIDE_WIDTH                 \
        ((CORE_LIBRE_ILA_N_LANES <=  4u) ?  4u :    \
         (CORE_LIBRE_ILA_N_LANES <=  8u) ?  8u :    \
         (CORE_LIBRE_ILA_N_LANES <= 16u) ? 16u :    \
         (CORE_LIBRE_ILA_N_LANES <= 32u) ? 32u : 64u)
#endif

#define CORE_LIBRE_ILA_REG_BYTES    (4u)

#define CORE_LIBRE_ILA_N_IP_REGS    (4u + 2u * CORE_LIBRE_ILA_STRIDE_WIDTH)
#define CORE_LIBRE_ILA_N_OP_REGS    (8u)

#define CORE_LIBRE_ILA_N_CTRL_REGS  (CORE_LIBRE_ILA_N_IP_REGS + CORE_LIBRE_ILA_N_OP_REGS)

/* Registers taken by the sample buffer, and the grand total */
#define CORE_LIBRE_ILA_N_SAMP_REGS \
        (CORE_LIBRE_ILA_STRIDE_WIDTH * CORE_LIBRE_ILA_SAMP_BUFF_DEPTH)
#define CORE_LIBRE_ILA_N_REGS \
        (CORE_LIBRE_ILA_N_CTRL_REGS + CORE_LIBRE_ILA_N_SAMP_REGS)

#define CORE_LIBRE_ILA_OP_REGS_OFFSET \
        (CORE_LIBRE_ILA_N_IP_REGS * CORE_LIBRE_ILA_REG_BYTES)

/*******************************************************************************
 * Probe bit helpers
 *
 * Same mapping for a trigger vector and for a sample read out of the buffer,
 * probe bit i lives in word i/32 at shift i%32. Build your project's own named
 * bits on top of these, for example
 *
 *   #define MY_PROBE_FIFO_FULL_BIT   (17u)
 *   cond[LIBRE_ILA_BIT_WORD(MY_PROBE_FIFO_FULL_BIT)] |=
 *           LIBRE_ILA_BIT_MASK(MY_PROBE_FIFO_FULL_BIT);
 */
#define LIBRE_ILA_BIT_WORD(bit)     ((bit) / 32u)
#define LIBRE_ILA_BIT_SHIFT(bit)    ((bit) % 32u)
#define LIBRE_ILA_BIT_MASK(bit)     ((uint32_t)(1UL << LIBRE_ILA_BIT_SHIFT(bit)))

/* Word w of sample n inside a buffer filled by LIBRE_ILA_read_data() */
#define LIBRE_ILA_SAMPLE_WORD(buff, n, w) \
        ((buff)[((n) * CORE_LIBRE_ILA_N_LANES) + (w)])

/* Bit b of sample n inside a buffer filled by LIBRE_ILA_read_data() */
#define LIBRE_ILA_SAMPLE_BIT(buff, n, b) \
        ((LIBRE_ILA_SAMPLE_WORD(buff, n, LIBRE_ILA_BIT_WORD(b)) >> LIBRE_ILA_BIT_SHIFT(b)) & 1u)

/* Width of the trigger vector in bits, padding included */
#define CORE_LIBRE_ILA_TRIG_VECT_WIDTH \
        (CORE_LIBRE_ILA_STRIDE_WIDTH * 32u)

/*******************************************************************************
 * Register: TRIG_POS_REG
 *
 * Description: Position of the trigger sample inside the captured window, in
 * samples. 0 keeps the whole buffer for post trigger samples, DEPTH-1 keeps it
 * all for pre trigger samples. The hardware captures (DEPTH - TRIG_POS - 1)
 * samples after the trigger fires.
 */
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET       0x00U
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_RW_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_POS_REG_WRITE_MASK   0xFFFFFFFFU

/*******************************************************************************
 * Register: ARM_FT_REG
 *
 * Description: Any write to this register will arm the ILA if not armed or
 * trigger is forced if already armed. The written value is irrelevant, the
 * hardware toggles an internal arm request on the write itself.
 */
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_OFFSET       0x04U
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_WO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_READ_MASK    0x00000000U
#define CORE_LIBRE_ILA_REGS_ARM_FT_REG_WRITE_MASK   0xFFFFFFFFU

/*******************************************************************************
 * Register: TRIG_CFG_REG
 *
 * Description: Selects how the enabled bits of the trigger vector are reduced
 * into the single trigger strobe.
 */
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET       0x08U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_RW_MASK      0x00000001U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_READ_MASK    0x00000001U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_WRITE_MASK   0x00000001U

/**
 * Field Name: ANDOR
 *
 * Field Desc: Reduction applied to the masked trigger vector. 1 selects OR, the
 * ILA triggers as soon as any enabled bit matches its condition. 0 selects AND,
 * every enabled bit has to match at the same time.
 */

#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_ANDOR_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_ANDOR_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_ANDOR_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_ANDOR_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_ANDOR_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_ANDOR_FIELD_SHIFT)

/*******************************************************************************
 * Register: RSVD_IN_REG
 *
 * Description: Reserved input register, reads back whatever was written to it
 * and has no effect on the hardware.
 */
#define CORE_LIBRE_ILA_REGS_RSVD_IN_REG_OFFSET       0x0CU
#define CORE_LIBRE_ILA_REGS_RSVD_IN_REG_LENGTH       0x04U

/*******************************************************************************
 * Register: TRIG_COND_REG
 *
 * Description: Condition half of the trigger vector, CORE_LIBRE_ILA_STRIDE_WIDTH registers starting here. Bit i holds the value probe bit i has to take for that bit to match. See the PROBE WORD AND TRIGGER VECTOR block at the top of this file.
 */
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET       0x10U
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_LENGTH       (CORE_LIBRE_ILA_STRIDE_WIDTH * CORE_LIBRE_ILA_REG_BYTES)
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_RW_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_WRITE_MASK   0xFFFFFFFFU

/* Byte offset of condition register n, n = 0 .. CORE_LIBRE_ILA_STRIDE_WIDTH-1 */
#define CORE_LIBRE_ILA_REGS_TRIG_COND_WORD_OFFSET(n)  \
        (CORE_LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET + ((n) * CORE_LIBRE_ILA_REG_BYTES))

/*******************************************************************************
 * Register: TRIG_MASK_REG
 *
 * Description: Mask half of the trigger vector, CORE_LIBRE_ILA_STRIDE_WIDTH registers starting here and using the same bit layout as TRIG_COND. A bit set to 1 enables the matching TRIG_COND bit, a bit set to 0 makes it a don't care.
 */
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET       \
        (CORE_LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET + \
         (CORE_LIBRE_ILA_STRIDE_WIDTH * CORE_LIBRE_ILA_REG_BYTES))
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_LENGTH       (CORE_LIBRE_ILA_STRIDE_WIDTH * CORE_LIBRE_ILA_REG_BYTES)
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_RW_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_WRITE_MASK   0xFFFFFFFFU

/* Byte offset of mask register n, n = 0 .. CORE_LIBRE_ILA_STRIDE_WIDTH-1 */
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_WORD_OFFSET(n)  \
        (CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET + ((n) * CORE_LIBRE_ILA_REG_BYTES))

/* HERE STARTS THE OUTPUT REGISTERS */
/*******************************************************************************
 * Register: STATUS_REG
 *
 * Description: This register is used to read the status of the ILA. It provides information about whether the ILA is idle, armed, triggered, or done capturing data.
 */
#define CORE_LIBRE_ILA_REGS_STATUS_REG_OFFSET       (0x00U + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_STATUS_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_STATUS_REG_RO_MASK      0x0000001FU
#define CORE_LIBRE_ILA_REGS_STATUS_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_STATUS_REG_READ_MASK    0x0000001FU
#define CORE_LIBRE_ILA_REGS_STATUS_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: ARMED
 *
 * Field Desc: Shows whether the ILA is armed. When set, the ILA is ready to capture data based on the configured trigger conditions. This bit is CDCed with 2FF.
 */

#define CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_SHIFT)

/**
 * Field Name: TRIGD
 *
 * Field Desc: Shows whether the ILA is triggered. When set, the ILA has detected a trigger event. This bit is CDCed with 2FF.
 */

#define CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_SHIFT      (1U)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_SHIFT)

/**
 * Field Name: DONE
 *
 * Field Desc: Shows whether the ILA is done capturing data. When set, the ILA has completed its data capture operation. This bit is CDCed with 2FF.
 */

#define CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_SHIFT      (2U)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_NS_MASK    ((uint32_t)(0x00000001UL))
#define CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_SHIFT)

/**
 * Field Name: STATE
 *
 * Field Desc: Raw two bit state of the ILA state machine, 0 idle, 1 armed, 2 triggered, 3 done. This field is NOT CDCed, it is a direct reflection of the internal state machine and can be sampled mid transition. Use the ARMED/TRIGD/DONE bits for anything the software depends on, this one is for debug.
 */

#define CORE_LIBRE_ILA_REGS_STATUS_REG_STATE_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_STATUS_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_STATE_FIELD_SHIFT      (3U)
#define CORE_LIBRE_ILA_REGS_STATUS_REG_STATE_FIELD_NS_MASK    ((uint32_t)(0x00000003UL))
#define CORE_LIBRE_ILA_REGS_STATUS_REG_STATE_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_STATUS_REG_STATE_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_STATUS_REG_STATE_FIELD_SHIFT)

/*******************************************************************************
 * Register: MGCKEY_REG
 *
 * Description: This register stores the MAGIC_KEY value used to verify the AXI4Lite connection. It is used during initialization to ensure that the software can communicate with the hardware correctly.
 */
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_OFFSET       (0x04U + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: MGCKEY
 *
 * Field Desc: Constant value used to verify the AXI4Lite connection. The expected value is 0xb01dface. This field is read-only and is used during initialization to ensure that the software can communicate with the hardware correctly.
 */

#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_MGCKEY_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_MGCKEY_REG_MGCKEY_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_CLK_FREQ_REG
 *
 * Description: This register stores the synthesis time frequency of the clock the probe is sampled on. It is used to provide information about the clock frequency to the software for timing analysis and debugging purposes.
 */
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET       (0x08U + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: SAMP_CLK_FREQ
 *
 * Field Desc: Stores the synthesis time sampling clock frequency. This field is read-only and is used to provide information about the clock frequency to the software for timing analysis and debugging purposes.
 */

#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_SAMP_CLK_FREQ_FIELD_SHIFT)

/*******************************************************************************
 * Register: WIDTH_REG
 *
 * Description: This register stores the synthesis time width of the probe, as one number. It is used to provide information about the probe width to the software for timing analysis and debugging purposes.
 */
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_OFFSET       (0x0CU + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: PROBE_WIDTH
 *
 * Field Desc: Total number of probed bits the hardware was synthesised with. This field is read-only, and it is the only width the hardware reports, the lane count follows from it.
 */

#define CORE_LIBRE_ILA_REGS_WIDTH_REG_PROBE_WIDTH_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_WIDTH_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_PROBE_WIDTH_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_PROBE_WIDTH_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_PROBE_WIDTH_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_WIDTH_REG_PROBE_WIDTH_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_WIDTH_REG_PROBE_WIDTH_FIELD_SHIFT)

/*******************************************************************************
 * Register: DEPTH_REG
 *
 * Description: This register stores the synthesis time depth of the sampling buffer.
 */
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_OFFSET       (0x10U + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: BUFF_DEPTH
 *
 * Field Desc: Stores the synthesis time depth of the sampling buffer. This field is read-only and is used to provide information about the buffer depth to the software for timing analysis and debugging purposes.
 */

#define CORE_LIBRE_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_DEPTH_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_DEPTH_REG_BUFF_DEPTH_FIELD_SHIFT)

/*******************************************************************************
 * Register: RSVD_OUT_REG
 *
 * Description: Reserved output register, always reads back zero.
 */
#define CORE_LIBRE_ILA_REGS_RSVD_OUT_REG_OFFSET       (0x14U + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_RSVD_OUT_REG_LENGTH       0x04U

/*******************************************************************************
 * Register: SAMP_BUFF_TRIG_IDX_REG
 *
 * Description: This register stores the index of the sample buffer where the trigger event occurred.
 */
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET       (0x18U + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: SAMP_BUFF_TRIG_IDX
 *
 * Field Desc: Stores the index of the sample buffer where the trigger event occurred.
 */

#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_TRIG_IDX_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_TRIG_IDX_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_TRIG_IDX_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_TRIG_IDX_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_TRIG_IDX_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_TRIG_IDX_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_BUFF_FRST_IDX_REG
 *
 * Description: This register stores the index of the oldest sample held in the circular sample buffer, i.e. where a time ordered readback has to start.
 */
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET       (0x1CU + CORE_LIBRE_ILA_OP_REGS_OFFSET)
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: SAMP_BUFF_FRST_IDX
 *
 * Field Desc: Stores the index of the oldest sample held in the sample buffer.
 */

#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_FRST_IDX_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_FRST_IDX_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_FRST_IDX_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_FRST_IDX_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_FRST_IDX_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_FRST_IDX_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_BUFF_BASE_REG
 *
 * Description: This is the base address of the sample buffer. It marks the starting point of the sample buffer in memory. The sample buffer is used to store captured data from the ILA.
 *
 * Each sample takes CORE_LIBRE_ILA_STRIDE_WIDTH registers, the first
 * CORE_LIBRE_ILA_N_LANES of which carry probe bits, the rest read back as zero.
 *
 * Look at the docs to see how data is stored and how to read it.
 */
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET \
        (CORE_LIBRE_ILA_N_CTRL_REGS * CORE_LIBRE_ILA_REG_BYTES)

/* Bytes between two consecutive samples in the buffer */
#define CORE_LIBRE_ILA_SAMP_STRIDE_BYTES \
        (CORE_LIBRE_ILA_STRIDE_WIDTH * CORE_LIBRE_ILA_REG_BYTES)

/* Byte offset of lane "lane" of sample "samp" */
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_WORD_OFFSET(samp, lane)       \
        (CORE_LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET +            \
         ((samp) * CORE_LIBRE_ILA_SAMP_STRIDE_BYTES) +              \
         ((lane) * CORE_LIBRE_ILA_REG_BYTES))

#endif /* __CORE_LIBRE_ILA_REGISTERS_H */
