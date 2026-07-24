/*******************************************************************************
 * @file core_axi4s_ila.h
 * @author Y.U.P. (paritkary25)
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
    CMD_STATUS_BAD_MAGIC_KEY = -2,   /**< Command failed due to a bad MAGIC_KEY read from the CoreAXI4S_ILA hardware instance. */
    CMD_STATUS_BAD_CONFIG = -3,   /**< Command failed due to defined  configuration no matching hardware. eg, invalid buffer depth or data width */
    CMD_STATUS_BAD_CLK_FREQ = -4,   /**< Command failed due defined clock frequency does not match hardware */
    CMD_STATUS_TIMEOUT = 1,   /**< Command timed out before completion. */
    CMD_STATUS_ERROR   = 2    /**< Command completed with an error. */
} cmd_status_t;

/*-------------------------------------------------------------------------*//** Enum for the hardware state reported by AXI4S_ILA_check_status(). Encodes two
 * independent bits (ready/busy, overflow/no overflow) as one named state,
 * rather than a bare 0-3 int8_t. */
typedef enum __axi4s_ila_status_t
{
    AXI4S_ILA_STATUS_BAD_AXI4S_ILA = -1,   /**< this_axi4s_ila is NULL. */
    AXI4S_ILA_STATUS_IDLE          =  0,   /**< ILA is idle */
    AXI4S_ILA_STATUS_ARMED         =  1,   /**< ILA is armed */
    AXI4S_ILA_STATUS_TRIGGERED     =  2,   /**< ILA is triggered */
    AXI4S_ILA_STATUS_DONE          =  3    /**< ILA acquisition complete */
} axi4s_ila_status_t;

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

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_get_status() function retrieves the current status of the CoreAXI4S_ILA hardware instance. This is done by reading the STATUS register of the CoreAXI4S_ILA hardware instance and interpreting the bits to determine the current state of the ILA.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @return
    ila_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
ila_status_t AXI4S_ILA_get_status
(
    axi4s_ila_instance_t * this_axi4s_ila
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_configure_trigger() function configures the trigger settings for the CoreAXI4S_ILA hardware instance. This is done by writing to the TRIG_COND and TRIG_MASK registers of the CoreAXI4S_ILA hardware instance.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @param trigger_cond
    The trigger_cond parameter is the value to be written to the TRIG_COND register of the CoreAXI4S_ILA hardware instance. This value defines the conditions under which the ILA will be triggered.

  @param trigger_mask
    The trigger_mask parameter is the value to be written to the TRIG_MASK register of the CoreAXI4S_ILA hardware instance. This value defines the mask for the trigger conditions.

  @return
    cmd_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_configure_trigger
(
    axi4s_ila_instance_t * this_axi4s_ila,
    uint32_t trigger_cond,
    uint32_t trigger_mask
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_configure_trigger_data() function configures the trigger settings for the CoreAXI4S_ILA hardware instance. This is done by writing to the TRIG_COND and TRIG_MASK registers of the CoreAXI4S_ILA hardware instance.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @param trigger_cond
    The trigger_cond parameter is the value to be written to the TRIG_DATA_COND register(s) of the CoreAXI4S_ILA hardware instance. This value defines the data value at which the ILA will trigger if the corresponding bits in the trigger_mask are set and ILA is in data trigger mode.

  @param trigger_mask
    The trigger_mask parameter is the value to be written to the TRIG_DATA_MASK register(s) of the CoreAXI4S_ILA hardware instance. This value defines the mask for the trigger data conditions. Only the bits set in this mask will be considered when evaluating the trigger condition against the trigger data.

  @return
    cmd_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_configure_trigger_data
(
    axi4s_ila_instance_t * this_axi4s_ila,
    uint64_t trigger_data_cond,
    uint64_t trigger_data_mask
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_arm() function arms the CoreAXI4S_ILA hardware instance. This is done by writing to the ARM_FT register of the CoreAXI4S_ILA hardware instance. Once armed, the ILA will start monitoring for the configured trigger conditions.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @return
    cmd_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_arm
(
    axi4s_ila_instance_t * this_axi4s_ila
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_force_trigger() function forces a trigger event on the CoreAXI4S_ILA hardware instance. This is done by writing to the ARM_FT register of the CoreAXI4S_ILA hardware instance. If the ILA is already armed, this will cause it to immediately trigger and start capturing data.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @return
    cmd_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_force_trigger
(
    axi4s_ila_instance_t * this_axi4s_ila
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_wait_done() function polls the STATUS register of the CoreAXI4S_ILA hardware instance until the ILA has completed its data capture operation or until a specified timeout period has elapsed. This function is useful for synchronizing with the ILA's operation in a blocking manner.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @param timeout_ms
    The timeout_ms parameter specifies the maximum time in milliseconds to wait for the ILA to complete its operation. If the ILA does not complete within this time, the function will return a timeout status.

  @return
    cmd_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_wait_done
(
    axi4s_ila_instance_t * this_axi4s_ila,
    uint32_t timeout_ms
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_read_idx() function reads the indices of the sample buffer where the trigger event occurred and where the first sample was captured. This is done by reading the SAMP_BUFF_TRIG_IDX and SAMP_BUFF_FRST_IDX registers of the CoreAXI4S_ILA hardware instance.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @param samp_buff_frst_idx
    Pointer to a uint32_t variable where the index of the first sample in the sample buffer will be stored.

  @param samp_buff_trig_idx
    Pointer to a uint32_t variable where the index of the sample in the sample buffer where the trigger event occurred will be stored.

  @return
    cmd_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_read_idx
(
    axi4s_ila_instance_t * this_axi4s_ila,
    uint32_t * samp_buff_frst_idx,
    uint32_t * samp_buff_trig_idx
);

/*-------------------------------------------------------------------------*//**
The AXI4S_ILA_read_data() function reads the data from the sample buffer where the trigger event occurred and where the first sample was captured. This function stores the values in the provided data buffer and the signal buffer. This is done with increasing time index, starting from the first sample index, and wrapping around the sample buffer if necessary till all the samples are read. The funciton uses the SAMP_BUFF_TRIG_IDX and SAMP_BUFF_FRST_IDX registers of the CoreAXI4S_ILA hardware instance to determine the indices of the samples to read.

The function separates the data and signal bits from the sample buffer and stores them in the provided buffers. The data buffer will contain the captured data values, while the signal buffer will contain the corresponding signal values.

  @param this_axi4s_ila
    Pointer to the axi4s_ila_instance_t to operate on.

  @param data_buffer
    Pointer to a uint64_t array where the captured data values will be stored. The size of the array should be at least equal to the sample buffer depth defined in the CoreAXI4S_ILA hardware instance.

  @param signal_buffer
    Pointer to a uint8_t array where the corresponding signal values will be stored. The size of the array should be at least equal to the sample buffer depth defined in the CoreAXI4S_ILA hardware instance.

  @param samp_buff_trig_idx
    Pointer to a uint32_t variable where the index of the sample in the sample buffer where the trigger event occurred will be stored.

  @return
    ila_status_t, see enum __axi4s_ila_status_t for details of the return values.
  */
cmd_status_t AXI4S_ILA_read_data
(
    axi4s_ila_instance_t * this_axi4s_ila,
    uint64_t * data_buffer,
    uint8_t * signal_buffer,
    uint32_t * samp_buff_trig_idx
);

#ifdef __cplusplus
}
#endif

#endif /* CORE_AXI4S_ILA_H_ */
