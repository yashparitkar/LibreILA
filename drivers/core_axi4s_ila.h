/*******************************************************************************
 * @file core_axi4s_ila.h
 * @author Y.U.P.
 * @brief Core AXI4S_ILA bare metal driver public API.
 */

/*=========================================================================*//**
  @mainpage CoreAXI4S_ILA Bare Metal Driver.

  @section intro_sec Introduction
  
  @section driver_configuration Driver Configuration
  
  @section theory_op Theory of Operation
  
 *//*=========================================================================*/
#ifndef CORE_AXI4S_ILA_H_
#define CORE_AXI4S_ILA_H_

#ifndef LEGACY_DIR_STRUCTURE
#include "hal/hal.h"

#else
#include "hal.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif


/*-------------------------------------------------------------------------*//** Enum for the status of a command sent to the CoreAXI4S_ILA hardware instance. */
typedef enum __cmd_status_t
{
    CMD_STATUS_SUCCESS = 0,   /**< Command completed successfully. */
    CMD_STATUS_BAD_AXI4S_ILA = -1,   /**< Command failed due to a bad AXI4S_ILA instance. */
    CMD_STATUS_BAD_DATA_POINTER = -2,   /**< Command failed due to bad input data. eg, null pointer */
    CMD_STATUS_BAD_MAGIC_KEY = -3,   /**< Command failed due to a bad MAGIC_KEY read from the CoreAXI4S_ILA hardware instance. */
    CMD_STATUS_BAD_DATA_LENGTH = -4,   /**< Command failed due to bad data length. eg, nframes = 0 */
    CMD_STATUS_TIMEOUT = 1,   /**< Command timed out before completion. */
    CMD_STATUS_ERROR   = 2    /**< Command completed with an error. */
} cmd_status_t;

/*-------------------------------------------------------------------------*//** Enum for the hardware state reported by AXI4S_ILA_check_status(). Encodes two
 * independent bits (ready/busy, overflow/no overflow) as one named state,
 * rather than a bare 0-3 int8_t. */
typedef enum __fpad_status_t
{
    AXI4S_ILA_STATUS_BAD_AXI4S_ILA = -1,   /**< this_axi4s_ila is NULL. */
    AXI4S_ILA_STATUS_IDLE          =  0,   /**< ILA is idle */
    AXI4S_ILA_STATUS_ARMED         =  1,   /**< ILA is armed */
    AXI4S_ILA_STATUS_TRIGGERED     =  2,   /**< ILA is triggered */
    AXI4S_ILA_STATUS_DONE          =  3    /**< ILA acquisition complete */
} fpad_status_t;

/*-------------------------------------------------------------------------*//** Structure instance holding all data regarding the CoreAXI4S_ILA
 */
typedef struct __axi4s_ila_instance_t
{
    addr_t              base_addr; // base addr of AXI4S_ILA AXI4L

} axi4s_ila_instance_t;

/*
 * Field Name: MAGIC_KEY
 * Field Desc: MAGIC_KEY to verify the AXI4Lite connection
 */
#define MAGIC_KEY               0xb01dface

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_init() function initializes the CoreAXI4S_ILA driver instance with thte base address of the CoreAXI4S_ILA hardware instance and the function pointers to send through PCDMA.

The init function checks the connection to the hardware by reading the MAGIC_KEY register, if the read value does not match the expected MAGIC_KEY value, the function returns failure status.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t data structure instance holding all data
    regarding the CoreAXI4S_ILA hardware instance being initialized. A pointer to the   same data structure is used in subsequent calls to the CoreAXI4S_ILA driver
    functions in order to identify the CoreAXI4S_ILA instance that must perform the
    operation implemented by the called driver function.

  @param base_addr
    The base_addr parameter is the base address in the memory map of the
    processor for the AXI4Lite registers of the core AXI4S_ILA instance being initialized.

  @return
    cmd_status_t, see enum __cmd_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_init
(
    axi4s_ila_instance_t * this_axi4s_ila,
    addr_t            base_addr,
);


#ifdef __cplusplus
}
#endif

#endif /* CORE_AXI4S_ILA_H_ */
