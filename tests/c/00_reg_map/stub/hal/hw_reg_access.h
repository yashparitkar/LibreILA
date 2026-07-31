/*******************************************************************************
 * @file hw_reg_access.h
 * @brief Stub of the PolarFire SoC HAL's hw_reg_access.h, host build only.
 *
 * On the target these are assembly routines doing volatile accesses to the
 * peripheral bus. Here they are backed by a flat array, see fake_regs.c. Note
 * that these take a plain address rather than a pasted register name, which is
 * why the two blocks whose address depends on the probe width go through these
 * and not through the HAL_* macros.
 */

#ifndef HW_REG_ACCESS_H
#define HW_REG_ACCESS_H

#include "cpu_types.h"

void     HW_set_32bit_reg(addr_t reg_addr, uint32_t value);
uint32_t HW_get_32bit_reg(addr_t reg_addr);

void     HW_set_32bit_reg_field(addr_t reg_addr, int8_t shift,
                                uint32_t mask, uint32_t value);
uint32_t HW_get_32bit_reg_field(addr_t reg_addr, int8_t shift, uint32_t mask);

#endif /* HW_REG_ACCESS_H */
