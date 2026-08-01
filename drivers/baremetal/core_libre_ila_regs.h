/*******************************************************************************
 * @file core_libre_ila_regs.h
 * @author Y.U.P. (yashparitkar)
 * @brief CoreLibreILA register definitions
 *
 * @note Last Modified: 2026-07-29 Wed 20:02
 *
 * @details This file contains the register definitions for the CoreLibreILA module, including register offsets, field offsets, masks, and descriptions. It serves as a reference for software developers to interact with the CoreLibreILA hardware.
 *
 * Nothing in here has to be updated per synthesis any more. The offsets below
 * are relative to the block they belong to, and LIBRE_ILA_init() reads the
 * probe width and the buffer depth off the core and works the block bases out
 * from them, so the one file that used to need editing after every build is now
 * the same for all of them.
 *
 * Nothing in here knows what the probed bits mean. The ILA samples a probe word
 * of CORE_LIBRE_ILA_PROBE_WIDTH bits and this driver treats it as an opaque bit
 * vector throughout. Naming the individual bits is the project's job, do it in
 * your own header on top of the bit helpers below.
 *
 *******************************************************************************
 * REGISTER MAP
 *
 * Everything below scales with a = the register stride the HDL uses for both
 * the trigger vector and the sample buffer, which the instance carries as
 * stride_width.
 *
 * Output registers (read only), byte offsets from op_base, which is the
 * AXI4Lite base address itself. This block is eight registers whatever the core
 * was synthesised with, which is why it comes first: everything above it moves
 * with the probe width, and these are the registers that report the probe width
 * in the first place.
 *
 *   0x00  STATUS              ARMED / TRIGD / DONE / STATE
 *   0x04  MGCKEY              0xb01dface
 *   0x08  SAMP_CLK_FREQ       synthesis time sampling clock frequency
 *   0x0C  WIDTH               total probed bits
 *   0x10  DEPTH               sample buffer depth
 *   0x14  UID                 synthesis time identity of this instance
 *   0x18  SAMP_BUFF_TRIG_IDX  buffer index of the trigger sample
 *   0x1C  SAMP_BUFF_FRST_IDX  buffer index of the oldest sample
 *
 * Input registers (read/write), byte offsets from ip_base, which is eight
 * registers above the AXI4Lite base address:
 *
 *   0x00                    TRIG_POS   position of the trigger sample inside
 *                                      the captured window
 *   0x04                    ARM_FT     any write arms the ILA, or forces a
 *                                      trigger when it is already armed
 *   0x08                    TRIG_CFG   bit0 = ANDOR,   0 -> AND,   1 -> OR
 *                                      bit1 = EDGE,    0 -> level, 1 -> edge
 *                                      bit2 = FALLING, 0 -> rising
 *   0x0C                    RSVD       reserved
 *   0x10 + 4*n, n = 0..a-1  TRIG_COND  trigger vector condition
 *
 * Trigger vector mask, one stride of registers from mask_base, word n at
 * mask_base + 4*n. This is the first block whose address depends on a.
 *
 * Sample buffer from buff_base, a registers per sample.
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
 * TRIG_CFG.EDGE and TRIG_CFG.FALLING then decide what counts as a trigger on
 * that single reduced condition:
 *
 *   EDGE = 0                trigger while the condition is true
 *   EDGE = 1, FALLING = 0   trigger when it becomes true
 *   EDGE = 1, FALLING = 1   trigger when it becomes false
 *
 * Edge detection is applied to the reduced condition, not to each probe bit, so
 * "bit 5 rises and bit 9 falls in the same sample" is not expressible. In level
 * mode a condition that already holds when the ILA is armed triggers on the
 * first sample, which is what the edge modes exist to avoid.
 *
 * @note An all zero TRIG_MASK in AND mode matches vacuously, so the ILA fires
 *       on the first sample after it is armed. Use OR mode with an all zero
 *       mask if the intent is "never trigger on the probe".
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

#ifndef __CORE_LIBRE_ILA_REGISTERS_H
#define __CORE_LIBRE_ILA_REGISTERS_H    1

#include <stdint.h>

/*******************************************************************************
 * OFFSETS ARE RELATIVE TO THEIR OWN BLOCK
 *
 * Every offset below is measured from the start of the block it belongs to, not
 * from the peripheral base, and libre_ila_instance_t carries one base address
 * per block. So an access names its block and its register:
 *
 *   HAL_get_32bit_reg(ila->op_base, CORE_LIBRE_ILA_REGS_STATUS);
 *   HAL_set_32bit_reg(ila->ip_base, CORE_LIBRE_ILA_REGS_TRIG_POS, pos);
 *
 * This is what keeps the HAL macros usable. They paste REG_NAME##_REG_OFFSET at
 * preprocess time and cannot be handed anything worked out at runtime, so the
 * part that moves with the probe width has to live in the base rather than in
 * the offset. LIBRE_ILA_init() reads WIDTH and DEPTH out of the output block,
 * which sits at the peripheral base in every build, and computes the four bases
 * from them. Nothing here has to be told what the core was synthesised with,
 * and one binary can drive several cores of different probe widths.
 *
 * It also means a later core that grows the input block, a second trigger stage
 * say, moves ip_base and buff_base in init() and changes no offset in this file.
 *
 * The two indexed blocks, the trigger mask words and the sample buffer, are
 * arrays rather than named registers, so they go through HW_*_reg() with the
 * index folded into the address. They have a base each for the same reason.
 *
 * What the defines below are still for is sizing the arrays the caller hands
 * over. That cannot come from the hardware, it is storage in the caller's own
 * scope with no allocator to fall back on, so the size stays a build time
 * decision. LIBRE_ILA_configure_trigger() and LIBRE_ILA_read_data() now take
 * the length alongside the pointer and reject the call unless it matches what
 * the core needs, so a width guessed wrong is a CMD_STATUS_BAD_PARAM at the
 * call rather than an overrun or a buffer indexed at the wrong row length.
 */

