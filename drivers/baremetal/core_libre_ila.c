/*******************************************************************************
 * @file core_libre_ila.c
 * @author Y.U.P. (yashparitkar)
 * @brief CoreLibreILA bare metal driver implementation.
 *
 * @note Last Modified: 2026-07-31 Fri 12:02
 *
 * The probe is treated as a flat bit vector everywhere below, nothing in here
 * knows what any of its bits mean.
 *
 * Nothing here is built against one synthesis either. LIBRE_ILA_init() reads
 * the probe width and the buffer depth off the core and puts a base address
 * for each block of the register map in the instance, so every access below
 * adds a constant offset to the base of the block it wants. The two blocks
 * whose address depends on the probe width, the trigger mask and the sample
 * buffer, are the only ones that needed this, but doing it for all four is
 * what keeps the HAL_*_reg() macros usable: those paste the offset in at
 * preprocess time and cannot take a value worked out at runtime.
 *
 * Functions:
 *   cmd_status_t LIBRE_ILA_init( libre_ila_instance_t * this_libre_ila, addr_t base_addr);
 *   libre_ila_status_t LIBRE_ILA_get_status( libre_ila_instance_t * this_libre_ila);
 *
 *   cmd_status_t LIBRE_ILA_set_trigger_position( libre_ila_instance_t * this_libre_ila, uint32_t trig_pos);
 *   cmd_status_t LIBRE_ILA_configure_trigger( libre_ila_instance_t * this_libre_ila, const uint32_t * trigger_cond, const uint32_t * trigger_mask, uint32_t n_words, libre_ila_trig_mode_t mode);
 *
 *   cmd_status_t LIBRE_ILA_arm ( libre_ila_instance_t * this_libre_ila);
 *   cmd_status_t LIBRE_ILA_force_trigger ( libre_ila_instance_t * this_libre_ila);
 *
 *   cmd_status_t LIBRE_ILA_wait_done( libre_ila_instance_t * this_libre_ila, uint32_t timeout_ms);
 *
 *   cmd_status_t LIBRE_ILA_read_idx( libre_ila_instance_t * this_libre_ila, uint32_t * samp_buff_frst_idx, uint32_t * samp_buff_trig_idx);
 *   cmd_status_t LIBRE_ILA_read_data( libre_ila_instance_t * this_libre_ila, uint32_t * samp_buffer, uint32_t buffer_words, uint32_t * samp_buff_trig_idx);
 *
 */
#include "core_libre_ila_regs.h"
#include "core_libre_ila.h"

#ifndef MPFS_HAL_H_
#include "mpfs_hal/mss_hal.h"
#endif

/* mtime tick rate. VERIFY against your MSS/Libero config —
 * it's the RTC/timer reference, 1 MHz on the standard Icicle design. */
#ifndef LIBRE_ILA_MTIME_HZ
#define LIBRE_ILA_MTIME_HZ   1000000ULL
#endif

/* 64-bit math so timeout_ms * HZ can't overflow */
#define LIBRE_ILA_MS_TO_TICKS(ms)  (((uint64_t)(ms) * LIBRE_ILA_MTIME_HZ) / 1000ULL)

/*-------------------------------------------------------------------------*//**
 * Registers one sample takes in the map, the lane count rounded up to a power
 * of two with a minimum of four. Mirrors get_stride() in hdl/libre_ila.vhdl.
 * Done here rather than with the LIBRE_ILA_STRIDE_FOR() macro because the lane
 * count this runs on came off the wire, not out of a #define.
 */
