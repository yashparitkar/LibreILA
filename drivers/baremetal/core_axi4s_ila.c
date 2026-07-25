/*******************************************************************************
 * @file core_axi4s_ila.c
 * @author Y.U.P. (paritkary25)
 * @brief CoreAXI4S_ILA bare metal driver implementation.
 * 
 * @note Last Modified: 2026-07-24 Fri 20:46
 *
 * Functions:
 *   cmd_status_t AXI4S_ILA_init( axi4s_ila_instance_t * this_axi4s_ila, addr_t base_addr);
 *   axi4s_ila_status_t AXI4S_ILA_get_status( axi4s_ila_instance_t * this_axi4s_ila);
 * 
 *   cmd_status_t AXI4S_ILA_configure_trigger( axi4s_ila_instance_t * this_axi4s_ila, uint32_t trigger_cond, uint32_t trigger_mask);
 *   cmd_status_t AXI4S_ILA_configure_trigger_data( axi4s_ila_instance_t * this_axi4s_ila, uint64_t trigger_data_cond, uint64_t trigger_data_mask); 
 * 
 *   cmd_status_t AXI4S_ILA_arm ( axi4s_ila_instance_t * this_axi4s_ila);
 *   cmd_status_t AXI4S_ILA_force_trigger ( axi4s_ila_instance_t * this_axi4s_ila);
 * 
 *   cmd_status_t AXI4S_ILA_wait_done( axi4s_ila_instance_t * this_axi4s_ila, uint32_t timeout_ms);
 * 
 *   cmd_status_t AXI4S_ILA_read_idx( axi4s_ila_instance_t * this_axi4s_ila, uint32_t * samp_buff_frst_idx, uint32_t * samp_buff_trig_idx);
 *   cmd_status_t AXI4S_ILA_read_data( axi4s_ila_instance_t * this_axi4s_ila, uint64_t * data_buffer, uint8_t * signal_buffer, uint32_t  * samp_buff_trig_idx);
 *   
 */
#include "core_axi4s_ila_regs.h"
#include "core_axi4s_ila.h"

#ifndef MPFS_HAL_H_
#include "mpfs_hal/mss_hal.h"
#endif

/* mtime tick rate. VERIFY against your MSS/Libero config —
 * it's the RTC/timer reference, 1 MHz on the standard Icicle design. */
#ifndef AXI4S_ILA_MTIME_HZ
#define AXI4S_ILA_MTIME_HZ   1000000ULL
#endif

/* 64-bit math so timeout_ms * HZ can't overflow */
#define AXI4S_ILA_MS_TO_TICKS(ms)  (((uint64_t)(ms) * AXI4S_ILA_MTIME_HZ) / 1000ULL)

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_init()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_init
(
    axi4s_ila_instance_t *   this_axi4s_ila,
    addr_t              base_addr,
)
{
    // Check if the defined values are true against the hardware instance.
    // 1. Check if the AXI4S_ILA instance pointer is NULL.
    // 2. Check if the MAGIC_KEY read from the hardware instance matches the expected value
    // 3. Check buffer depth and data width against the hardware instance.
    // 4. Check if the clock frequency matches the expected value (warning only)

    uint32_t mgckey_value;
    uint32_t buffer_depth_value;
    uint32_t data_width_value;
    uint32_t signal_width_value;
    uint32_t samp_clk_freq_value;

    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    mgckey_value = HAL_get_32bit_reg(this_axi4s_ila->base_addr,  CORE_AXI4S_ILA_REGS_MGCKEY);

    if (mgckey_value != MAGIC_KEY)
    {
        return CMD_STATUS_BAD_MAGIC_KEY; // Connection failed, return failure status
    }

    buffer_depth_value = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_DEPTH);

    if (buffer_depth_value != CORE_AXI4S_ILA_SAMP_BUFF_DEPTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    data_width_value = HAL_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_WIDTH_REG_DATA_WIDTH);

    if (data_width_value != CORE_AXI4S_ILA_DATA_WIDTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    signal_width_value = HAL_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_WIDTH_REG_SIGNAL_WIDTH);

    if (signal_width_value != CORE_AXI4S_ILA_SIGNAL_WIDTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    samp_clk_freq_value = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ);

    if (samp_clk_freq_value != CORE_AXI4S_ILA_SAMP_FREQ_HZ)
    {
        return CMD_STATUS_BAD_CLK_FREQ; // Connection failed, return failure status
    }

    return CMD_STATUS_SUCCESS; // Connection successful, return success status
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_get_status()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
ila_status_t AXI4S_ILA_get_status
(
    axi4s_ila_instance_t *   this_axi4s_ila
)
{
    uint32_t ila_status;

    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    ila_status = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_STATUS);

    if (ila_status & CORE_AXI4S_ILA_STATUS_REG_DONE_MASK == CORE_AXI4S_ILA_STATUS_REG_DONE_MASK)
    {
        return AXI4S_ILA_STATUS_DONE; // ILA acquisition complete
    }
    else if (ila_status & CORE_AXI4S_ILA_STATUS_REG_TRIGGERED_MASK == CORE_AXI4S_ILA_STATUS_REG_TRIGGERED_MASK)
    {
        return AXI4S_ILA_STATUS_TRIGGERED; // ILA is triggered
    }
    else if (ila_status & CORE_AXI4S_ILA_STATUS_REG_ARMED_MASK == CORE_AXI4S_ILA_STATUS_REG_ARMED_MASK)
    {
        return AXI4S_ILA_STATUS_ARMED; // ILA is armed
    }
    else
    {
        return AXI4S_ILA_STATUS_IDLE; // ILA is idle
    }

}
/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_configure_trigger()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */

cmd_status_t AXI4S_ILA_configure_trigger
(
    axi4s_ila_instance_t *   this_axi4s_ila,
    uint32_t            trigger_cond,
    uint32_t            trigger_mask
)
{
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_TRIG_COND, trigger_cond);
    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_TRIG_MASK, trigger_mask);

    return CMD_STATUS_SUCCESS; // Trigger configuration successful
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_configure_trigger_data()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_configure_trigger_data
(
    axi4s_ila_instance_t *   this_axi4s_ila,
    uint64_t            trigger_data_cond,
    uint64_t            trigger_data_mask
)
{
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB, (uint32_t)(trigger_data_cond & 0xFFFFFFFF));
    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_TRIG_DATA_COND_LSB + 4, (uint32_t)((trigger_data_cond >> 32) & 0xFFFFFFFF));

    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB, (uint32_t)(trigger_data_mask & 0xFFFFFFFF));
    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_TRIG_DATA_MASK_LSB + 4, (uint32_t)((trigger_data_mask >> 32) & 0xFFFFFFFF));

    return CMD_STATUS_SUCCESS; // Trigger data configuration successful
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_arm()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_arm
(
    axi4s_ila_instance_t *   this_axi4s_ila
)
{
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    // Check if the ILA is already armed
    uint32_t ila_arm_status = HAL_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_STATUS, ARMED);

    if (ila_arm_status == 1)
    {
        return CMD_STATUS_ERROR; // ILA is already armed
    }

    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_ARM_FT, 0x1);

    return CMD_STATUS_SUCCESS; // ILA armed successfully
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_force_trigger()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_force_trigger
(
    axi4s_ila_instance_t *   this_axi4s_ila
)
{
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    // Check if the ILA is already armed
    uint32_t ila_arm_status = HAL_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_STATUS, ARMED);

    if (ila_arm_status == 0)
    {
        return CMD_STATUS_ERROR; // ILA is not armed, cannot force trigger
    }

    HAL_set_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_ARM_FT, 0x1);

    return CMD_STATUS_SUCCESS; // Force trigger send successfully
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_wait_done()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_wait_done
(
    axi4s_ila_instance_t *   this_axi4s_ila,
    uint32_t            timeout_ms
)
{
    uint64_t deadline;
    uint32_t ila_status;

    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // fail fast instead of busy-looping the full timeout
    }

    deadline = readmtime() + FPAD_MS_TO_TICKS(timeout_ms);

    do
    {

        ila_status = HAL_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_STATUS, DONE);
        if (ila_status == 1)
        {
            return CMD_STATUS_SUCCESS;
        }
        /* optional: a short pause here if you want to ease bus traffic/power */
    } while (readmtime() < deadline);

    return CMD_STATUS_TIMEOUT;
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_read_idx()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_read_idx
(
    axi4s_ila_instance_t *   this_axi4s_ila,
    uint32_t *          samp_buff_frst_idx,
    uint32_t *          samp_buff_trig_idx
)
{
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // fail fast instead of busy-looping the full timeout
    }
    * samp_buff_frst_idx = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX);
    * samp_buff_trig_idx = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX);
    
    return CMD_STATUS_SUCCESS;
}

/*-------------------------------------------------------------------------*//**
 * AXI4S_ILA_read_data()
 * See "core_axi4s_ila.h" for details of how to use this function.
 */
cmd_status_t AXI4S_ILA_read_data
(
    axi4s_ila_instance_t * this_axi4s_ila,
    uint64_t * data_buffer,
    uint8_t * signal_buffer,
    uint32_t * samp_buff_trig_idx
)
{
    uint32_t samp_buff_frst_idx;
    
    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // fail fast instead of busy-looping the full timeout
    }
    samp_buff_frst_idx = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_FRST_IDX);

    * samp_buff_trig_idx = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_TRIG_IDX);

    for( uint32_t i = 0; i < CORE_AXI4S_ILA_SAMP_BUFF_DEPTH; i++)
    {
        uint32_t idx = (samp_buff_frst_idx + i) % CORE_AXI4S_ILA_SAMP_BUFF_DEPTH;

        uint32_t lo = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_BASE + (idx * CORE_AXI4S_ILA_STRIDE_WIDTH));
        uint32_t hi = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_BASE + (idx * CORE_AXI4S_ILA_STRIDE_WIDTH) + 4);
        data_buffer[i] = ((uint64_t)hi << 32) | lo;

        signal_buffer[i] = HAL_get_32bit_reg(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_REGS_SAMP_BUFF_BASE + (idx * CORE_AXI4S_ILA_STRIDE_WIDTH) + 8);
    }
    
    return CMD_STATUS_SUCCESS;
}