/* Lane count and stride for an arbitrary width, so a second core of a different
 * width has something to size its arrays with. LIBRE_ILA_STRIDE_FOR mirrors
 * get_stride() in the HDL: the next power of two at or above the lane count,
 * minimum 4 so the control registers always fit. Do not confuse the two, a 67
 * bit probe uses 3 lanes but a stride of 4. */
#define LIBRE_ILA_LANES_FOR(width)   (((width) + 31u) / 32u)

#define LIBRE_ILA_STRIDE_FOR(width)                  \
        ((LIBRE_ILA_LANES_FOR(width) <=  4u) ?  4u : \
         (LIBRE_ILA_LANES_FOR(width) <=  8u) ?  8u : \
         (LIBRE_ILA_LANES_FOR(width) <= 16u) ? 16u : \
         (LIBRE_ILA_LANES_FOR(width) <= 32u) ? 32u : 64u)

/* Words LIBRE_ILA_configure_trigger() wants for each of cond and mask, and
 * words LIBRE_ILA_read_data() writes. The stride padding is dropped on the way
 * out of the buffer, so the sample count goes by lanes and not by stride. */
#define LIBRE_ILA_TRIG_WORDS(width)           (LIBRE_ILA_STRIDE_FOR(width))
#define LIBRE_ILA_SAMPLE_WORDS(width, depth)  (LIBRE_ILA_LANES_FOR(width) * (depth))

/* Total number of probed bits, G_PROBE_WIDTH in the HDL, reported whole by the
 * WIDTH register. The hardware does not split it and neither does this driver.
 * The default is the stock AXI4S build, 64 bits of TDATA plus the three
 * signalling ports. Sizing only, the driver reads its geometry off the core. */
#ifndef CORE_LIBRE_ILA_PROBE_WIDTH
#define CORE_LIBRE_ILA_PROBE_WIDTH 67u
#endif

#ifndef CORE_LIBRE_ILA_SAMP_BUFF_DEPTH
#define CORE_LIBRE_ILA_SAMP_BUFF_DEPTH 2048u
#endif

/* Nothing is derived from this one. The core reports it and the driver hands it
 * back in the instance, this is only somewhere to say what you expect. */
#ifndef CORE_LIBRE_ILA_SAMP_FREQ_HZ
#define CORE_LIBRE_ILA_SAMP_FREQ_HZ 100000000u
#endif

/* The same two for the global width, so existing declarations keep working */
#define CORE_LIBRE_ILA_N_LANES  LIBRE_ILA_LANES_FOR(CORE_LIBRE_ILA_PROBE_WIDTH)

#ifndef CORE_LIBRE_ILA_STRIDE_WIDTH
#define CORE_LIBRE_ILA_STRIDE_WIDTH  LIBRE_ILA_STRIDE_FOR(CORE_LIBRE_ILA_PROBE_WIDTH)
#endif

