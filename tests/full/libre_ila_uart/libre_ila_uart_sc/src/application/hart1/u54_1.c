/********************************************************************
 * File: u54_1.c
 * Author: Y.U.P. Paritkar (yashparitkar)
 * Created: 2026/05/26 19:16
 * Last Modified: 2026-08-10 Mon 22:47
 *
 * Description:
 *   Testing the libre_ila_uart, this code simply generates packet stream on
 *   the axi4s bus. This code is suitable for TDATA width of 64 bits. Please
 *   modify the code as necessary to accomodate for different TDATA widths.
 *   
 *   This codes gives TUI like interface on the UART terminal to select number
 *   of packets and frames to transfer. 
 ********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mpfs_hal/mss_hal.h"
#include "drivers/mss/mss_gpio/mss_gpio.h"
#include "drivers/mss/mss_mmuart/mss_uart.h"
#include "inc/uart_mapping.h"
#include "mpfs_hal/common/mss_sysreg.h"

#include "mpfs_hal/common/mss_peripherals.h"

// HAL_set_32bit_reg / HAL_get_32bit_reg used for direct AXI4S_PKTGEN register access
#include "hal/hal.h"

extern struct mss_uart_instance *p_uartmap_u54_1;

/* AXI4S_PKTGEN Defines*/
#define AXI4S_PKTGEN_BASE_ADDR (0x60020000u)       // AXILOOPBACK IP base address
#define AXI4S_PKTGEN_NUM_PKT_REG_OFFSET (0x00u)    // Offset to program the number of packets to transfer
#define AXI4S_PKTGEN_NUM_FRAME_REG_OFFSET (0x04u)  // Offset to program the number of frames to transfer
#define AXI4S_PKTGEN_CONFIG_REG_OFFSET (0x08u)     // [0]: enable TLAST. [31:16]: data density
#define AXI4S_PKTGEN_START_REG_OFFSET (0x0Cu)      // Offset to start the transfer with any write
#define AXI4S_PKTGEN_LSTFRAME_L_REG_OFFSET (0x10u) // Offset to read the last frame received in the current transfer
#define AXI4S_PKTGEN_LSTFRAME_H_REG_OFFSET (0x14u) // Offset to read the last frame received in the current transfer
#define AXI4S_PKTGEN_STATUS_REG_OFFSET (0x18u)     // Offset to read the status of the pktgen (1 means pktgen is empty, 0 means pktgen is not empty)

#define AXI4S_PKTGEN_CONFIG_TLAST_EN (0x1u)   // CONFIG[0]: TLAST enable bit
#define AXI4S_PKTGEN_CONFIG_DENSITY_SHIFT (16u) // CONFIG[31:16]: data density field

/*******************************************************************/

/* Global variables ************************************************/
// UART is taken from the bare-metal example
static volatile uint32_t uart_recieve_buffer_length = 0u;
static uint8_t uart_recieve_buffer[1u] = {0u};

#define NPKT_MIN (1u)
#define NPKT_MAX (256u)
#define NFRAMES_MIN (1u)
#define NFRAMES_MAX (256u)
#define DENSITY_MIN (0u)
#define DENSITY_MAX (65535u) // CONFIG[31:16] is a 16 bit field, 0 disables bubble insertion

static uint16_t txn_cnt = 0u;      // Transaction count
static uint32_t npkt_value = 1u;   // Selected number of packets to transfer
static uint32_t nframes_value = 1u; // Selected number of frames per packet to transfer
static uint32_t density_value = 0u; // Selected data density (0 disables bubble insertion)

static const char transfer_in_progress_options_mgs[] =
    "\r\n\
Select an action:\r\n\
0. Setup up transfer\r\n\
1. Start PKTGEN transfer\r\n\
2. Check last frame received in PKTGEN\r\n\
3. Check PKTGEN status\r\n\
4. Continue waiting\r\n";
/*******************************************************************/

/* Assisting function **********************************************/
void print_menu(bool clear_screen)
{
  char transfer_message[512] = {0u};
  sprintf(transfer_message,
"\r\n\r\n\r\n **** PolarFire SoC MSS LibreILA testing ****\r\n\r\n\
Current settings:\r\n\
  Number of packets: %.3u | Number of frames: %u | Density: %u\r\n",
  npkt_value,
  nframes_value,
  density_value
  );
  if (clear_screen)
  {
    MSS_UART_polled_tx_string(p_uartmap_u54_1, "\x1B[2J\x1B[H"); // clear the screen
  }
  MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);
}

/***************************************************************************//**
 * tui_read_number()
 *
 * Reads a decimal number typed at the UART terminal, TUI style: digits are
 * echoed back as they arrive, backspace/DEL erases the last digit, and Enter
 * submits the value. If the submitted value falls outside [min_val, max_val]
 * (or nothing was typed), an error is printed, the prompt is redisplayed, and
 * entry restarts - this repeats until a valid value is entered.
 *
 * This lets the caller take an arbitrary in-range value (e.g. npkt, nframes,
 * density) instead of being limited to a fixed menu of choices.
 *
 * prompt:   Message printed before (and after invalid input) reading digits.
 * min_val:  Smallest value accepted, inclusive.
 * max_val:  Largest value accepted, inclusive.
 * RETURN:   The accepted value, guaranteed to be within [min_val, max_val].
 */
