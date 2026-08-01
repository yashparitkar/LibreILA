/*******************************************************************************
 * @file hal.h
 * @brief Stub of the PolarFire SoC HAL's hal.h, host build only.
 *
 * Not Microchip's file, a reimplementation of the four macros the driver uses.
 * They are reproduced rather than copied so the test carries no vendor code,
 * but the contract has to match exactly, because the contract is the thing
 * under test:
 *
 *   HAL_get_32bit_reg(BASE, REG_NAME) pastes REG_NAME##_REG_OFFSET at
 *   preprocess time. That is why an offset that moves with the probe width
 *   cannot go through here at all, and why the driver puts the moving part in
 *   the base address instead. See the block comment in core_libre_ila_regs.h.
 *
 * The field variants paste three symbols, FIELD_NAME with _OFFSET, _SHIFT and
 * _MASK suffixes, where _MASK is already shifted into place.
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

#ifndef HAL_H
#define HAL_H

#include "cpu_types.h"
#include "hw_reg_access.h"

#define FIELD_OFFSET(FIELD_NAME)  (FIELD_NAME##_OFFSET)
#define FIELD_SHIFT(FIELD_NAME)   (FIELD_NAME##_SHIFT)
#define FIELD_MASK(FIELD_NAME)    (FIELD_NAME##_MASK)

#define HAL_set_32bit_reg(BASE_ADDR, REG_NAME, VALUE) \
          (HW_set_32bit_reg( ((BASE_ADDR) + (REG_NAME##_REG_OFFSET)), (VALUE) ))

#define HAL_get_32bit_reg(BASE_ADDR, REG_NAME) \
          (HW_get_32bit_reg( ((BASE_ADDR) + (REG_NAME##_REG_OFFSET)) ))

#define HAL_set_32bit_reg_field(BASE_ADDR, FIELD_NAME, VALUE) \
            (HW_set_32bit_reg_field(                          \
                (BASE_ADDR) + FIELD_OFFSET(FIELD_NAME),       \
                FIELD_SHIFT(FIELD_NAME),                      \
                FIELD_MASK(FIELD_NAME),                       \
                (VALUE)))

#define HAL_get_32bit_reg_field(BASE_ADDR, FIELD_NAME) \
            (HW_get_32bit_reg_field(                   \
                (BASE_ADDR) + FIELD_OFFSET(FIELD_NAME),\
                FIELD_SHIFT(FIELD_NAME),               \
                FIELD_MASK(FIELD_NAME)))

#endif /* HAL_H */