static uint32_t libre_ila_stride_of(uint32_t n_lanes)
{
    uint32_t stride = 1u;

    while (stride < n_lanes)
    {
        stride <<= 1u;
    }

    return (stride < 4u) ? 4u : stride;
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_init()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_init
(
    libre_ila_instance_t *   this_libre_ila,
    addr_t              base_addr
)
{
    // 1. Check if the LIBRE_ILA instance pointer is NULL.
    // 2. Check if the MAGIC_KEY read from the hardware instance matches the expected value
    // 3. Read the geometry the hardware reports and derive the register map
    //    from it. The probe is one flat vector, so there is a single width.

    uint32_t mgckey_value;

    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    this_libre_ila->base_addr = base_addr;

    /* The output block sits at the base address in every build, which is what
     * makes the rest of this possible: the registers that report the geometry
     * are findable before the geometry is known. */
    this_libre_ila->op_base = base_addr + LIBRE_ILA_OP_BLOCK_OFFSET;
    this_libre_ila->ip_base = base_addr + LIBRE_ILA_IP_BLOCK_OFFSET;

    mgckey_value = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_MGCKEY);

    if (mgckey_value != MAGIC_KEY)
    {
        return CMD_STATUS_BAD_MAGIC_KEY; // Connection failed, return failure status
    }

    this_libre_ila->samp_clk_freq_hz = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ);
    this_libre_ila->probe_width      = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_WIDTH);
    this_libre_ila->samp_buff_depth  = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_DEPTH);

    /* Nothing is checked against a build time value any more, the map is built
     * out of these two, so a nonsense value has to be caught here rather than
     * surfacing later as an access at an address that means nothing. Both are
     * asserted at elaboration in the HDL, a core reporting otherwise is not
     * one whatever the magic key says. */
    if (this_libre_ila->probe_width == 0u)
    {
        return CMD_STATUS_BAD_CONFIG; // A probe has to have at least one bit
    }

    if (this_libre_ila->samp_buff_depth < 2u)
    {
        return CMD_STATUS_BAD_CONFIG; // A depth of one leaves no address bits
    }

    this_libre_ila->n_lanes      = (this_libre_ila->probe_width + 31u) / 32u;
    this_libre_ila->stride_width = libre_ila_stride_of(this_libre_ila->n_lanes);

    /* The two blocks whose address depends on the stride. Everything below them
     * is at a constant offset from op_base or ip_base. */
    this_libre_ila->mask_base =
            base_addr + LIBRE_ILA_MASK_BLOCK_OFFSET(this_libre_ila->stride_width);
    this_libre_ila->buff_base =
            base_addr + LIBRE_ILA_BUFF_BLOCK_OFFSET(this_libre_ila->stride_width);

    return CMD_STATUS_SUCCESS; // Connection successful, return success status
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_get_status()
 * See "core_libre_ila.h" for details of how to use this function.
 */
