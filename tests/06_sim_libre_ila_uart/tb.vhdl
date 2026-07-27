---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Description: Test the LibreILA UART wrapper end to end -- configure
--   the trigger over UART, stream AXI4S stimulus into the probe port
--   (same pattern as 01_sim_axil_trig), arm over UART, and read the
--   status/sample buffer back over UART.
--
-- The "PC" side of the link is modeled with a second instance of the
-- same uart.vhdl core, cross-wired to the DUT's uart_rx/uart_tx pins,
-- so byte-level TX/RX timing is handled by the (already validated)
-- UART core rather than hand-rolled bit-banging. A small FIFO buffers
-- bytes received from the DUT so the echoed response header (which the
-- wrapper starts sending as soon as it has the address, i.e. possibly
-- while this testbench is still clocking out write-data bytes) is
-- never dropped.
---------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library std;
  use std.env.all;

entity tb is
end entity tb;

architecture sim of tb is

  constant C_DATA_WIDTH    : natural := 64;
  constant C_DEPTH         : natural := 8;
  constant C_AXIS_PERIOD   : time    := 10 ns;
  constant C_AXIL_PERIOD   : time    := 10 ns;
  constant C_AXIL_CLK_FREQ : integer := 100_000_000;
  -- Standard RS232 baud rate.
  constant C_BAUD_RATE     : integer := 230_400;

  constant C_TRIG_IDX      : natural := 3;
  constant C_TRIGGER_POINT : natural := 80;
  constant C_SAMPLE_COUNT  : natural := 192;

  constant C_AXIL_WORD_BYTES : natural := 4;
  -- Matches the DUT's C_AXIL_STRIDE (see hdl/libre_ila.vhdl): next
  -- power-of-two register count for (TDATA lanes + 1 control lane).
  constant C_STRIDE          : natural := 2 ** integer(ceil(log2(real(C_DATA_WIDTH / 32 + 1))));
  constant C_INPUT_REG_COUNT : natural := 4 + 2 * C_STRIDE;
  constant C_OUTPUT_REG_BASE : natural := C_INPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE : natural := (C_INPUT_REG_COUNT + 8) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE   : natural := C_STRIDE;

  -- Input register map: 0=trig pos, 1=ARM_FT, 2=trig cfg (AND/OR), 3=reserved,
  -- 4..4+a-1=trig vector cond, 4+a..4+2a-1=trig vector mask (a = C_STRIDE)
  constant C_TRIG_POS_ADDR  : std_logic_vector(31 downto 0) := x"00000000";
  constant C_ARM_FT_ADDR    : std_logic_vector(31 downto 0) := x"00000004";
  constant C_TRIG_CFG_ADDR  : std_logic_vector(31 downto 0) := x"00000008";
  constant C_TRIG_COND_BASE : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(4 * C_AXIL_WORD_BYTES, 32));

  constant C_STATUS_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_SAMP_ADDR   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_SAMPLE_RAM_BASE, 32));
  constant C_SAMP_WORDS  : natural                       := C_DEPTH * C_SAMPLE_STRIDE;

  type t_word_array is array (natural range <>) of std_logic_vector(31 downto 0);

  -- Trigger config: control word (TLAST/TVALID/TREADY, word index
  -- C_DATA_WIDTH/32 within the cond/mask block) requires all three
  -- high; TDATA and padding words are left at '0' (don't-care mask).
  -- cond words 0..3 then mask words 0..3, written as one 8-word burst
  -- starting at C_TRIG_COND_BASE.
  constant C_TRIG_BLOCK : t_word_array(0 to 7) := (
    0 => x"00000000",
    1 => x"00000000",
    2 => x"00000007",
    3 => x"00000000",
    4 => x"00000000",
    5 => x"00000000",
    6 => x"00000007",
    7 => x"00000000"
  );

  signal i_rst_sync    : std_logic := '1';
  signal axis_in_aclk  : std_logic := '0';
  signal axis_out_aclk : std_logic;
  signal s_axil_aclk   : std_logic := '0';

  signal i_ext_trig : std_logic := '0';
  signal o_trig_out  : std_logic;

  signal axis_in_tready : std_logic;
  signal axis_in_tvalid : std_logic                                   := '0';
  signal axis_in_tlast  : std_logic                                   := '0';
  signal axis_in_tdata  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

  signal axis_out_tready : std_logic := '1';
  signal axis_out_tvalid : std_logic;
  signal axis_out_tlast  : std_logic;
  signal axis_out_tdata  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);

  -- Serial link between the DUT and the simulated "PC"
  signal dut_uart_rx : std_logic; -- driven by pc_uart_inst.tx
  signal dut_uart_tx : std_logic; -- driven by the DUT, into pc_uart_inst.rx

  -- "PC" side UART core
  signal pc_tx_data : std_logic_vector(7 downto 0) := (others => '0');
  signal pc_tx_stb  : std_logic                     := '0';
  signal pc_tx_ack  : std_logic;
  signal pc_rx_data : std_logic_vector(7 downto 0);
  signal pc_rx_stb  : std_logic;

  -- Buffers bytes received from the DUT so the echoed response header
  -- (sent as soon as the wrapper has the address) is never dropped
  -- while this testbench is still clocking out write-data bytes.
  signal pc_rxfifo_rd_en   : std_logic := '0';
  signal pc_rxfifo_rd_data : std_logic_vector(7 downto 0);
  signal pc_rxfifo_nempty  : std_logic;

  component libre_ila_uart is
    generic (
      G_AXIS_CLK_FREQ      : integer;
      G_AXIL_CLK_FREQ      : integer;
      G_EXTERNAL_TRIG      : integer;
      G_DATA_WIDTH         : natural;
      G_DEPTH              : natural;
      C_S_AXIL_DATA_WIDTH  : integer;
      C_S_AXIL_ADDR_WIDTH  : integer;
      G_UART_RX_FIFO_DEPTH : natural;
      G_UART_TX_FIFO_DEPTH : natural;
      BAUD_RATE             : integer
    );
    port (
      i_rst_sync : in    std_logic;

      s_axil_aclk : in    std_logic;

      uart_rx : in    std_logic;
      uart_tx : out   std_logic;

      i_ext_trig : in    std_logic;
      o_trig_out : out   std_logic;

      axis_in_aclk   : in    std_logic;
      axis_in_tready : out   std_logic;
      axis_in_tvalid : in    std_logic;
      axis_in_tlast  : in    std_logic;
      axis_in_tdata  : in    std_logic_vector(G_DATA_WIDTH - 1 downto 0);

      axis_out_aclk   : out   std_logic;
      axis_out_tready : in    std_logic;
      axis_out_tvalid : out   std_logic;
      axis_out_tlast  : out   std_logic;
      axis_out_tdata  : out   std_logic_vector(G_DATA_WIDTH - 1 downto 0)
    );
  end component libre_ila_uart;

  component uart is
    generic (
      BAUD            : positive;
      CLOCK_FREQUENCY : positive
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
  end component uart;

  component fifo is
    generic (
      G_WIDTH : natural;
      G_DEPTH : natural
    );
    port (
      i_rst_sync : in    std_logic;
      i_clk      : in    std_logic;

      i_wr_en   : in    std_logic;
      i_wr_data : in    std_logic_vector(G_WIDTH - 1 downto 0);

      i_rd_en   : in    std_logic;
      o_rd_data : out   std_logic_vector(G_WIDTH - 1 downto 0);

      o_nfull  : out   std_logic;
      o_nempty : out   std_logic
    );
  end component fifo;

  -- Push one byte out over the "PC" UART (received by the DUT)
  procedure pc_tx_byte (
    signal clk     : in std_logic;
    signal din     : out std_logic_vector(7 downto 0);
    signal din_stb : out std_logic;
    signal din_ack : in std_logic;
    constant val   : in std_logic_vector(7 downto 0)
  ) is
  begin

    wait until rising_edge(clk);
    din     <= val;
    din_stb <= '1';

    wait until rising_edge(clk) and din_ack = '1';
    din_stb <= '0';

  end procedure pc_tx_byte;

  -- Pop one byte received from the DUT (buffered in pc_rxfifo)
  procedure pc_rx_byte (
    signal clk     : in std_logic;
    signal rd_en   : out std_logic;
    signal rd_data : in std_logic_vector(7 downto 0);
    signal nempty  : in std_logic;
    variable val   : out std_logic_vector(7 downto 0)
  ) is
  begin

    wait until rising_edge(clk) and nempty = '1';
    val := rd_data;
    rd_en <= '1';

    wait until rising_edge(clk);
    rd_en <= '0';

  end procedure pc_rx_byte;

  -- Full "PC to ILA wrapper" write transaction: SYNC, REQ (W, #words),
  -- address, data words (MSB first), then consume+check the echoed
  -- response header.
  procedure uart_ila_write (
    signal clk     : in std_logic;
    signal din     : out std_logic_vector(7 downto 0);
    signal din_stb : out std_logic;
    signal din_ack : in std_logic;
    signal rd_en   : out std_logic;
    signal rd_data : in std_logic_vector(7 downto 0);
    signal nempty  : in std_logic;
    constant addr  : in std_logic_vector(31 downto 0);
    constant data  : in t_word_array
  ) is

    variable n : natural := data'length;
    variable b : std_logic_vector(7 downto 0);

  begin

    pc_tx_byte(clk, din, din_stb, din_ack, x"55");
    pc_tx_byte(clk, din, din_stb, din_ack, '1' & std_logic_vector(to_unsigned(n, 7)));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(31 downto 24));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(23 downto 16));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(15 downto 8));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(7 downto 0));

    for i in 0 to n - 1 loop

      pc_tx_byte(clk, din, din_stb, din_ack, data(i)(31 downto 24));
      pc_tx_byte(clk, din, din_stb, din_ack, data(i)(23 downto 16));
      pc_tx_byte(clk, din, din_stb, din_ack, data(i)(15 downto 8));
      pc_tx_byte(clk, din, din_stb, din_ack, data(i)(7 downto 0));

    end loop;

    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = x"AA" report "uart_ila_write: bad sync in echo header" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = ('1' & std_logic_vector(to_unsigned(n, 7))) report "uart_ila_write: bad req echo" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(31 downto 24) report "uart_ila_write: bad addr echo byte0" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(23 downto 16) report "uart_ila_write: bad addr echo byte1" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(15 downto 8) report "uart_ila_write: bad addr echo byte2" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(7 downto 0) report "uart_ila_write: bad addr echo byte3" severity error;

  end procedure uart_ila_write;

  -- Full "PC to ILA wrapper" read transaction: SYNC, REQ (R, #words),
  -- address, then consume+check the echoed response header and
  -- unpack the trailing data words (MSB first) into `result`.
  procedure uart_ila_read (
    signal clk      : in std_logic;
    signal din      : out std_logic_vector(7 downto 0);
    signal din_stb  : out std_logic;
    signal din_ack  : in std_logic;
    signal rd_en    : out std_logic;
    signal rd_data  : in std_logic_vector(7 downto 0);
    signal nempty   : in std_logic;
    constant addr   : in std_logic_vector(31 downto 0);
    constant n      : in natural;
    variable result : out t_word_array
  ) is

    variable b, b3, b2, b1, b0 : std_logic_vector(7 downto 0);

  begin

    pc_tx_byte(clk, din, din_stb, din_ack, x"55");
    pc_tx_byte(clk, din, din_stb, din_ack, '0' & std_logic_vector(to_unsigned(n, 7)));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(31 downto 24));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(23 downto 16));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(15 downto 8));
    pc_tx_byte(clk, din, din_stb, din_ack, addr(7 downto 0));

    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = x"AA" report "uart_ila_read: bad sync in echo header" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = ('0' & std_logic_vector(to_unsigned(n, 7))) or b = ('1' & std_logic_vector(to_unsigned(n, 7)))
      report "uart_ila_read: bad req echo" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(31 downto 24) report "uart_ila_read: bad addr echo byte0" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(23 downto 16) report "uart_ila_read: bad addr echo byte1" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(15 downto 8) report "uart_ila_read: bad addr echo byte2" severity error;
    pc_rx_byte(clk, rd_en, rd_data, nempty, b);
    assert b = addr(7 downto 0) report "uart_ila_read: bad addr echo byte3" severity error;

    for i in 0 to n - 1 loop

      pc_rx_byte(clk, rd_en, rd_data, nempty, b3);
      pc_rx_byte(clk, rd_en, rd_data, nempty, b2);
      pc_rx_byte(clk, rd_en, rd_data, nempty, b1);
      pc_rx_byte(clk, rd_en, rd_data, nempty, b0);
      result(i) := b3 & b2 & b1 & b0;

    end loop;

  end procedure uart_ila_read;

