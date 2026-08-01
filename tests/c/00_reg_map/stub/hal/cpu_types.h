/*******************************************************************************
 * @file cpu_types.h
 * @brief Stub of the PolarFire SoC HAL's cpu_types.h, host build only.
 *
 * Not Microchip's file. It declares the handful of types core_libre_ila.c
 * actually uses, so the driver can be compiled and exercised with an ordinary
 * host compiler. addr_t is what every HAL register accessor takes, and on the
 * target it is wide enough for the MSS memory map; here it only has to hold an
 * index into the fake register array in fake_regs.c.
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

#ifndef CPU_TYPES_H
#define CPU_TYPES_H

#include <stdint.h>
#include <stddef.h>

typedef uintptr_t addr_t;
typedef uint64_t  psr_t;

#endif /* CPU_TYPES_H */
