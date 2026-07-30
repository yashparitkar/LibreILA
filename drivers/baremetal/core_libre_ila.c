/*******************************************************************************
 * @file core_libre_ila.c
 * @author Y.U.P. (yashparitkar)
 * @brief CoreLibreILA bare metal driver implementation.
 *
 * @note Last Modified: 2026-07-27 Mon
 *
 * The probe is treated as a flat bit vector everywhere below, nothing in here
 * knows what any of its bits mean.
 *
 * Functions:
 *   cmd_status_t LIBRE_ILA_init( libre_ila_instance_t * this_libre_ila, addr_t base_addr);
 *   libre_ila_status_t LIBRE_ILA_get_status( libre_ila_instance_t * this_libre_ila);
 *
 *   cmd_status_t LIBRE_ILA_set_trigger_position( libre_ila_instance_t * this_libre_ila, uint32_t trig_pos);
 *   cmd_status_t LIBRE_ILA_configure_trigger( libre_ila_instance_t * this_libre_ila, const uint32_t * trigger_cond, const uint32_t * trigger_mask, libre_ila_trig_mode_t mode);
 *
 *   cmd_status_t LIBRE_ILA_arm ( libre_ila_instance_t * this_libre_ila);
 *   cmd_status_t LIBRE_ILA_force_trigger ( libre_ila_instance_t * this_libre_ila);
 *
 *   cmd_status_t LIBRE_ILA_wait_done( libre_ila_instance_t * this_libre_ila, uint32_t timeout_ms);
 *
 *   cmd_status_t LIBRE_ILA_read_idx( libre_ila_instance_t * this_libre_ila, uint32_t * samp_buff_frst_idx, uint32_t * samp_buff_trig_idx);
 *   cmd_status_t LIBRE_ILA_read_data( libre_ila_instance_t * this_libre_ila, uint32_t * samp_buffer, uint32_t * samp_buff_trig_idx);
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
 * LIBRE_ILA_init()
 * See "core_libre_ila.h" for details of how to use this function.
 */
