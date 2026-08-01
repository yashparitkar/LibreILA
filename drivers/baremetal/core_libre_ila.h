/*******************************************************************************
 * @file core_libre_ila.h
 * @author Y.U.P. (yashparitkar)
 * @brief Core LIBRE_ILA bare metal driver public API.
 *
 * @note Last Modified: 2026-07-27 Mon
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

/*=========================================================================*//**
  @mainpage CoreLibreILA Bare Metal Driver.

  @section intro_sec Introduction

  @section driver_configuration Driver Configuration

  @section theory_op Theory of Operation

  The ILA samples a probe word of CORE_LIBRE_ILA_PROBE_WIDTH bits on every
  cycle of its sampling clock into a circular buffer. It is armed, watches
  every sampled word against a trigger vector, and freezes the buffer once the
  requested number of post trigger samples has been captured.

  This driver never interprets the probe, it is a flat bit vector from bit 0 up
  to CORE_LIBRE_ILA_PROBE_WIDTH-1. What each bit means is a property of the
  design the ILA was wired into, so name the bits in your own project header.

  The trigger is one bit per probed bit and lives in two register banks of one
  stride each. TRIG_COND holds the value each probe bit has to take, TRIG_MASK
  selects which bits take part, and the mode argument reduces the enabled bits,
  OR fires on the first bit that matches, AND needs all of them to match at
  once. Both banks use the same bit layout as a sample, probe bit i sitting in
  word i/32 at shift i%32, which is what the LIBRE_ILA_BIT_WORD() and
  LIBRE_ILA_BIT_MASK() macros compute.

  LIBRE_ILA_init() takes the probe width, the buffer depth and the sampling
  clock frequency off the core and leaves them in the instance, so the driver
  is not built against any one synthesis. The arrays you hand it are the
  exception, since they are storage in your own scope: size them at build time
  and pass the length, and the driver rejects the call rather than writing past
  the end if the core turns out to want a different shape.

  A typical acquisition looks like this:

  @code
    #define MY_PROBE_ERR_BIT    (3u)
    #define MY_PROBE_STATE_LSB  (8u)

    libre_ila_instance_t ila;

    uint32_t cond[CORE_LIBRE_ILA_STRIDE_WIDTH] = {0};
    uint32_t mask[CORE_LIBRE_ILA_STRIDE_WIDTH] = {0};

    uint32_t samples[CORE_LIBRE_ILA_SAMP_BUFF_DEPTH * CORE_LIBRE_ILA_N_LANES];
    uint32_t trig_pos;

    LIBRE_ILA_init(&ila, LIBRE_ILA_BASE_ADDR);

    LIBRE_ILA_set_trigger_position(&ila, 64u);

    // trigger once probe bit 3 goes high
    cond[LIBRE_ILA_BIT_WORD(MY_PROBE_ERR_BIT)] |= LIBRE_ILA_BIT_MASK(MY_PROBE_ERR_BIT);
    mask[LIBRE_ILA_BIT_WORD(MY_PROBE_ERR_BIT)] |= LIBRE_ILA_BIT_MASK(MY_PROBE_ERR_BIT);

    LIBRE_ILA_configure_trigger(&ila, cond, mask,
                                CORE_LIBRE_ILA_STRIDE_WIDTH,
                                LIBRE_ILA_TRIG_MODE_AND);

    LIBRE_ILA_arm(&ila);
    LIBRE_ILA_wait_done(&ila, 1000u);
    LIBRE_ILA_read_data(&ila, samples,
                        sizeof(samples) / sizeof(samples[0]), &trig_pos);

    // probe bit 3 of the sample that triggered the ILA
    LIBRE_ILA_SAMPLE_BIT(samples, trig_pos, MY_PROBE_ERR_BIT);
  @endcode

  A second core of a different probe width cannot use the globals above, since
  they only describe one of them. Size its arrays from its own width and index
  them with the lane count out of its instance:

  @code
    #define MY_WIDE_PROBE_WIDTH  (512u)

    uint32_t wide_cond[LIBRE_ILA_TRIG_WORDS(MY_WIDE_PROBE_WIDTH)]   = {0};
    uint32_t wide[LIBRE_ILA_SAMPLE_WORDS(MY_WIDE_PROBE_WIDTH, 1024u)];

    LIBRE_ILA_read_data(&wide_ila, wide,
                        sizeof(wide) / sizeof(wide[0]), &trig_pos);

    LIBRE_ILA_SAMPLE_BIT_N(wide, wide_ila.n_lanes, trig_pos, MY_PROBE_ERR_BIT);
  @endcode

  Watch out for one corner, an all zero mask in AND mode matches vacuously and
  the ILA triggers on the first sample after arming.

 *//*=========================================================================*/
