---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Created: 2026-07-21 Tue 19:55
-- Last Modified: 2026-07-21 Tue 20:00
--
-- Description: Test the ILA with different clock domain configurations
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

  -- Clock domain frequency configuration
  constant C_AXIS_FREQ_MHZ : real := 100.0;
  constant C_AXIL_FREQ_MHZ : real := 200.0;

  constant C_AXIS_PERIOD   : time := integer(1_000_000.0 / C_AXIS_FREQ_MHZ) * 1 ps;
  constant C_AXIL_PERIOD   : time := integer(1_000_000.0 / C_AXIL_FREQ_MHZ) * 1 ps;

  constant C_TRIG_IDX      : natural := 3;
  constant C_TRIGGER_POINT : natural := 80;
  constant C_TRIGGER_PULSE : natural := 16;
  constant C_SAMPLE_COUNT  : natural := 192;

  constant TRIGGER_COND      : std_logic_vector(31 downto 0) := x"00000001";
  constant TRIGGER_MASK      : std_logic_vector(31 downto 0) := x"00000000";
  constant TRIGGER_DATA      : std_logic_vector(63 downto 0) := x"00000000_00000045";
  constant TRIGGER_DATA_MASK : std_logic_vector(63 downto 0) := x"00000000_00000555";

  constant C_AXIL_WORD_BYTES : natural := 4;
  -- The DUT maps output registers after the input-register block.
  -- For this configuration, the output block begins at input-reg-count * 4 bytes.
  constant C_INPUT_REG_COUNT : natural := 4 + 2 * (C_DATA_WIDTH / 32);
  constant C_OUTPUT_REG_BASE : natural := C_INPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE : natural := (4 + 2 * (C_DATA_WIDTH / 32) + 8) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE   : natural := 2 ** integer(ceil(log2(real((C_DATA_WIDTH / 32) + 1))));
  -- The current address decoder exposes the buffer RAM window.
  constant C_SAMPLE_PRINT_COUNT : natural                       := C_DEPTH;
  constant C_STATUS_ADDR        : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR         : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));

  signal i_rst_sync    : std_logic := '1';
  signal axis_in_aclk  : std_logic := '0';
  signal axis_out_aclk : std_logic := '0';
  signal s_axil_aclk   : std_logic := '0';

  signal i_ext_trig : std_logic := '0';
  signal o_trig_out : std_logic;

  signal axis_in_tready : std_logic;
  signal axis_in_tvalid : std_logic                                   := '0';
  signal axis_in_tlast  : std_logic                                   := '0';
  signal axis_in_tdata  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

  signal axis_out_tready : std_logic := '1';
  signal axis_out_tvalid : std_logic;
  signal axis_out_tlast  : std_logic;
  signal axis_out_tdata  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);

  signal s_axil_aresetn : std_logic                     := '0';
  signal s_axil_awaddr  : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axil_awprot  : std_logic_vector(2 downto 0)  := (others => '0');
  signal s_axil_awvalid : std_logic                     := '0';
  signal s_axil_awready : std_logic;
  signal s_axil_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axil_wstrb   : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axil_wvalid  : std_logic                     := '0';
  signal s_axil_wready  : std_logic;
  signal s_axil_bresp   : std_logic_vector(1 downto 0);
  signal s_axil_bvalid  : std_logic;
  signal s_axil_bready  : std_logic                     := '0';
  signal s_axil_araddr  : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axil_arprot  : std_logic_vector(2 downto 0)  := (others => '0');
  signal s_axil_arvalid : std_logic                     := '0';
  signal s_axil_arready : std_logic;
  signal s_axil_rdata   : std_logic_vector(31 downto 0);
  signal s_axil_rresp   : std_logic_vector(1 downto 0);
  signal s_axil_rvalid  : std_logic;
  signal s_axil_rready  : std_logic                     := '0';

  procedure axil_write (
    signal clk     : in std_logic;
    signal awaddr  : out std_logic_vector(31 downto 0);
    signal awvalid : out std_logic;
    signal wdata   : out std_logic_vector(31 downto 0);
    signal wvalid  : out std_logic;
    signal bready  : out std_logic;
    signal bvalid  : in std_logic;
    constant addr  : in std_logic_vector(31 downto 0);
    constant data  : in std_logic_vector(31 downto 0)
  ) is
  begin

    awaddr  <= addr;
    awvalid <= '1';
    wdata   <= data;
    wvalid  <= '1';
    bready  <= '1';

    while bvalid /= '1' loop

      wait until rising_edge(clk);

    end loop;

    awvalid <= '0';
    wvalid  <= '0';
    bready  <= '0';

  end procedure axil_write;

  procedure axil_arm (
    signal clk     : in std_logic;
    signal awaddr  : out std_logic_vector(31 downto 0);
    signal awvalid : out std_logic;
    signal wdata   : out std_logic_vector(31 downto 0);
    signal wvalid  : out std_logic;
    signal bready  : out std_logic;
    signal bvalid  : in std_logic;
    constant addr  : in std_logic_vector(31 downto 0);
    constant data  : in std_logic_vector(31 downto 0)
  ) is
  begin

    awaddr  <= addr;
    awvalid <= '1';
    wdata   <= data;
    wvalid  <= '1';
    bready  <= '1';

    wait until rising_edge(clk);

    wvalid <= '0';

    while bvalid /= '1' loop

      wait until rising_edge(clk);

    end loop;

    awvalid <= '0';
    bready  <= '0';

  end procedure axil_arm;

  procedure axil_read (
    signal clk     : in std_logic;
    signal araddr  : out std_logic_vector(31 downto 0);
    signal arvalid : out std_logic;
    signal rready  : out std_logic;
    signal rdata   : in std_logic_vector(31 downto 0);
    signal rvalid  : in std_logic;
    constant addr  : in std_logic_vector(31 downto 0);
    variable data  : out std_logic_vector(31 downto 0)
  ) is
  begin

    araddr  <= addr;
    arvalid <= '1';
    rready  <= '1';

    while rvalid /= '1' loop

      wait until rising_edge(clk);

    end loop;

    data    := rdata;
    arvalid <= '0';
    rready  <= '0';

  end procedure axil_read;