cmd_status_t LIBRE_ILA_init
(
    libre_ila_instance_t *   this_libre_ila,
    addr_t              base_addr
)
{
    // Check if the defined values are true against the hardware instance.
    // 1. Check if the LIBRE_ILA instance pointer is NULL.
    // 2. Check if the MAGIC_KEY read from the hardware instance matches the expected value
    // 3. Check buffer depth and probe width against the hardware instance.
    //    The probe is one flat vector, there is a single width to agree on.
    // 4. Check if the clock frequency matches the expected value

    uint32_t mgckey_value;
    uint32_t buffer_depth_value;
    uint32_t probe_width_value;
    uint32_t samp_clk_freq_value;

    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // Bad LIBRE_ILA instance
    }

    this_libre_ila->base_addr = base_addr;

    mgckey_value = HAL_get_32bit_reg(this_libre_ila->base_addr,  CORE_LIBRE_ILA_REGS_MGCKEY);

    if (mgckey_value != MAGIC_KEY)
    {
        return CMD_STATUS_BAD_MAGIC_KEY; // Connection failed, return failure status
    }

    buffer_depth_value = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_DEPTH);

    if (buffer_depth_value != CORE_LIBRE_ILA_SAMP_BUFF_DEPTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    /* One width to check, the lane count and hence the whole register map is
     * derived from it. */
    probe_width_value = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_WIDTH);

    if (probe_width_value != CORE_LIBRE_ILA_PROBE_WIDTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    samp_clk_freq_value = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_SAMP_CLK_FREQ);

    if (samp_clk_freq_value != CORE_LIBRE_ILA_SAMP_FREQ_HZ)
    {
        return CMD_STATUS_BAD_CLK_FREQ; // Connection failed, return failure status
    }

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
    ila_status = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_STATUS);

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

    if (trig_pos >= CORE_LIBRE_ILA_SAMP_BUFF_DEPTH)
    {
        return CMD_STATUS_BAD_PARAM; // Trigger has to sit inside the captured window
    }

    HAL_set_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_TRIG_POS, trig_pos);

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
     * padding above the probe width. */
    for (word_idx = 0u; word_idx < CORE_LIBRE_ILA_STRIDE_WIDTH; word_idx++)
    {
        HW_set_32bit_reg(this_libre_ila->base_addr + CORE_LIBRE_ILA_REGS_TRIG_COND_WORD_OFFSET(word_idx),
                         trigger_cond[word_idx]);

        HW_set_32bit_reg(this_libre_ila->base_addr + CORE_LIBRE_ILA_REGS_TRIG_MASK_WORD_OFFSET(word_idx),
                         trigger_mask[word_idx]);
    }

    /* The mode is the whole register. Writing it in one go rather than three
     * read-modify-writes of the ANDOR/EDGE/FALLING fields is safe because
     * everything above bit 2 is reserved, and it means a mode value always
     * lands whole instead of the trigger passing through a mixed state. */
    HW_set_32bit_reg(this_libre_ila->base_addr + CORE_LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET, (uint32_t)mode);

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
    uint32_t ila_arm_status = HAL_get_32bit_reg_field(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD);

    if (ila_arm_status == 1u)
    {
        return CMD_STATUS_ERROR; // ILA is already armed, another write would force a trigger
    }

    // The hardware arms on the write itself, the value written does not matter
    HAL_set_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_ARM_FT, 0x1u);

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
    uint32_t ila_arm_status = HAL_get_32bit_reg_field(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD);

    if (ila_arm_status == 0u)
    {
        return CMD_STATUS_ERROR; // ILA is not armed, the write would arm it instead
    }

    // Same register as the arm, an armed ILA reads the write as a forced trigger
    HAL_set_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_ARM_FT, 0x1u);

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

        ila_status = HAL_get_32bit_reg_field(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD);
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

    * samp_buff_frst_idx = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX);
    * samp_buff_trig_idx = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX);

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
    uint32_t * samp_buff_trig_idx
)
{
    uint32_t samp_buff_frst_idx;
    uint32_t trig_idx;
    uint32_t i;

    if (this_libre_ila == NULL)
    {
        return CMD_STATUS_BAD_LIBRE_ILA; // fail fast instead of busy-looping the full timeout
    }

    if ((samp_buffer == NULL) || (samp_buff_trig_idx == NULL))
    {
        return CMD_STATUS_BAD_PARAM; // Nowhere to store the capture
    }

    samp_buff_frst_idx = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX);
    trig_idx           = HAL_get_32bit_reg(this_libre_ila->base_addr, CORE_LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX);

    /* Both indices point into the circular buffer, the readback below unrolls
     * it from the oldest sample, so rebase the trigger onto the output. */
    * samp_buff_trig_idx = (trig_idx + CORE_LIBRE_ILA_SAMP_BUFF_DEPTH - samp_buff_frst_idx)
                           % CORE_LIBRE_ILA_SAMP_BUFF_DEPTH;

    for( i = 0u; i < CORE_LIBRE_ILA_SAMP_BUFF_DEPTH; i++)
    {
        uint32_t idx = (samp_buff_frst_idx + i) % CORE_LIBRE_ILA_SAMP_BUFF_DEPTH;
        uint32_t lane;

        /* A sample takes CORE_LIBRE_ILA_STRIDE_WIDTH registers in hardware but
         * only the first CORE_LIBRE_ILA_N_LANES of them carry probe bits, the
         * rest is padding and gets dropped here. */
        for (lane = 0u; lane < CORE_LIBRE_ILA_N_LANES; lane++)
        {
            LIBRE_ILA_SAMPLE_WORD(samp_buffer, i, lane) =
                    HW_get_32bit_reg(this_libre_ila->base_addr +
                                     CORE_LIBRE_ILA_REGS_SAMP_BUFF_WORD_OFFSET(idx, lane));
        }
    }

    return CMD_STATUS_SUCCESS;
}