#ifndef CORE_LIBRE_ILA_H_
#define CORE_LIBRE_ILA_H_

#ifndef LEGACY_DIR_STRUCTURE
#include "hal/hal.h"

#else
#include "hal.h"
#endif

#include "core_libre_ila_regs.h"

#ifdef __cplusplus
extern "C" {
#endif


/*-------------------------------------------------------------------------*//** Enum for the status of a command sent to the CoreLibreILA hardware instance. */
typedef enum __cmd_status_t
{
    CMD_STATUS_SUCCESS = 0,   /**< Command completed successfully. */
    CMD_STATUS_BAD_LIBRE_ILA = -1,   /**< Command failed due to a bad LIBRE_ILA instance. */
    CMD_STATUS_BAD_MAGIC_KEY = -2,   /**< Command failed due to a bad MAGIC_KEY read from the CoreLibreILA hardware instance. */
    CMD_STATUS_BAD_CONFIG = -3,   /**< The hardware reported a geometry it could not have been elaborated with, eg a probe width of zero or a buffer depth below two. */
    CMD_STATUS_BAD_CLK_FREQ = -4,   /**< No longer returned. The sampling clock frequency is reported by the core into samp_clk_freq_hz and nothing is derived from it, so there is nothing left to disagree about. Kept so the enum values do not shift under code that switches on them. */
    CMD_STATUS_BAD_PARAM = -5,   /**< Command failed due to an out of range or NULL argument. */
    CMD_STATUS_TIMEOUT = 1,   /**< Command timed out before completion. */
    CMD_STATUS_ERROR   = 2    /**< Command completed with an error. */
} cmd_status_t;

/*-------------------------------------------------------------------------*//** Enum for the hardware state reported by LIBRE_ILA_get_status(). The values
 * match the STATE field of the STATUS register. */
typedef enum __libre_ila_status_t
{
    LIBRE_ILA_STATUS_BAD_LIBRE_ILA = -1,   /**< this_libre_ila is NULL. */
    LIBRE_ILA_STATUS_IDLE          =  0,   /**< ILA is idle */
    LIBRE_ILA_STATUS_ARMED         =  1,   /**< ILA is armed */
    LIBRE_ILA_STATUS_TRIGGERED     =  2,   /**< ILA is triggered */
    LIBRE_ILA_STATUS_DONE          =  3    /**< ILA acquisition complete */
} libre_ila_status_t;

/*-------------------------------------------------------------------------*//** Enum for the contents of the TRIG_CFG register: the reduction applied to the
 * enabled bits of the trigger vector, plus what counts as a trigger on the
 * reduced condition.
 *
 * The reduction and the edge flags OR together, so
 * LIBRE_ILA_TRIG_MODE_AND | LIBRE_ILA_TRIG_EDGE asks for "every enabled bit
 * matches, and trigger when that becomes true" rather than "while it is true".
 *
 * Level is the default. It fires on the first sample if the condition already
 * holds when the ILA is armed, which is rarely what a "trigger when TVALID is
 * high" style request means. */
typedef enum __libre_ila_trig_mode_t
{
    LIBRE_ILA_TRIG_MODE_AND = 0,   /**< Trigger when every enabled bit matches its condition. */
    LIBRE_ILA_TRIG_MODE_OR  = 1,   /**< Trigger when any enabled bit matches its condition. */
    LIBRE_ILA_TRIG_EDGE     = 2,   /**< OR in: trigger on a transition of the reduced condition, not its level. */
    LIBRE_ILA_TRIG_FALLING  = 4    /**< OR in alongside LIBRE_ILA_TRIG_EDGE: transition to false instead of to true. */
} libre_ila_trig_mode_t;

/*-------------------------------------------------------------------------*//** Every bit TRIG_CFG defines. The core ignores anything above them, so a stray
 * bit would leave the trigger in whatever mode the rest of the word asks for
 * instead of failing, which is worth catching on the host. */
#define LIBRE_ILA_TRIG_MODE_VALID_BITS  (0x7u)

/*-------------------------------------------------------------------------*//** Structure instance holding all data regarding the CoreLibreILA.
 *
 * Everything past base_addr is filled in by LIBRE_ILA_init() from what the core
 * itself reports, so nothing has to be told what the hardware was synthesised
 * with and two instances of different probe widths can be driven from one
 * binary. Treat the whole thing as read only once init() has returned.
 *
 * The four bases are one per block of the register map. Offsets in
 * core_libre_ila_regs.h are relative to their block, which is what lets the
 * HAL_*_reg() macros keep working: they paste the offset in at preprocess time,
 * so the part that moves with the probe width has to sit in the base.
 */
typedef struct __libre_ila_instance_t
{
    addr_t   base_addr;   /**< base addr of LIBRE_ILA AXI4L */

    addr_t   op_base;     /**< read only block, == base_addr */
    addr_t   ip_base;     /**< read/write block, eight registers above it */
    addr_t   mask_base;   /**< trigger vector mask, word n at mask_base + 4*n */
    addr_t   buff_base;   /**< sample buffer, stride_width registers per sample */

    uint32_t probe_width;      /**< G_PROBE_WIDTH, total probed bits */
    uint32_t samp_buff_depth;  /**< G_SAMP_BUFF_DEPTH, samples held */
    uint32_t samp_clk_freq_hz; /**< G_SAMP_CLK_FREQ, sampling clock */
    uint32_t uid;              /**< G_UID, identity of this instance, zero if
                                    the core was built without one. Nothing is
                                    derived from it, it is here so that code
                                    driving several cores can tell them apart */

    uint32_t n_lanes;      /**< 32 bit words a probe word takes, ceil(width/32) */
    uint32_t stride_width; /**< registers a sample takes, n_lanes rounded up to
                                a power of two with a minimum of four */
} libre_ila_instance_t;

/*
 * Field Name: MAGIC_KEY
 * Field Desc: MAGIC_KEY to verify the AXI4Lite connection
 */
#define MAGIC_KEY               0xb01dface

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_init() function initializes the CoreLibreILA driver instance with thte base address of the CoreLibreILA hardware instance and the function pointers to send through PCDMA.

The init function checks the connection to the hardware by reading the MAGIC_KEY register, if the read value does not match the expected MAGIC_KEY value, the function returns failure status.

It then reads the probe width, the buffer depth and the sampling clock frequency the hardware reports, and works the block base addresses out from them. Nothing is checked against a CORE_LIBRE_ILA_* build time value any more, the map comes from the core. A width or depth the HDL could not have been elaborated with is rejected as CMD_STATUS_BAD_CONFIG.

The instance uid is read into ila.uid on the way past. It is not checked against anything, since every value is legal and zero simply means the core was built without one. Where MAGIC_KEY answers "is this a LibreILA", the uid answers "which one", which is what lets one binary tell apart the several cores it may be driving.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t data structure instance holding all data
    regarding the CoreLibreILA hardware instance being initialized. A pointer to the   same data structure is used in subsequent calls to the CoreLibreILA driver
    functions in order to identify the CoreLibreILA instance that must perform the
    operation implemented by the called driver function.

  @param base_addr
    The base_addr parameter is the base address in the memory map of the
    processor for the AXI4Lite registers of the core LIBRE_ILA instance being initialized.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_init
(
    libre_ila_instance_t * this_libre_ila,
    addr_t            base_addr
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_get_status() function retrieves the current status of the CoreLibreILA hardware instance. This is done by reading the STATUS register of the CoreLibreILA hardware instance and interpreting the bits to determine the current state of the ILA.

The ARMED, TRIGD and DONE bits are used rather than the raw STATE field, they are the ones the hardware synchronises into the AXI4Lite clock domain.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @return
    libre_ila_status_t, see enum __libre_ila_status_t for details of the return values.
  */
libre_ila_status_t LIBRE_ILA_get_status
(
    libre_ila_instance_t * this_libre_ila
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_set_trigger_position() function sets where the trigger sample sits inside the captured window, by writing the TRIG_POS register. The hardware keeps capturing (DEPTH - trig_pos - 1) samples once the trigger fires, so 0 gives an all post trigger capture and DEPTH-1 an all pre trigger one.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @param trig_pos
    Index of the trigger sample within the captured window, in samples. Has to be smaller than the buffer depth the core reports, which the instance carries as samp_buff_depth.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_set_trigger_position
(
    libre_ila_instance_t * this_libre_ila,
    uint32_t trig_pos
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_configure_trigger() function writes the whole trigger vector, condition and mask, selects how the enabled bits are reduced and picks whether the trigger follows the level of that reduction or one of its edges. This is done by writing the TRIG_COND and TRIG_MASK banks and the whole TRIG_CFG register, whose ANDOR, EDGE and FALLING fields the mode argument carries.

Both arrays describe the probe word bit for bit, word n holding probe bits [32n+31:32n]. Use LIBRE_ILA_BIT_WORD() and LIBRE_ILA_BIT_MASK() to place a given probe bit. Words above the probe width are padding, keep them zero.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @param trigger_cond
    Pointer to an array of n_words words written to the TRIG_COND bank. Bit i is the value probe bit i has to take to match.

  @param trigger_mask
    Pointer to an array of n_words words written to the TRIG_MASK bank. Bit i set to 1 lets probe bit i take part in the trigger, 0 makes it a don't care.

  @param n_words
    Length of both arrays. Has to equal the stride the core reports, which the instance carries as stride_width and which LIBRE_ILA_TRIG_WORDS() computes for a width known at build time. A mismatch is CMD_STATUS_BAD_PARAM and nothing is written, since a short array would leave the top of the trigger holding whatever was there before.

  @param mode
    LIBRE_ILA_TRIG_MODE_OR to trigger as soon as any enabled bit matches its condition, LIBRE_ILA_TRIG_MODE_AND to require all of them to match at the same time. Either may be OR-ed with LIBRE_ILA_TRIG_EDGE to trigger on the reduced condition becoming true rather than being true, and with LIBRE_ILA_TRIG_FALLING alongside it to trigger on it becoming false instead. LIBRE_ILA_TRIG_FALLING on its own is rejected, a level trigger has no direction.

  @note In AND mode an all zero trigger mask matches vacuously, the ILA then fires on the first sample after it is armed.

  @note Without LIBRE_ILA_TRIG_EDGE the trigger is level sensitive, so a condition that already holds when the ILA is armed fires on the first sample and captures nothing of interest. "Trigger when TVALID is high" on a mostly idle stream is the usual way to meet this.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_configure_trigger
(
    libre_ila_instance_t * this_libre_ila,
    const uint32_t * trigger_cond,
    const uint32_t * trigger_mask,
    uint32_t n_words,
    libre_ila_trig_mode_t mode
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_arm() function arms the CoreLibreILA hardware instance. This is done by writing to the ARM_FT register of the CoreLibreILA hardware instance. Once armed, the ILA will start monitoring for the configured trigger conditions.

The written value does not matter, the hardware acts on the write itself.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_arm
(
    libre_ila_instance_t * this_libre_ila
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_force_trigger() function forces a trigger event on the CoreLibreILA hardware instance. This is done by writing to the ARM_FT register of the CoreLibreILA hardware instance. If the ILA is already armed, this will cause it to immediately trigger and start capturing data.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_force_trigger
(
    libre_ila_instance_t * this_libre_ila
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_wait_done() function polls the STATUS register of the CoreLibreILA hardware instance until the ILA has completed its data capture operation or until a specified timeout period has elapsed. This function is useful for synchronizing with the ILA's operation in a blocking manner.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @param timeout_ms
    The timeout_ms parameter specifies the maximum time in milliseconds to wait for the ILA to complete its operation. If the ILA does not complete within this time, the function will return a timeout status.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_wait_done
(
    libre_ila_instance_t * this_libre_ila,
    uint32_t timeout_ms
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_read_idx() function reads the indices of the sample buffer where the trigger event occurred and where the first sample was captured. This is done by reading the SAMP_BUFF_TRIG_IDX and SAMP_BUFF_FRST_IDX registers of the CoreLibreILA hardware instance.

Both are raw indices into the circular buffer, LIBRE_ILA_read_data() returns the trigger position already rebased on its own output.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @param samp_buff_frst_idx
    Pointer to a uint32_t variable where the index of the first sample in the sample buffer will be stored.

  @param samp_buff_trig_idx
    Pointer to a uint32_t variable where the index of the sample in the sample buffer where the trigger event occurred will be stored.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_read_idx
(
    libre_ila_instance_t * this_libre_ila,
    uint32_t * samp_buff_frst_idx,
    uint32_t * samp_buff_trig_idx
);

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_read_data() function reads the whole sample buffer into the provided buffer. This is done with increasing time index, starting from the first sample index, and wrapping around the sample buffer if necessary till all the samples are read. The function uses the SAMP_BUFF_TRIG_IDX and SAMP_BUFF_FRST_IDX registers of the CoreLibreILA hardware instance to determine the indices of the samples to read.

Samples are stored packed, this_libre_ila->n_lanes words each, the padding words the hardware inserts up to the register stride are dropped. Word w of sample n is samp_buffer[n * n_lanes + w], or LIBRE_ILA_SAMPLE_WORD(samp_buffer, n, w) when the core matches the global CORE_LIBRE_ILA_PROBE_WIDTH, and probe bit b of sample n is LIBRE_ILA_SAMPLE_BIT(samp_buffer, n, b). For a core of a different width use LIBRE_ILA_SAMPLE_WORD_N()/LIBRE_ILA_SAMPLE_BIT_N() and pass this_libre_ila->n_lanes.

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @param samp_buffer
    Pointer to a uint32_t array where the captured probe words will be stored.

  @param buffer_words
    Length of samp_buffer. Has to equal (samp_buff_depth * n_lanes) as the core reports them, which LIBRE_ILA_SAMPLE_WORDS() computes for a width and depth known at build time. The match is exact rather than "at least" on purpose: LIBRE_ILA_SAMPLE_WORD() indexes rows at the lane count it was compiled with, so a buffer sized for a wider probe than the core actually has would be filled at one row length and read back at another. A mismatch is CMD_STATUS_BAD_PARAM and nothing is written.

  @param samp_buff_trig_idx
    Pointer to a uint32_t variable where the position of the trigger sample within samp_buffer will be stored. It is already rebased on the first sample, so sample number *samp_buff_trig_idx is the one that triggered the ILA.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_read_data
(
    libre_ila_instance_t * this_libre_ila,
    uint32_t * samp_buffer,
    uint32_t buffer_words,
    uint32_t * samp_buff_trig_idx
);

#ifdef __cplusplus
}
#endif

#endif /* CORE_LIBRE_ILA_H_ */