static uint32_t tui_read_number(const char *prompt, uint32_t min_val, uint32_t max_val)
{
  char digits[11] = {0u}; // up to 10 digits (uint32_t max) + NUL terminator
  uint8_t digits_len = 0u;
  uint32_t value;
  char err_message[96];

  MSS_UART_polled_tx_string(p_uartmap_u54_1, prompt);

  while (1)
  {
    uart_recieve_buffer_length = MSS_UART_get_rx(p_uartmap_u54_1, uart_recieve_buffer, sizeof(uart_recieve_buffer));
    if (uart_recieve_buffer_length == 0u)
    {
      continue;
    }

    uint8_t c = uart_recieve_buffer[0];

    if ((c >= '0') && (c <= '9'))
    {
      if (digits_len < (sizeof(digits) - 1u))
      {
        digits[digits_len++] = (char)c;
        digits[digits_len] = '\0';
        MSS_UART_polled_tx(p_uartmap_u54_1, &c, 1u); // echo the digit
      }
    }
    else if ((c == 0x08u) || (c == 0x7Fu)) // backspace / DEL
    {
      if (digits_len > 0u)
      {
        digits_len--;
        digits[digits_len] = '\0';
        MSS_UART_polled_tx_string(p_uartmap_u54_1, "\b \b"); // erase char on terminal
      }
    }
    else if ((c == '\r') || (c == '\n'))
    {
      if (digits_len == 0u)
      {
        continue; // nothing typed yet, keep waiting
      }

      value = (uint32_t)strtoul(digits, NULL, 10);
      if ((value >= min_val) && (value <= max_val))
      {
        MSS_UART_polled_tx_string(p_uartmap_u54_1, "\r\n");
        return value;
      }

      sprintf(err_message, "\r\nInvalid value! Please enter a number between %u and %u\r\n", min_val, max_val);
      MSS_UART_polled_tx_string(p_uartmap_u54_1, err_message);
      digits_len = 0u;
      digits[0] = '\0';
      MSS_UART_polled_tx_string(p_uartmap_u54_1, prompt);
    }
    // Any other character is ignored
  }
}


// TODO: FIGURE OUT THIS FUNCTION
uint8_t PLIC_f2m_2_IRQHandler(void)
{
  // Not using IRQ for this demo
  return 0;
}
/*******************************************************************/

/******************************************************************************
 * Instruction message. These message will be displayed on the UART terminal
 when the program starts.
*****************************************************************************/
uint8_t g_message[] =
    "\r\n\r\n\r\n **** PolarFire SoC MSS LibreILA testing ****\r\n\r\n\r\n\
This program is running on u54_1.\r\n\r\n\
\r\n";

/* Main function for the hart1(U54 processor).
 * Application code running on hart1 is placed here.
 */

