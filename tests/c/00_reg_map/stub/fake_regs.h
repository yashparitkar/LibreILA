/*******************************************************************************
 * @file fake_regs.h
 * @brief The stand-in register file the host build of the driver talks to.
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

#ifndef FAKE_REGS_H
#define FAKE_REGS_H

#include <stdint.h>

/* Enough for the widest core the test stages: a 512 bit probe is a stride of
 * 16, so 44 control registers plus 16 per sample. */
#define FAKE_REG_COUNT  (8192u)

extern uint32_t fake_reg[FAKE_REG_COUNT];

void fake_regs_clear(void);

#endif /* FAKE_REGS_H */