libre_ila_status_t LIBRE_ILA_get_status
(
    libre_ila_instance_t *   this_libre_ila
)
{
    uint32_t ila_status;

    if (this_libre_ila == NULL)
    {
        return LIBRE_ILA_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    /* The STATE field of the same register carries the raw state machine value,
     * but it is not synchronised into this clock domain. Decode the CDCed
     * ARMED/TRIGD/DONE bits instead, latest state first. */
    ila_status = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_STATUS);

    if ((ila_status & CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_MASK) != 0u)
    {
        return LIBRE_ILA_STATUS_DONE; // ILA acquisition complete
    }
    else if ((ila_status & CORE_LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_MASK) != 0u)
    {
        return LIBRE_ILA_STATUS_TRIGGERED; // ILA is triggered
    }
    else if ((ila_status & CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK) != 0u)
    {
        return LIBRE_ILA_STATUS_ARMED; // ILA is armed
    }
    else
    {
        return LIBRE_ILA_STATUS_IDLE; // ILA is idle
    }

}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_set_trigger_position()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_set_trigger_position
(
    libre_ila_instance_t *   this_libre_ila,
    uint32_t            trig_pos
)
{
    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    if (trig_pos >= this_libre_ila->samp_buff_depth)
    {
        return CMD_STATUS_BAD_PARAM; // Trigger has to sit inside the captured window
    }

    HAL_set_32bit_reg(this_libre_ila->ip_base, CORE_LIBRE_ILA_REGS_TRIG_POS, trig_pos);

    return CMD_STATUS_SUCCESS; // Trigger position set successfully
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_configure_trigger()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_configure_trigger
(
    libre_ila_instance_t *   this_libre_ila,
    const uint32_t *    trigger_cond,
    const uint32_t *    trigger_mask,
    uint32_t            n_words,
    libre_ila_trig_mode_t    mode
)
{
    uint32_t word_idx;

    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    if ((trigger_cond == NULL) || (trigger_mask == NULL))
    {
        return CMD_STATUS_BAD_PARAM; // Nothing to write from
    }

    /* Both halves span the whole stride, so a short array would leave the top
     * of the trigger holding whatever the last configuration left there, and a
     * long one says the caller thinks the core is a different shape than it is.
     * Neither is worth guessing at. */
    if (n_words != this_libre_ila->stride_width)
    {
        return CMD_STATUS_BAD_PARAM;
    }

    if ((((uint32_t)mode) & ~LIBRE_ILA_TRIG_MODE_VALID_BITS) != 0u)
    {
        return CMD_STATUS_BAD_PARAM; // TRIG_CFG defines bits 2 downto 0 and nothing else
    }

    /* Rising versus falling only means anything once the edge bit is set, the
     * core does not look at bit 2 in level mode. Asking for a falling level
     * trigger is a caller mistake worth reporting rather than ignoring. */
    if (((((uint32_t)mode) & (uint32_t)LIBRE_ILA_TRIG_FALLING) != 0u) &&
        ((((uint32_t)mode) & (uint32_t)LIBRE_ILA_TRIG_EDGE) == 0u))
    {
        return CMD_STATUS_BAD_PARAM;
    }

    /* Whole vector at once, the caller owns every bit of it including the
     * padding above the probe width.
     *
     * TRIG_COND is at a constant offset inside the input block, it is input
     * index 4 in every build. TRIG_MASK is a whole stride above it, which is
     * the first address in the map that moves with the probe width, so it has
     * its own base worked out in init(). */
    for (word_idx = 0u; word_idx < n_words; word_idx++)
    {
        HW_set_32bit_reg(this_libre_ila->ip_base + CORE_LIBRE_ILA_REGS_TRIG_COND_WORD_OFFSET(word_idx),
                         trigger_cond[word_idx]);

        HW_set_32bit_reg(this_libre_ila->mask_base + (word_idx * CORE_LIBRE_ILA_REG_BYTES),
                         trigger_mask[word_idx]);
    }

    /* The mode is the whole register. Writing it in one go rather than three
     * read-modify-writes of the ANDOR/EDGE/FALLING fields is safe because
     * everything above bit 2 is reserved, and it means a mode value always
     * lands whole instead of the trigger passing through a mixed state. */
    HW_set_32bit_reg(this_libre_ila->ip_base + CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET, (uint32_t)mode);

    return CMD_STATUS_SUCCESS; // Trigger configuration successful
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_arm()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_arm
(
    libre_ila_instance_t *   this_libre_ila
)
{
    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    // Check if the ILA is already armed
    uint32_t ila_arm_status = HAL_get_32bit_reg_field(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD);

    if (ila_arm_status == 1u)
    {
        return CMD_STATUS_ERROR; // ILA is already armed, another write would force a trigger
    }

    // The hardware arms on the write itself, the value written does not matter
    HAL_set_32bit_reg(this_libre_ila->ip_base, CORE_LIBRE_ILA_REGS_ARM_FT, 0x1u);

    return CMD_STATUS_SUCCESS; // ILA armed successfully
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_force_trigger()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_force_trigger
(
    libre_ila_instance_t *   this_libre_ila
)
{
    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    // Check if the ILA is already armed
    uint32_t ila_arm_status = HAL_get_32bit_reg_field(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD);

    if (ila_arm_status == 0u)
    {
        return CMD_STATUS_ERROR; // ILA is not armed, the write would arm it instead
    }

    // Same register as the arm, an armed ILA reads the write as a forced trigger
    HAL_set_32bit_reg(this_libre_ila->ip_base, CORE_LIBRE_ILA_REGS_ARM_FT, 0x1u);

    return CMD_STATUS_SUCCESS; // Force trigger send successfully
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_wait_done()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_wait_done
(
    libre_ila_instance_t *   this_libre_ila,
    uint32_t            timeout_ms
)
{
    uint64_t deadline;
    uint32_t ila_status;

    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // fail fast instead of busy-looping the full timeout
    }

    deadline = readmtime() + LIBRE_ILA_MS_TO_TICKS(timeout_ms);

    do
    {

        ila_status = HAL_get_32bit_reg_field(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD);
        if (ila_status == 1u)
        {
            return CMD_STATUS_SUCCESS;
        }
        /* optional: a short pause here if you want to ease bus traffic/power */
    } while (readmtime() < deadline);

    return CMD_STATUS_TIMEOUT;
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_read_idx()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_read_idx
(
    libre_ila_instance_t *   this_libre_ila,
    uint32_t *          samp_buff_frst_idx,
    uint32_t *          samp_buff_trig_idx
)
{
    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // fail fast instead of busy-looping the full timeout
    }

    if ((samp_buff_frst_idx == NULL) || (samp_buff_trig_idx == NULL))
    {
        return CMD_STATUS_BAD_PARAM; // Nowhere to store the indices
    }

    * samp_buff_frst_idx = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX);
    * samp_buff_trig_idx = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX);

    return CMD_STATUS_SUCCESS;
}

/*-------------------------------------------------------------------------*//**
 * LIBRE_ILA_read_data()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_read_data
(
    libre_ila_instance_t * this_libre_ila,
    uint32_t * samp_buffer,
    uint32_t buffer_words,
    uint32_t * samp_buff_trig_idx
)
{
    uint32_t samp_buff_frst_idx;
    uint32_t trig_idx;
    uint32_t depth;
    uint32_t n_lanes;
    uint32_t stride_bytes;
    uint32_t i;

    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // fail fast instead of busy-looping the full timeout
    }

    if ((samp_buffer == NULL) || (samp_buff_trig_idx == NULL))
    {
        return CMD_STATUS_BAD_PARAM; // Nowhere to store the capture
    }

    depth   = this_libre_ila->samp_buff_depth;
    n_lanes = this_libre_ila->n_lanes;

    /* Exact rather than "at least", because the caller reads this buffer back
     * with LIBRE_ILA_SAMPLE_WORD(), which multiplies by the lane count it was
     * compiled with. A buffer sized for a wider probe than the core actually
     * has would pass an "at least" check, get filled at one row length and be
     * indexed at another. */
    if (buffer_words != (depth * n_lanes))
    {
        return CMD_STATUS_BAD_PARAM;
    }

    samp_buff_frst_idx = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX);
    trig_idx           = HAL_get_32bit_reg(this_libre_ila->op_base, CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX);

    /* Both indices point into the circular buffer, the readback below unrolls
     * it from the oldest sample, so rebase the trigger onto the output. */
    * samp_buff_trig_idx = (trig_idx + depth - samp_buff_frst_idx) % depth;

    /* Bytes from one sample to the next. The stride is what the hardware
     * spends, the lane count is what carries probe bits, and the difference is
     * the padding dropped below. */
    stride_bytes = this_libre_ila->stride_width * CORE_LIBRE_ILA_REG_BYTES;

    for( i = 0u; i < depth; i++)
    {
        uint32_t idx = (samp_buff_frst_idx + i) % depth;
        uint32_t lane;

        for (lane = 0u; lane < n_lanes; lane++)
        {
            LIBRE_ILA_SAMPLE_WORD_N(samp_buffer, n_lanes, i, lane) =
                    HW_get_32bit_reg(this_libre_ila->buff_base +
                                     (idx * stride_bytes) +
                                     (lane * CORE_LIBRE_ILA_REG_BYTES));
        }
    }

    return CMD_STATUS_SUCCESS;
}
