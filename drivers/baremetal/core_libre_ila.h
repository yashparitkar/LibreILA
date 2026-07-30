/*******************************************************************************
 * @file core_libre_ila.h
 * @author Y.U.P. (yashparitkar)
 * @brief Core LIBRE_ILA bare metal driver public API.
 *
 * @note Last Modified: 2026-07-27 Mon
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

  The trigger is one bit per probed bit and lives in two register banks of
  CORE_LIBRE_ILA_STRIDE_WIDTH words each. TRIG_COND holds the value each probe
  bit has to take, TRIG_MASK selects which bits take part, and the mode
  argument reduces the enabled bits, OR fires on the first bit that matches,
  AND needs all of them to match at once. Both banks use the same bit layout as
  a sample, probe bit i sitting in word i/32 at shift i%32, which is what the
  LIBRE_ILA_BIT_WORD() and LIBRE_ILA_BIT_MASK() macros compute.

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

    LIBRE_ILA_configure_trigger(&ila, cond, mask, LIBRE_ILA_TRIG_MODE_AND);

    LIBRE_ILA_arm(&ila);
    LIBRE_ILA_wait_done(&ila, 1000u);
    LIBRE_ILA_read_data(&ila, samples, &trig_pos);

    // probe bit 3 of the sample that triggered the ILA
    LIBRE_ILA_SAMPLE_BIT(samples, trig_pos, MY_PROBE_ERR_BIT);
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
    CMD_STATUS_BAD_CONFIG = -3,   /**< Command failed due to defined  configuration no matching hardware. eg, invalid buffer depth or probe width */
    CMD_STATUS_BAD_CLK_FREQ = -4,   /**< Command failed due defined clock frequency does not match hardware */
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

/*-------------------------------------------------------------------------*//** Structure instance holding all data regarding the CoreLibreILA
 */
typedef struct __libre_ila_instance_t
{
    addr_t              base_addr; // base addr of LIBRE_ILA AXI4L
} libre_ila_instance_t;

/*
 * Field Name: MAGIC_KEY
 * Field Desc: MAGIC_KEY to verify the AXI4Lite connection
 */
#define MAGIC_KEY               0xb01dface

/*-------------------------------------------------------------------------*//**
The LIBRE_ILA_init() function initializes the CoreLibreILA driver instance with thte base address of the CoreLibreILA hardware instance and the function pointers to send through PCDMA.

The init function checks the connection to the hardware by reading the MAGIC_KEY register, if the read value does not match the expected MAGIC_KEY value, the function returns failure status.

It also checks the synthesis time parameters reported by the hardware against the CORE_LIBRE_ILA_* values this driver was built with, since the whole register map is derived from them. The hardware reports one probe width, so there is a single width to agree on.

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
    Index of the trigger sample within the captured window, in samples. Has to be smaller than CORE_LIBRE_ILA_SAMP_BUFF_DEPTH.

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
    Pointer to an array of CORE_LIBRE_ILA_STRIDE_WIDTH words written to the TRIG_COND bank. Bit i is the value probe bit i has to take to match.

  @param trigger_mask
    Pointer to an array of CORE_LIBRE_ILA_STRIDE_WIDTH words written to the TRIG_MASK bank. Bit i set to 1 lets probe bit i take part in the trigger, 0 makes it a don't care.

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

Samples are stored packed, CORE_LIBRE_ILA_N_LANES words each, the padding words the hardware inserts up to the register stride are dropped. Word w of sample n is samp_buffer[n * CORE_LIBRE_ILA_N_LANES + w], or LIBRE_ILA_SAMPLE_WORD(samp_buffer, n, w), and probe bit b of sample n is LIBRE_ILA_SAMPLE_BIT(samp_buffer, n, b).

  @param this_libre_ila
    Pointer to the libre_ila_instance_t to operate on.

  @param samp_buffer
    Pointer to a uint32_t array where the captured probe words will be stored. The array has to hold at least (CORE_LIBRE_ILA_SAMP_BUFF_DEPTH * CORE_LIBRE_ILA_N_LANES) words.

  @param samp_buff_trig_idx
    Pointer to a uint32_t variable where the position of the trigger sample within samp_buffer will be stored. It is already rebased on the first sample, so sample number *samp_buff_trig_idx is the one that triggered the ILA.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t LIBRE_ILA_read_data
(
    libre_ila_instance_t * this_libre_ila,
    uint32_t * samp_buffer,
    uint32_t * samp_buff_trig_idx
);

#ifdef __cplusplus
}
#endif

#endif /* CORE_LIBRE_ILA_H_ */