void u54_1(void)
{
  mss_disable_fabric();
  mss_enable_fabric();
  uint8_t cnt = 16U;

  /*
   * Clear pending software interrupt in case there was any.
   * Enable only the software interrupt so that the E51 core can bring this
   * core out of WFI by raising a software interrupt In case of external,
   * bootloader not present
   */

  clear_soft_interrupt();
  set_csr(mie, MIP_MSIP);

#if (IMAGE_LOADED_BY_BOOTLOADER == 0)

  /*Put this hart into WFI.*/

  do
  {
    __asm("wfi");
  } while (0 == (read_csr(mip) & MIP_MSIP));

  /* The hart is out of WFI, clear the SW interrupt. Hear onwards Application
   * can enable and use any interrupts as required */
  clear_soft_interrupt();
#endif

  mss_enable_fabric();
  PLIC_init();

  PLIC_SetPriority(FABRIC_F2H_2_PLIC, 2);
  PLIC_EnableIRQ(FABRIC_F2H_2_PLIC);

  __enable_irq();

  /* Reset the peripherals turn on the clocks */
  (void)mss_config_clk_rst(MSS_PERIPH_MMUART_U54_1, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_MMUART_U54_2, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_MMUART_U54_3, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_GPIO0, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_GPIO1, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_GPIO2, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_CFM, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);

  (void)mss_config_clk_rst(MSS_PERIPH_MMUART1, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_FIC0, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);
  (void)mss_config_clk_rst(MSS_PERIPH_FIC3, (uint8_t)MPFS_HAL_FIRST_HART, PERIPHERAL_ON);

  /* mmuart1 initialization */
  MSS_UART_init(p_uartmap_u54_1,
                MSS_UART_115200_BAUD,
                MSS_UART_DATA_8_BITS | MSS_UART_NO_PARITY | MSS_UART_ONE_STOP_BIT);

  MSS_UART_polled_tx_string(p_uartmap_u54_1, g_message);

  SysTick_Config();

  SYSREG->GPIO_INTERRUPT_FAB_CR = 0xFFFFFFFFUL;

  MSS_GPIO_init(GPIO2_LO);
  for (cnt = 16u; cnt < 20u; cnt++)
  {
    MSS_GPIO_config(GPIO2_LO,
                    cnt,
                    MSS_GPIO_OUTPUT_MODE);
  }

  MSS_GPIO_set_outputs(GPIO2_LO, 0u);

  /* Actual code to test the logic *********************************************/
  print_menu(true);
  MSS_UART_polled_tx_string(p_uartmap_u54_1, "\r\n Starting test ...\r\n");
  MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_in_progress_options_mgs);

  char transfer_message[128] = {0u};
  while (1)
  {
    uart_recieve_buffer_length = MSS_UART_get_rx(p_uartmap_u54_1, uart_recieve_buffer, sizeof(uart_recieve_buffer));

    if (uart_recieve_buffer_length > 0u)
    {
      uint32_t lstframe_h, lstframe_l, pktgen_status;
      switch (uart_recieve_buffer[0])
      {
      case '0':
        npkt_value = tui_read_number("\r\nEnter number of packets to transfer (1-256): ", NPKT_MIN, NPKT_MAX);
        sprintf(transfer_message, "\r\nYou have selected to transfer %u packets\r\n", npkt_value);
        MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);

        nframes_value = tui_read_number("\r\nEnter number of frames per packet (1-256): ", NFRAMES_MIN, NFRAMES_MAX);
        sprintf(transfer_message, "\r\nYou have selected to transfer %u frames per packet\r\n", nframes_value);
        MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);

        density_value = tui_read_number("\r\nEnter data density, 0 to disable bubble insertion (0-65535): ", DENSITY_MIN, DENSITY_MAX);
        sprintf(transfer_message, "\r\nYou have selected a data density of %u\r\n", density_value);
        MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);
        break;

      case '1':
        // Setup the PKTGEN IP
        HAL_set_32bit_reg(AXI4S_PKTGEN_BASE_ADDR, AXI4S_PKTGEN_NUM_PKT, npkt_value);
        mb();
        HAL_set_32bit_reg(AXI4S_PKTGEN_BASE_ADDR, AXI4S_PKTGEN_NUM_FRAME, nframes_value);
        mb();

        // CONFIG[0]: enable TLAST, CONFIG[31:16]: data density
        HAL_set_32bit_reg(AXI4S_PKTGEN_BASE_ADDR, AXI4S_PKTGEN_CONFIG,
                           (density_value << AXI4S_PKTGEN_CONFIG_DENSITY_SHIFT) | AXI4S_PKTGEN_CONFIG_TLAST_EN);
        mb();

        // Start the PKTGEN transfer
        HAL_set_32bit_reg(AXI4S_PKTGEN_BASE_ADDR, AXI4S_PKTGEN_START, 1);

        sprintf(transfer_message,
                "\r\n\rAXI4S_PKTGEN: Transfer Started\r\n"
                "> Transferring %-i packets, %-i frames, density %-i\r\n",
                *(volatile uint32_t *)(AXI4S_PKTGEN_BASE_ADDR + AXI4S_PKTGEN_NUM_PKT_REG_OFFSET),
                *(volatile uint32_t *)(AXI4S_PKTGEN_BASE_ADDR + AXI4S_PKTGEN_NUM_FRAME_REG_OFFSET),
                density_value);

        MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);
        txn_cnt++;
        break;

      case '2':
        lstframe_h = *(volatile uint32_t *)(AXI4S_PKTGEN_BASE_ADDR + AXI4S_PKTGEN_LSTFRAME_H_REG_OFFSET);
        lstframe_l = *(volatile uint32_t *)(AXI4S_PKTGEN_BASE_ADDR + AXI4S_PKTGEN_LSTFRAME_L_REG_OFFSET);

        sprintf(transfer_message, "\r\nLast frame received in PKTGEN:\r\n 0x%08X 0x%08X \r\n", lstframe_h, lstframe_l);
        MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);
        break;

      case '3':
        pktgen_status = *(volatile uint32_t *)(AXI4S_PKTGEN_BASE_ADDR + AXI4S_PKTGEN_STATUS_REG_OFFSET);
        sprintf(transfer_message, "\r\nPKTGEN status: 0x%08X (1: STATE_SEND 0: STATE_IDLE)\r\n", pktgen_status);
        MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_message);
        break;

      case '4':
        MSS_UART_polled_tx_string(p_uartmap_u54_1, "\r\nContinuing to wait...\r\n");
        break;

      default:
        // Do nothing
        MSS_UART_polled_tx_string(p_uartmap_u54_1, "\r\nInvalid selection! Please select a number between 0 and 4\r\n");
        break;
      }
      print_menu(false);
      MSS_UART_polled_tx_string(p_uartmap_u54_1, transfer_in_progress_options_mgs);
    }
  }
}

void SysTick_Handler_h1_IRQHandler(void)
{
  uint32_t hart_id = read_csr(mhartid);
  static volatile uint8_t value = 0u;

  if (1u == hart_id)
  {
    if (0u == value)
    {
      value = 0x01u;
    }
    else
    {
      value = 0x00u;
    }

    MSS_GPIO_set_output(GPIO2_LO, MSS_GPIO_17, value);
  }
}
