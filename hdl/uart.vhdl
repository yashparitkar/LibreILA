-------------------------------------------------------------------------------
-- File: uart.vhdl
-- Author: pabennett/uart; modified a bit by paritkary25
-- Last Modified: 2026/07/24 10:52
-------------------------------------------------------------------------------
-- Original work: pabennett/uart
-- Copyright 2015 Peter Bennett
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-------------------------------------------------------------------------------
-- UART
-- Implements a universal asynchronous receiver transmitter
-------------------------------------------------------------------------------
-- clock
--      Input clock, must match frequency value given on clock_frequency
--      generic input.
-- reset
--      Synchronous reset.
-- data_stream_in
--      Input data bus for bytes to transmit.
-- data_stream_in_stb
--      Input strobe to qualify the input data bus.
-- data_stream_in_ack
--      Output acknowledge to indicate the UART has begun sending the byte
--      provided on the data_stream_in port.
-- data_stream_out
--      Data output port for received bytes.
-- data_stream_out_stb
--      Output strobe to qualify the received byte. Will be valid for one clock
--      cycle only.
-- tx
--      Serial transmit.
-- rx
--      Serial receive
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity uart is
  generic (
    BAUD            : positive := 115200;
    CLOCK_FREQUENCY : positive := 100000000
  );
  port (
    clock               : in    std_logic;
    reset               : in    std_logic;
    data_stream_in      : in    std_logic_vector(7 downto 0);
    data_stream_in_stb  : in    std_logic;
    data_stream_in_ack  : out   std_logic;
    data_stream_out     : out   std_logic_vector(7 downto 0);
    data_stream_out_stb : out   std_logic;
    tx                  : out   std_logic;
    rx                  : in    std_logic
  );
end entity uart;

architecture rtl of uart is

  ---------------------------------------------------------------------------
  -- Baud generation constants
  ---------------------------------------------------------------------------
  constant C_TX_DIV       : integer := CLOCK_FREQUENCY / BAUD;
  constant C_RX_DIV       : integer := CLOCK_FREQUENCY / (BAUD * 16);
  constant C_TX_DIV_WIDTH : integer := integer(log2(real(C_TX_DIV))) + 1;
  constant C_RX_DIV_WIDTH : integer := integer(log2(real(C_RX_DIV))) + 1;
  ---------------------------------------------------------------------------
  -- Baud generation signals
  ---------------------------------------------------------------------------
  signal tx_baud_counter : unsigned(C_TX_DIV_WIDTH - 1 downto 0);
  signal tx_baud_tick    : std_logic;
  signal rx_baud_counter : unsigned(C_RX_DIV_WIDTH - 1 downto 0);
  signal rx_baud_tick    : std_logic;
  ---------------------------------------------------------------------------
  -- Transmitter signals
  ---------------------------------------------------------------------------

  constant TX_SEND_START_BIT : std_logic_vector(1 downto 0) := "00";
  constant TX_SEND_DATA      : std_logic_vector(1 downto 0) := "01";
  constant TX_SEND_STOP_BIT  : std_logic_vector(1 downto 0) := "10";

  signal uart_tx_state       : std_logic_vector(1 downto 0);
  signal uart_tx_data_vec    : std_logic_vector(7 downto 0);
  signal uart_tx_data        : std_logic;
  signal uart_tx_count       : unsigned(2 downto 0);
  signal uart_tx_data_in_ack : std_logic;
  ---------------------------------------------------------------------------
  -- Receiver signals
  ---------------------------------------------------------------------------
  constant RX_GET_START_BIT : std_logic_vector(1 downto 0) := "00";
  constant RX_GET_DATA      : std_logic_vector(1 downto 0) := "01";
  constant RX_GET_STOP_BIT  : std_logic_vector(1 downto 0) := "10";

  signal uart_rx_state        : std_logic_vector(1 downto 0);
  signal uart_rx_bit          : std_logic;
  signal uart_rx_data_vec     : std_logic_vector(7 downto 0);
  signal uart_rx_data_sr      : std_logic_vector(1 downto 0);
  signal uart_rx_filter       : unsigned(1 downto 0);
  signal uart_rx_count        : unsigned(2 downto 0);
  signal uart_rx_data_out_stb : std_logic;
  signal uart_rx_bit_spacing  : unsigned (3 downto 0);
  signal uart_rx_bit_tick     : std_logic;
  signal uart_rx_start_filter : unsigned(1 downto 0);