begin

  dut : component libre_ila_uart
    generic map (
      g_axis_clk_freq      => C_AXIL_CLK_FREQ,
      g_axil_clk_freq      => C_AXIL_CLK_FREQ,
      g_external_trig      => 0,
      g_data_width         => C_DATA_WIDTH,
      g_depth              => C_DEPTH,
      c_s_axil_data_width  => 32,
      c_s_axil_addr_width  => 32,
      g_uart_rx_fifo_depth => 64,
      g_uart_tx_fifo_depth => 64,
      baud_rate            => C_BAUD_RATE
    )
    port map (
      i_rst_sync => i_rst_sync,

      s_axil_aclk => s_axil_aclk,

      uart_rx => dut_uart_rx,
      uart_tx => dut_uart_tx,

      i_ext_trig => i_ext_trig,
      o_trig_out => o_trig_out,

      axis_in_aclk   => axis_in_aclk,
      axis_in_tready => axis_in_tready,
      axis_in_tvalid => axis_in_tvalid,
      axis_in_tlast  => axis_in_tlast,
      axis_in_tdata  => axis_in_tdata,

      axis_out_aclk   => axis_out_aclk,
      axis_out_tready => axis_out_tready,
      axis_out_tvalid => axis_out_tvalid,
      axis_out_tlast  => axis_out_tlast,
      axis_out_tdata  => axis_out_tdata
    );

  pc_uart_inst : component uart
    generic map (
      baud            => C_BAUD_RATE,
      clock_frequency => C_AXIL_CLK_FREQ
    )
    port map (
      clock               => s_axil_aclk,
      reset               => i_rst_sync,
      data_stream_in      => pc_tx_data,
      data_stream_in_stb  => pc_tx_stb,
      data_stream_in_ack  => pc_tx_ack,
      data_stream_out     => pc_rx_data,
      data_stream_out_stb => pc_rx_stb,
      tx                  => dut_uart_rx,
      rx                  => dut_uart_tx
    );

  pc_rxfifo_inst : component fifo
    generic map (
      g_width => 8,
      g_depth => 32
    )
    port map (
      i_rst_sync => i_rst_sync,
      i_clk      => s_axil_aclk,
      i_wr_en    => pc_rx_stb,
      i_wr_data  => pc_rx_data,
      i_rd_en    => pc_rxfifo_rd_en,
      o_rd_data  => pc_rxfifo_rd_data,
      o_nfull    => open,
      o_nempty   => pc_rxfifo_nempty
    );

  p_axis_clk : process is
  begin

    while true loop

      axis_in_aclk <= '0';
      wait for C_AXIS_PERIOD / 2;
      axis_in_aclk <= '1';
      wait for C_AXIS_PERIOD / 2;

    end loop;

  end process p_axis_clk;

  p_axil_clk : process is
  begin

    while true loop

      s_axil_aclk <= '0';
      wait for C_AXIL_PERIOD / 2;
      s_axil_aclk <= '1';
      wait for C_AXIL_PERIOD / 2;

    end loop;

  end process p_axil_clk;

  p_stimulus : process is

    variable status_word : t_word_array(0 to 0);
    variable magic_word  : t_word_array(0 to 0);
    variable samp_words  : t_word_array(0 to C_SAMP_WORDS - 1);

  begin

    wait for 40 ns;
    i_rst_sync <= '0';

    for settle_index in 1 to 4 loop

      wait until rising_edge(axis_in_aclk);

    end loop;

    -- Configure trigger position, AND/OR mode, and the trigger vector
    -- cond+mask block (8 contiguous words: cond then mask), all over UART
    uart_ila_write(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_TRIG_POS_ADDR, (0 => std_logic_vector(to_unsigned(C_TRIG_IDX, 32)))
    );

    uart_ila_write(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_TRIG_CFG_ADDR, (0 => x"00000000")
    );

    uart_ila_write(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_TRIG_COND_BASE, C_TRIG_BLOCK
    );

    -- Read back the configuration we just wrote before arming, to prove
    -- the UART write path actually landed in the core's registers
    uart_ila_read(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_TRIG_COND_BASE, 8, samp_words(0 to 7)
    );

    for i in 0 to 7 loop

      assert samp_words(i) = C_TRIG_BLOCK(i)
        report "06_sim_libre_ila_uart: trigger cond/mask readback mismatch at word " & integer'image(i)
        severity error;

    end loop;

    for settle_index in 1 to 4 loop

      wait until rising_edge(axis_in_aclk);

    end loop;

    -- Arm the ILA (any write to ARM_FT arms/forces trigger)
    uart_ila_write(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_ARM_FT_ADDR, (0 => x"00000001")
    );

    uart_ila_read(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_STATUS_ADDR, 1, status_word
    );
    report "06_sim_libre_ila_uart: status after arm = 0x" & to_hstring(status_word(0)) severity note;
    assert status_word(0)(0) = '1' report "06_sim_libre_ila_uart: ILA failed to ARM" severity error;

    -- Stream probe stimulus, same pattern as 01_sim_axil_trig: TLAST
    -- pulses at the trigger point, TREADY backpressure elsewhere.
    for sample_index in 0 to C_SAMPLE_COUNT - 1 loop

      wait until falling_edge(axis_in_aclk);
      axis_in_tvalid <= '1';
      axis_in_tdata  <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));

      if (sample_index = C_TRIGGER_POINT) then
        axis_in_tlast <= '1';
      else
        axis_in_tlast <= '0';
      end if;

      if (sample_index mod 5 = 3 and sample_index /= C_TRIGGER_POINT) then
        axis_out_tready <= '0';
      else
        axis_out_tready <= '1';
      end if;

      wait until rising_edge(axis_in_aclk);

    end loop;

    axis_in_tvalid  <= '0';
    axis_in_tlast   <= '0';
    axis_out_tready <= '1';

    -- Poll STATUS over UART until DONE asserts
    for attempt in 0 to 63 loop

      uart_ila_read(
        s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
        pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
        C_STATUS_ADDR, 1, status_word
      );
      exit when status_word(0)(2) = '1';

    end loop;

    assert status_word(0)(2) = '1'
      report "06_sim_libre_ila_uart: DONE did not assert"
      severity error;

    uart_ila_read(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_MAGIC_ADDR, 1, magic_word
    );
    assert magic_word(0) = x"B01DFACE"
      report "06_sim_libre_ila_uart: magic key mismatch"
      severity error;

    -- Read the whole sample buffer back in a single UART transaction
    uart_ila_read(
      s_axil_aclk, pc_tx_data, pc_tx_stb, pc_tx_ack,
      pc_rxfifo_rd_en, pc_rxfifo_rd_data, pc_rxfifo_nempty,
      C_SAMP_ADDR, C_SAMP_WORDS, samp_words
    );

    for sample_index in 0 to C_DEPTH - 1 loop

      report "06_sim_libre_ila_uart: sample " & integer'image(sample_index) &
             " | lane2=0x" & to_hstring(samp_words(sample_index * C_SAMPLE_STRIDE + 2)) &
             " | lane1=0x" & to_hstring(samp_words(sample_index * C_SAMPLE_STRIDE + 1)) &
             " | lane0=0x" & to_hstring(samp_words(sample_index * C_SAMPLE_STRIDE + 0))
        severity note;

    end loop;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
