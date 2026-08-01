/*******************************************************************************
 * @file mss_hal.h
 * @brief Stub of the PolarFire SoC MSS HAL, host build only.
 *
 * core_libre_ila.c pulls this in for readmtime(), which it uses to build the
 * deadline in LIBRE_ILA_wait_done(). The stub ticks once per call so a poll
 * loop actually reaches its deadline instead of spinning forever, and
 * fake_mtime_reset() puts it back for the next test.
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

#ifndef MPFS_HAL_H_
#define MPFS_HAL_H_

#include <stdint.h>
#include <stddef.h>

uint64_t readmtime(void);
void     fake_mtime_reset(void);

#endif /* MPFS_HAL_H_ */