#define CORE_LIBRE_ILA_REG_BYTES    (4u)

/* Block sizes. The output one is fixed, the input one grows with the stride,
 * and both take a stride argument rather than reading the global one so
 * LIBRE_ILA_init() can pass what it read off the core. */
#define CORE_LIBRE_ILA_N_OP_REGS           (8u)
#define LIBRE_ILA_N_IP_REGS_FOR(stride)    (4u + 2u * (stride))
#define LIBRE_ILA_N_CTRL_REGS_FOR(stride)  \
        (CORE_LIBRE_ILA_N_OP_REGS + LIBRE_ILA_N_IP_REGS_FOR(stride))

/* Byte offset of each block from the peripheral base. The first two are
 * constant, the last two are where the probe width shows up. */
#define LIBRE_ILA_OP_BLOCK_OFFSET          (0u)
#define LIBRE_ILA_IP_BLOCK_OFFSET          \
        (CORE_LIBRE_ILA_N_OP_REGS * CORE_LIBRE_ILA_REG_BYTES)
#define LIBRE_ILA_MASK_BLOCK_OFFSET(stride)   \
        (LIBRE_ILA_IP_BLOCK_OFFSET +          \
         ((4u + (stride)) * CORE_LIBRE_ILA_REG_BYTES))
#define LIBRE_ILA_BUFF_BLOCK_OFFSET(stride)   \
        (LIBRE_ILA_N_CTRL_REGS_FOR(stride) * CORE_LIBRE_ILA_REG_BYTES)

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

/* Word w and bit b of sample n inside a buffer filled by
 * LIBRE_ILA_read_data(). The row length is the lane count, so these only hold
 * while the global CORE_LIBRE_ILA_PROBE_WIDTH is the width of the core the
 * buffer was read from. read_data() checks exactly that before it writes
 * anything, so a mismatch is a CMD_STATUS_BAD_PARAM rather than a row read at
 * the wrong stride. */
#define LIBRE_ILA_SAMPLE_WORD(buff, n, w) \
        LIBRE_ILA_SAMPLE_WORD_N(buff, CORE_LIBRE_ILA_N_LANES, n, w)

#define LIBRE_ILA_SAMPLE_BIT(buff, n, b) \
        LIBRE_ILA_SAMPLE_BIT_N(buff, CORE_LIBRE_ILA_N_LANES, n, b)

/* The same two with the row length spelled out, for a buffer read from a core
 * that is not the one the global width describes. Pass that instance's
 * n_lanes, which LIBRE_ILA_init() filled in from the core itself. */
#define LIBRE_ILA_SAMPLE_WORD_N(buff, lanes, n, w) \
        ((buff)[((n) * (lanes)) + (w)])

#define LIBRE_ILA_SAMPLE_BIT_N(buff, lanes, n, b)                        \
        ((LIBRE_ILA_SAMPLE_WORD_N(buff, lanes, n, LIBRE_ILA_BIT_WORD(b)) \
          >> LIBRE_ILA_BIT_SHIFT(b)) & 1u)

/* Width of the trigger vector in bits, padding included */
#define CORE_LIBRE_ILA_TRIG_VECT_WIDTH \
        (CORE_LIBRE_ILA_STRIDE_WIDTH * 32u)

/* HERE START THE OUTPUT REGISTERS, THE BLOCK AT THE BASE ADDRESS */
/*******************************************************************************
 * Register: STATUS_REG
 *
 * Description: This register is used to read the status of the ILA. It provides information about whether the ILA is idle, armed, triggered, or done capturing data.
 */
#define CORE_LIBRE_ILA_REGS_STATUS_REG_OFFSET       0x00U
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
#define CORE_LIBRE_ILA_REGS_MGCKEY_REG_OFFSET       0x04U
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
#define CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET       0x08U
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
#define CORE_LIBRE_ILA_REGS_WIDTH_REG_OFFSET       0x0CU
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
#define CORE_LIBRE_ILA_REGS_DEPTH_REG_OFFSET       0x10U
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
 * Register: UID_REG
 *
 * Description: This register stores the synthesis time identity of this instance of the core, so that a system carrying several of them can tell one from another. MGCKEY says that a core is a LibreILA, this says which LibreILA it is.
 */