begin

  dut : entity work.libre_ila
    generic map (
      g_external_trig => 0,
      g_data_width    => C_DATA_WIDTH,
      g_depth         => C_DEPTH
    )
    port map (
      i_rst_sync      => i_rst_sync,
      axis_in_aclk    => axis_in_aclk,
      axis_out_aclk   => axis_out_aclk,
      i_ext_trig      => i_ext_trig,
      o_trig_out      => o_trig_out,
      axis_in_tready  => axis_in_tready,
      axis_in_tvalid  => axis_in_tvalid,
      axis_in_tlast   => axis_in_tlast,
      axis_in_tdata   => axis_in_tdata,
      axis_out_tready => axis_out_tready,
      axis_out_tvalid => axis_out_tvalid,
      axis_out_tlast  => axis_out_tlast,
      axis_out_tdata  => axis_out_tdata,
      s_axil_aclk     => s_axil_aclk,
      s_axil_aresetn  => s_axil_aresetn,
      s_axil_awaddr   => s_axil_awaddr,
      s_axil_awprot   => s_axil_awprot,
      s_axil_awvalid  => s_axil_awvalid,
      s_axil_awready  => s_axil_awready,
      s_axil_wdata    => s_axil_wdata,
      s_axil_wstrb    => s_axil_wstrb,
      s_axil_wvalid   => s_axil_wvalid,
      s_axil_wready   => s_axil_wready,
      s_axil_bresp    => s_axil_bresp,
      s_axil_bvalid   => s_axil_bvalid,
      s_axil_bready   => s_axil_bready,
      s_axil_araddr   => s_axil_araddr,
      s_axil_arprot   => s_axil_arprot,
      s_axil_arvalid  => s_axil_arvalid,
      s_axil_arready  => s_axil_arready,
      s_axil_rdata    => s_axil_rdata,
      s_axil_rresp    => s_axil_rresp,
      s_axil_rvalid   => s_axil_rvalid,
      s_axil_rready   => s_axil_rready
    );

  p_axis_clk : process is
  begin

    while true loop

      axis_in_aclk  <= '0';
      wait for C_AXIS_PERIOD / 2;
      axis_in_aclk  <= '1';
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

    variable read_data : std_logic_vector(31 downto 0);
    variable status    : std_logic_vector(31 downto 0);

    type t_lane_data is array (natural range <>) of std_logic_vector(31 downto 0);

    variable lane_data : t_lane_data(0 to C_DATA_WIDTH / 32);

  begin

    wait for 40 ns;
    i_rst_sync     <= '0';
    s_axil_aresetn <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(axis_in_aclk);

    end loop;

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, x"00000008", std_logic_vector(to_unsigned(C_TRIG_IDX, 32)));

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, x"00000000", TRIGGER_COND);

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, x"00000004", TRIGGER_MASK);

    -- Trigger data words (Index 4 to 4 + a - 1)
    for word_idx in 0 to (C_DATA_WIDTH / 32) - 1 loop

      wait until rising_edge(s_axil_aclk);
      axil_write(
        s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid,
        std_logic_vector(to_unsigned((4 + word_idx) * 4, 32)),
        TRIGGER_DATA(31 + word_idx * 32 downto word_idx * 32)
      );

    end loop;

    -- Trigger data mask words (Index 4 + a to 4 + 2a - 1)
    for word_idx in 0 to (C_DATA_WIDTH / 32) - 1 loop

      wait until rising_edge(s_axil_aclk);
      axil_write(
        s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid,
        std_logic_vector(to_unsigned((4 + (C_DATA_WIDTH / 32) + word_idx) * 4, 32)),
        TRIGGER_DATA_MASK(31 + word_idx * 32 downto word_idx * 32)
      );

    end loop;

    for settle_index in 1 to 4 loop

      wait until rising_edge(axis_in_aclk);

    end loop;

    axil_arm(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, x"0000000C", x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(axis_in_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    report "00_sim_ext_trig: status after arm = " & integer'image(to_integer(unsigned(status(2 downto 0))))
      severity note;

    for sample_index in 0 to C_SAMPLE_COUNT - 1 loop

      wait until falling_edge(axis_in_aclk);
      axis_in_tvalid <= '1';
      axis_in_tdata  <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));

      -- Pulse TLAST at trigger sample index
      if (sample_index = C_TRIGGER_POINT) then
        axis_in_tlast <= '1';
      else
        axis_in_tlast <= '0';
      end if;

      -- Inject TREADY backpressure every 5th cycle, ensuring TREADY = '1' at trigger point
      if (sample_index mod 5 = 3 and sample_index /= C_TRIGGER_POINT) then
        axis_out_tready <= '0';
      else
        axis_out_tready <= '1';
      end if;

      i_ext_trig <= '0';

      wait until rising_edge(axis_in_aclk);

    end loop;

    i_ext_trig      <= '0';
    axis_in_tvalid  <= '0';
    axis_in_tlast   <= '0';
    axis_out_tready <= '1';

    for attempt in 0 to 511 loop

      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
      exit when status(2) = '1';

    end loop;

    assert status(2) = '1'
      report "00_sim_ext_trig: DONE did not assert"
      severity error;

    for settle_index in 1 to 4 loop

      wait until rising_edge(s_axil_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_MAGIC_ADDR, read_data);
    assert read_data = x"B01DFACE"
      report "00_sim_ext_trig: magic key mismatch"
      severity error;

    -- Reading back output samples from RAM window
    for sample_index in 0 to C_SAMPLE_PRINT_COUNT - 1 loop

      for lane_index in 0 to (C_DATA_WIDTH / 32) loop

        wait until rising_edge(s_axil_aclk);
        axil_read(
                  s_axil_aclk,
                  s_axil_araddr,
                  s_axil_arvalid,
                  s_axil_rready,
                  s_axil_rdata,
                  s_axil_rvalid,
                  std_logic_vector(to_unsigned(C_SAMPLE_RAM_BASE + sample_index * C_SAMPLE_STRIDE * C_AXIL_WORD_BYTES + lane_index * C_AXIL_WORD_BYTES, 32)),
                  read_data
                );
        lane_data(lane_index) := read_data;

      end loop;

      report "00_sim_ext_trig: sample " & integer'image(sample_index) &
             " | lane2=0x" & to_hstring(lane_data(2)) &
             " | lane1=0x" & to_hstring(lane_data(1)) &
             " | lane0=0x" & to_hstring(lane_data(0))
        severity note;

      wait until rising_edge(s_axil_aclk);

    end loop;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
