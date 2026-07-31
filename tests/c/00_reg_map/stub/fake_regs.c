/*******************************************************************************
 * @file fake_regs.c
 * @brief A flat array standing in for the core's AXI4Lite register file.
 *
 * The driver reaches the hardware only through HW_*_reg(), so backing those
 * four with an array is enough to run it on the host. Every address the driver
 * computes lands in fake_reg[], which the test then reads directly, so what is
 * being checked is where the driver decided to put things rather than whether
 * it agrees with itself.
 *
 * Addresses are byte addresses from a base of zero, which is what the test
 * passes to LIBRE_ILA_init(), so register n is fake_reg[n].
 */

#include <string.h>

#include "hal/cpu_types.h"
#include "mpfs_hal/mss_hal.h"
#include "fake_regs.h"

uint32_t fake_reg[FAKE_REG_COUNT];

static uint64_t fake_mtime;

void fake_regs_clear(void)
{
    memset(fake_reg, 0, sizeof(fake_reg));
    fake_mtime_reset();
}

/* One tick per call, so a LIBRE_ILA_wait_done() that is never going to see
 * DONE runs out of deadline instead of hanging the test */
uint64_t readmtime(void)
{
    return fake_mtime++;
}

void fake_mtime_reset(void)
{
    fake_mtime = 0u;
}

void HW_set_32bit_reg(addr_t reg_addr, uint32_t value)
{
    fake_reg[reg_addr / 4u] = value;
}

uint32_t HW_get_32bit_reg(addr_t reg_addr)
{
    return fake_reg[reg_addr / 4u];
}

void HW_set_32bit_reg_field(addr_t reg_addr, int8_t shift,
                            uint32_t mask, uint32_t value)
{
    uint32_t word = HW_get_32bit_reg(reg_addr);

    word = (word & ~mask) | ((value << shift) & mask);

    HW_set_32bit_reg(reg_addr, word);
}

uint32_t HW_get_32bit_reg_field(addr_t reg_addr, int8_t shift, uint32_t mask)
{
    return (HW_get_32bit_reg(reg_addr) & mask) >> shift;
}