#define CORE_LIBRE_ILA_REGS_UID_REG_OFFSET       0x14U
#define CORE_LIBRE_ILA_REGS_UID_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_UID_REG_RW_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_UID_REG_RO_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_UID_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_UID_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_UID_REG_WRITE_MASK   0x00000000U

/**
 * Field Name: UID
 *
 * Field Desc: Stores the synthesis time identity of this instance, G_UID in the HDL. This field is read-only. Every value is legal and zero means unset, so nothing is validated against it; it is a label for the host to match instances against, not a check that the core is a LibreILA.
 */

#define CORE_LIBRE_ILA_REGS_UID_REG_UID_FIELD_OFFSET     \
                (CORE_LIBRE_ILA_REGS_UID_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_UID_REG_UID_FIELD_SHIFT      (0U)
#define CORE_LIBRE_ILA_REGS_UID_REG_UID_FIELD_NS_MASK    ((uint32_t)(0xFFFFFFFFUL))
#define CORE_LIBRE_ILA_REGS_UID_REG_UID_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_UID_REG_UID_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_UID_REG_UID_FIELD_SHIFT)

/*******************************************************************************
 * Register: SAMP_BUFF_TRIG_IDX_REG
 *
 * Description: This register stores the index of the sample buffer where the trigger event occurred.
 */
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET       0x18U
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
#define CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET       0x1CU
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

/* HERE START THE INPUT REGISTERS, ONE BLOCK ABOVE THE OUTPUT ONE */
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
 * into the single trigger strobe, and whether that strobe follows the level of
 * the reduced condition or one of its two edges.
 */
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET       0x08U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_LENGTH       0x04U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_RW_MASK      0x00000007U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_READ_MASK    0x00000007U
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_WRITE_MASK   0x00000007U

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

/**
 * Field Name: EDGE
 *
 * Field Desc: What the trigger follows on the reduced condition. 0 selects the
 * level, the ILA triggers for as long as the condition holds, so a condition
 * that already holds at the arm fires on the first sample. 1 selects a
 * transition, direction picked by FALLING.
 */

#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_EDGE_FIELD_OFFSET      \
                (CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_EDGE_FIELD_SHIFT       (1U)
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_EDGE_FIELD_NS_MASK     ((uint32_t)(0x00000001UL))
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_EDGE_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_EDGE_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_EDGE_FIELD_SHIFT)

/**
 * Field Name: FALLING
 *
 * Field Desc: Which transition triggers when EDGE is set. 0 selects the rising
 * edge, the condition becoming true, 1 selects the falling edge, the condition
 * becoming false. The core does not look at this field when EDGE is clear.
 */

#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_FALLING_FIELD_OFFSET   \
                (CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET)
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_FALLING_FIELD_SHIFT    (2U)
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_FALLING_FIELD_NS_MASK  ((uint32_t)(0x00000001UL))
#define CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_FALLING_FIELD_MASK \
      (CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_FALLING_FIELD_NS_MASK << \
         CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_FALLING_FIELD_SHIFT)

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
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_RW_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_COND_REG_WRITE_MASK   0xFFFFFFFFU

/* Byte offset of condition register n from ip_base, n = 0 .. stride-1 */
#define CORE_LIBRE_ILA_REGS_TRIG_COND_WORD_OFFSET(n)  \
        (CORE_LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET + ((n) * CORE_LIBRE_ILA_REG_BYTES))

/*******************************************************************************
 * Register: TRIG_MASK_REG
 *
 * Description: Mask half of the trigger vector, one stride of registers using
 * the same bit layout as TRIG_COND. A bit set to 1 enables the matching
 * TRIG_COND bit, a bit set to 0 makes it a don't care.
 *
 * This is the first thing in the map whose address moves with the probe width,
 * so it does not get an offset here. It gets its own base in the instance,
 * mask_base, and word n is at mask_base + 4*n. The same goes for the sample
 * buffer, buff_base, whose word offsets are worked out in LIBRE_ILA_read_data()
 * from the instance's stride.
 *
 * Both are arrays rather than named registers, so neither was reachable through
 * the HAL_*_reg() macros to begin with, and both were already accessed with
 * HW_*_reg() and a computed address.
 */
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_RW_MASK      0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_RO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_WO_MASK      0x00000000U
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_READ_MASK    0xFFFFFFFFU
#define CORE_LIBRE_ILA_REGS_TRIG_MASK_REG_WRITE_MASK   0xFFFFFFFFU

#endif /* __CORE_LIBRE_ILA_REGISTERS_H */