begin

  -- INPUT CHECKING ---------------------------------------------------------
  assert ((BAUD * 16) <= CLOCK_FREQUENCY)
    report "CLOCK should be greater than 16 * BAUD"
    severity failure;
  ---------------------------------------------------------------------------

  -- Connect IO
  data_stream_in_ack  <= uart_tx_data_in_ack;
  data_stream_out     <= uart_rx_data_vec;
  data_stream_out_stb <= uart_rx_data_out_stb;
  tx                  <= uart_tx_data;
  ---------------------------------------------------------------------------
  -- OVERSAMPLE_CLOCK_DIVIDER
  -- generate an oversampled tick (baud * 16)
  ---------------------------------------------------------------------------
  oversample_clock_divider : process (clock) is
  begin

    if (rising_edge (clock)) then
      if (reset = '1') then
        rx_baud_counter <= (others => '0');
        rx_baud_tick    <= '0';
      else
        if (rx_baud_counter = C_RX_DIV - 1) then
          rx_baud_counter <= (others => '0');
          rx_baud_tick    <= '1';
        else
          rx_baud_counter <= rx_baud_counter + 1;
          rx_baud_tick    <= '0';
        end if;
      end if;
    end if;

  end process oversample_clock_divider;

  ---------------------------------------------------------------------------
  -- RXD_SYNCHRONISE
  -- Synchronise rxd to the local clock domain
  ---------------------------------------------------------------------------
  rxd_synchronise : process (clock) is
  begin

    if rising_edge(clock) then
      if (reset = '1') then
        uart_rx_data_sr <= (others => '1');
      else
        uart_rx_data_sr(0) <= rx;
        uart_rx_data_sr(1) <= uart_rx_data_sr(0);
      end if;
    end if;

  end process rxd_synchronise;

  ---------------------------------------------------------------------------
  -- RXD_FILTER
  -- Filter rxd with a 2 bit counter.
  ---------------------------------------------------------------------------
  rxd_filter : process (clock) is
  begin

    if rising_edge(clock) then
      if (reset = '1') then
        uart_rx_filter <= (others => '1');
        uart_rx_bit    <= '1';
      else
        if (rx_baud_tick = '1') then
          -- filter rxd.
          if (uart_rx_data_sr(1) = '1' and uart_rx_filter < 3) then
            uart_rx_filter <= uart_rx_filter + 1;
          elsif (uart_rx_data_sr(1) = '0' and uart_rx_filter > 0) then
            uart_rx_filter <= uart_rx_filter - 1;
          end if;
          -- set the rx bit.
          if (uart_rx_filter = 3) then
            uart_rx_bit <= '1';
          elsif (uart_rx_filter = 0) then
            uart_rx_bit <= '0';
          end if;
        end if;
      end if;
    end if;

  end process rxd_filter;

  ---------------------------------------------------------------------------
  -- RX_BIT_SPACING
  ---------------------------------------------------------------------------
  rx_bit_spacing : process (clock) is
  begin

    if rising_edge(clock) then
      uart_rx_bit_tick <= '0';
      if (rx_baud_tick = '1') then
        if (uart_rx_bit_spacing = 15) then
          uart_rx_bit_tick    <= '1';
          uart_rx_bit_spacing <= (others => '0');
        else
          uart_rx_bit_spacing <= uart_rx_bit_spacing + 1;
        end if;
        if (uart_rx_state = RX_GET_START_BIT) then
          uart_rx_bit_spacing <= (others => '0');
        end if;
      end if;
    end if;

  end process rx_bit_spacing;

  ---------------------------------------------------------------------------
  -- UART_RECEIVE_DATA
  ---------------------------------------------------------------------------
  uart_receive_data : process (clock) is
  begin

    if rising_edge(clock) then
      if (reset = '1') then
        uart_rx_state        <= RX_GET_START_BIT;
        uart_rx_data_vec     <= (others => '0');
        uart_rx_count        <= (others => '0');
        uart_rx_data_out_stb <= '0';
        uart_rx_start_filter <= (others => '0');
      else
        uart_rx_data_out_stb <= '0';

        case uart_rx_state is

          when RX_GET_START_BIT =>

            if (rx_baud_tick = '1') then
              if (uart_rx_bit = '0') then
                if (uart_rx_start_filter < 3) then
                  uart_rx_start_filter <= uart_rx_start_filter + 1;
                else
                  -- 4 consecutive low samples confirmed: transition to RX_GET_DATA
                  uart_rx_state        <= RX_GET_DATA;
                  uart_rx_start_filter <= (others => '0');
                end if;
              else
                -- Reset counter on any '1' sample to prevent noise accumulation
                uart_rx_start_filter <= (others => '0');
              end if;
            end if;

          when RX_GET_DATA =>

            if (uart_rx_bit_tick = '1') then
              uart_rx_data_vec(uart_rx_data_vec'high)
                <= uart_rx_bit;
              uart_rx_data_vec(
              uart_rx_data_vec'high - 1 downto 0
              ) <= uart_rx_data_vec(
                                    uart_rx_data_vec'high downto 1
                                  );
              if (uart_rx_count < 7) then
                uart_rx_count <= uart_rx_count + 1;
              else
                uart_rx_count <= (others => '0');
                uart_rx_state <= RX_GET_STOP_BIT;
              end if;
            end if;

          when RX_GET_STOP_BIT =>

            if (uart_rx_bit_tick = '1') then
              uart_rx_state <= RX_GET_START_BIT;
              if (uart_rx_bit = '1') then
                uart_rx_data_out_stb <= '1';
              end if;
            end if;

          when others =>

            uart_rx_state <= RX_GET_START_BIT;

        end case;

      end if;
    end if;

  end process uart_receive_data;

  ---------------------------------------------------------------------------
  -- TX_CLOCK_DIVIDER
  -- Generate baud ticks at the required rate based on the input clock
  -- frequency and baud rate
  ---------------------------------------------------------------------------
  tx_clock_divider : process (clock) is
  begin

    if (rising_edge (clock)) then
      if (reset = '1') then
        tx_baud_counter <= (others => '0');
        tx_baud_tick    <= '0';
      else
        if (tx_baud_counter = C_TX_DIV - 1) then
          tx_baud_counter <= (others => '0');
          tx_baud_tick    <= '1';
        else
          tx_baud_counter <= tx_baud_counter + 1;
          tx_baud_tick    <= '0';
        end if;
      end if;
    end if;

  end process tx_clock_divider;

  ---------------------------------------------------------------------------
  -- UART_SEND_DATA
  -- Get data from data_stream_in and send it one bit at a time upon each
  -- baud tick. Send data lsb first.
  -- wait 1 tick, send start bit (0), send data 0-7, send stop bit (1)
  ---------------------------------------------------------------------------
  uart_send_data : process (clock) is
  begin

    if rising_edge(clock) then
      if (reset = '1') then
        uart_tx_data        <= '1';
        uart_tx_data_vec    <= (others => '0');
        uart_tx_count       <= (others => '0');
        uart_tx_state       <= TX_SEND_START_BIT;
        uart_tx_data_in_ack <= '0';
      else
        uart_tx_data_in_ack <= '0';

        case uart_tx_state is

          when TX_SEND_START_BIT =>

            if (tx_baud_tick = '1' and data_stream_in_stb = '1') then
              uart_tx_data        <= '0';
              uart_tx_state       <= TX_SEND_DATA;
              uart_tx_count       <= (others => '0');
              uart_tx_data_in_ack <= '1';
              uart_tx_data_vec    <= data_stream_in;
            end if;

          when TX_SEND_DATA =>

            if (tx_baud_tick = '1') then
              uart_tx_data <= uart_tx_data_vec(0);
              uart_tx_data_vec(
              uart_tx_data_vec'high - 1 downto 0
              )            <= uart_tx_data_vec(
                                               uart_tx_data_vec'high downto 1
                                             );
              if (uart_tx_count < 7) then
                uart_tx_count <= uart_tx_count + 1;
              else
                uart_tx_count <= (others => '0');
                uart_tx_state <= TX_SEND_STOP_BIT;
              end if;
            end if;

          when TX_SEND_STOP_BIT =>

            if (tx_baud_tick = '1') then
              uart_tx_data  <= '1';
              uart_tx_state <= TX_SEND_START_BIT;
            end if;

          when others =>

            uart_tx_data  <= '1';
            uart_tx_state <= TX_SEND_START_BIT;

        end case;

      end if;
    end if;

  end process uart_send_data;

end architecture rtl;
