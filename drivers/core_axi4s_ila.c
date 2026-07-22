/*******************************************************************************
 * @file core_axi4s_ila.c
 * @author Y.U.P.
 * @brief CoreAXI4S_ILA bare metal driver implementation.
 *
 * Functions:
 *   cmd_status_t AXI4S_ILA_init( axi4s_ila_instance_t * this_axi4s_ila, addr_t base_addr);
 *   axi4s_ila_status_t AXI4S_ILA_get_status( axi4s_ila_instance_t * this_axi4s_ila, addr_t base_addr);
 * 
 *   cmd_status_t AXI4S_ILA_configure_trigger( axi4s_ila_instance_t * this_axi4s_ila, uint32_t trigger_cond, uint32_t trigger_mask);
 *   cmd_status_t AXI4S_ILA_configure_trigger_data( axi4s_ila_instance_t * this_axi4s_ila, uint32_t trigger_data_cond, uint32_t trigger_data_mask); 
 * 
 *   cmd_status_t AXI4S_ILA_arm ( axi4s_ila_instance_t * this_axi4s_ila);
 *   cmd_status_t AXI4S_ILA_force_trigger ( axi4s_ila_instance_t * this_axi4s_ila);
 * 
 *   cmd_status_t AXI4S_ILA_wait_done( axi4s_ila_instance_t * this_axi4s_ila, uint32_t timeout_ms);
 * 
 *   cmd_status_t AXI4S_ILA_read_idx( axi4s_ila_instance_t * this_axi4s_ila, uint32_t * samp_buff_frst_idx, uint32_t * samp_buff_trig_idx);
 *   cmd_status_t AXI4S_ILA_read_data( axi4s_ila_instance_t * this_axi4s_ila, uint64_t * data_buffer, uint8_t * signal_buffer, uint32_t  * samp_buff_trig_idx, uint32_t * samp_buff_frst_idx);
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

    mgckey_value = HW_get_32bit_reg(this_axi4s_ila->base_addr + CORE_AXI4S_ILA_REGS_MGCKEY_REG_OFFSET);

    if (mgckey_value != MAGIC_KEY)
    {
        return CMD_STATUS_BAD_MAGIC_KEY; // Connection failed, return failure status
    }

    buffer_depth_value = HW_get_32bit_reg(this_axi4s_ila->base_addr + CORE_AXI4S_ILA_REGS_DEPTH_REG_OFFSET);

    if (buffer_depth_value != CORE_AXI4S_ILA_SAMP_BUFF_DEPTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    data_width_value = HW_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_WIDTH_REG_DATA_WIDTH);

    if (data_width_value != CORE_AXI4S_ILA_DATA_WIDTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    signal_width_value = HW_get_32bit_reg_field(this_axi4s_ila->base_addr, CORE_AXI4S_ILA_WIDTH_REG_SIGNAL_WIDTH);

    if (signal_width_value != CORE_AXI4S_ILA_SIGNAL_WIDTH)
    {
        return CMD_STATUS_BAD_CONFIG; // Connection failed, return failure status
    }

    samp_clk_freq_value = HW_get_32bit_reg(this_axi4s_ila->base_addr + CORE_AXI4S_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET);

    if (samp_clk_freq_value != CORE_AXI4S_ILA_SAMP_FREQ_HZ)
    {
        return CMD_STATUS_BAD_CLK_FREQ; // Connection failed, return failure status
    }

    return CMD_STATUS_SUCCESS; // Connection successful, return success status
}
