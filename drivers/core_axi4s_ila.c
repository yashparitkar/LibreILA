/*******************************************************************************
 * @file core_axi4s_ila.c
 * @author Y.U.P.
 * @brief CoreAXI4S_ILA bare metal driver implementation.
 *
 * Functions:
 *   cmd_status_t AXI4S_ILA_init( axi4s_ila_instance_t * this_axi4s_ila, addr_t base_addr);
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
    uint32_t mgckey_value;

    if (this_axi4s_ila == NULL)
    {
        return CMD_STATUS_BAD_AXI4S_ILA; // Bad AXI4S_ILA instance
    }

    mgckey_value = HW_get_32bit_reg(this_axi4s_ila->base_addr + COREAXI4S_ILA_REGS_MGCKEY_BYTE_OFFSET(nFP));

    if (mgckey_value != MAGIC_KEY)
    {
        return CMD_STATUS_BAD_MAGIC_KEY; // Connection failed, return failure status
    }
    return CMD_STATUS_SUCCESS; // Connection successful, return success status
}
