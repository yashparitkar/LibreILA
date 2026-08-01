---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Created: 2026-07-16 Mon 13:27
-- Last Modified: 2026-07-30 Thu 10:32
--
-- Description: Test the ILA in external trigger configuration
--
-- The Makefile runs this bench once per trigger position, each run in its
-- own work directory with its own copy of this file and C_TRIG_IDX patched
-- in it, see the VARIANTS list there.
--
-- Copyright 2026 Yash Paritkar
-- SPDX-License-Identifier: CERN-OHL-P-2.0
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

  constant C_DATA_WIDTH      : natural := 64;
  constant C_SAMP_BUFF_DEPTH : natural := 8;
  constant C_AXIS_PERIOD     : time    := 10 ns;
  constant C_AXIL_PERIOD     : time    := 10 ns;
  -- The trigger position under test. The Makefile rewrites the right hand
  -- side of this one line per work directory, so keep it on a single line and
  -- keep the name, otherwise the sweep silently falls back to this value.
  constant C_TRIG_IDX      : natural := 3;
  constant C_TRIGGER_POINT : natural := 80;
  constant C_TRIGGER_PULSE : natural := 16;
  constant C_SAMPLE_COUNT  : natural := 192;

  -- The trigger position is the number of samples the DUT keeps from before
  -- the triggering one, so the capture window is C_TRIG_POS samples of history
  -- plus the trigger plus the rest of the buffer. The DUT holds the position
  -- in a counter as wide as the buffer address, so anything from
  -- C_SAMP_BUFF_DEPTH up arrives truncated and the expectation follows it.
  constant C_TRIG_POS : natural := C_TRIG_IDX mod C_SAMP_BUFF_DEPTH;

  constant C_AXIL_WORD_BYTES : natural := 4;
  -- The probe word the DUT samples, TDATA plus the signalling ports, one
  -- flat vector. This is what gets driven into G_PROBE_WIDTH, the DUT no
  -- longer derives it from the TDATA width, see hdl/libre_ila.vhdl.
  constant C_N_SIGNALS   : natural := 3;
  constant C_PROBE_WIDTH : natural := C_DATA_WIDTH + C_N_SIGNALS;
  constant C_N_LANES     : natural := integer(ceil(real(C_PROBE_WIDTH) / 32.0));
  -- Matches the DUT's C_AXIL_STRIDE: next power-of-two lane count, minimum 4
  -- -- same constant the DUT uses to size both the trigger vector block and
  -- the output sample stride.
  constant C_STRIDE : natural := maximum(4, 2 ** integer(ceil(log2(real(C_N_LANES)))));
  -- The DUT maps the fixed size output block at the base address and the
  -- input block, which grows with C_STRIDE, above it. That is what lets a
  -- reader find STATUS and the magic key without knowing the probe width.
  constant C_OUTPUT_REG_COUNT : natural := 8;
  constant C_INPUT_REG_COUNT  : natural := 4 + 2 * C_STRIDE;
  constant C_OUTPUT_REG_BASE  : natural := 0;
  constant C_INPUT_REG_BASE   : natural := C_OUTPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE  : natural := (C_OUTPUT_REG_COUNT + C_INPUT_REG_COUNT) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE   : natural := C_STRIDE;

  -- Input block, indices relative to C_INPUT_REG_BASE: 0=trig pos, 1=ARM_FT,
  -- 2=trig cfg (AND/OR), 3=reserved
  constant C_TRIG_POS_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_ARM_FT_ADDR   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));

  constant C_SAMPLE_PRINT_COUNT : natural                       := C_SAMP_BUFF_DEPTH;
  constant C_STATUS_ADDR        : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR         : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  -- Output register 6 carries trig_idx, the buffer slot that held the
  -- triggering sample. The readout order below is what the trigger position
  -- rotates, this is the anchor it is rotated around.
  constant C_TRIG_IDX_ADDR      : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 6 * C_AXIL_WORD_BYTES, 32));

  -- Every report carries the trigger position, the three runs of the sweep
  -- otherwise print the same lines and cannot be told apart in the log.
  constant C_TEST_ID : string := "00_sim_ext_trig[C_TRIG_IDX=" & integer'image(C_TRIG_IDX) & "]";

  signal i_rst_sync    : std_logic := '1';
  signal samp_aclk     : std_logic := '0';
  signal s_axil_aclk   : std_logic := '0';

  signal i_ext_trig : std_logic := '0';
  signal o_trig_out : std_logic;

  signal probe_slave_axis_tready : std_logic;
  signal probe_slave_axis_tvalid : std_logic                                   := '0';
  signal probe_slave_axis_tlast  : std_logic                                   := '0';
  signal probe_slave_axis_tdata  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

  signal probe_master_axis_tready : std_logic := '1';
  signal probe_master_axis_tvalid : std_logic;
  signal probe_master_axis_tlast  : std_logic;
  signal probe_master_axis_tdata  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);

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
    signal awready : in std_logic;
    signal wready  : in std_logic;
    constant addr  : in std_logic_vector(31 downto 0);
    constant data  : in std_logic_vector(31 downto 0)
  ) is
  begin

    awaddr  <= addr;
    awvalid <= '1';
    wdata   <= data;
    wvalid  <= '1';

    -- Wait for the slave to accept THIS address+data. AWREADY/WREADY are
    -- fresh per-cycle handshake signals; BVALID alone is not safe to poll
    -- here since the slave's write FSM can leave it asserted from a prior
    -- back-to-back write, which would make this wait return immediately
    -- without the new address/data ever having been latched.
    wait until rising_edge(clk) and awready = '1' and wready = '1';

    awvalid <= '0';
    wvalid  <= '0';
    bready  <= '1';

    -- Consume the response, then drop BREADY so the slave can clear
    -- BVALID before the next transaction starts.
    wait until rising_edge(clk) and bvalid = '1';
    bready <= '0';

  end procedure axil_write;

  procedure axil_arm (
    signal clk     : in std_logic;
    signal awaddr  : out std_logic_vector(31 downto 0);
    signal awvalid : out std_logic;
    signal wdata   : out std_logic_vector(31 downto 0);
    signal wvalid  : out std_logic;
    signal bready  : out std_logic;
    signal bvalid  : in std_logic;
    signal awready : in std_logic;
    signal wready  : in std_logic;
    constant addr  : in std_logic_vector(31 downto 0);
    constant data  : in std_logic_vector(31 downto 0)
  ) is
  begin

    awaddr  <= addr;
    awvalid <= '1';
    wdata   <= data;
    wvalid  <= '1';

    wait until rising_edge(clk) and awready = '1' and wready = '1';

    awvalid <= '0';
    wvalid  <= '0';
    bready  <= '1';

    wait until rising_edge(clk) and bvalid = '1';
    bready <= '0';

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
      g_external_trig   => 1,
      g_probe_width     => C_PROBE_WIDTH,
      g_samp_buff_depth => C_SAMP_BUFF_DEPTH
    )
    port map (
      i_rst_sync               => i_rst_sync,
      samp_aclk                => samp_aclk,
      i_ext_trig               => i_ext_trig,
      o_trig_out               => o_trig_out,
      probe_slave_axis_tready  => probe_slave_axis_tready,
      probe_slave_axis_tvalid  => probe_slave_axis_tvalid,
      probe_slave_axis_tlast   => probe_slave_axis_tlast,
      probe_slave_axis_tdata   => probe_slave_axis_tdata,
      probe_master_axis_tready => probe_master_axis_tready,
      probe_master_axis_tvalid => probe_master_axis_tvalid,
      probe_master_axis_tlast  => probe_master_axis_tlast,
      probe_master_axis_tdata  => probe_master_axis_tdata,
      s_axil_aclk              => s_axil_aclk,
      s_axil_aresetn           => s_axil_aresetn,
      s_axil_awaddr            => s_axil_awaddr,
      s_axil_awprot            => s_axil_awprot,
      s_axil_awvalid           => s_axil_awvalid,
      s_axil_awready           => s_axil_awready,
      s_axil_wdata             => s_axil_wdata,
      s_axil_wstrb             => s_axil_wstrb,
      s_axil_wvalid            => s_axil_wvalid,
      s_axil_wready            => s_axil_wready,
      s_axil_bresp             => s_axil_bresp,
      s_axil_bvalid            => s_axil_bvalid,
      s_axil_bready            => s_axil_bready,
      s_axil_araddr            => s_axil_araddr,
      s_axil_arprot            => s_axil_arprot,
      s_axil_arvalid           => s_axil_arvalid,
      s_axil_arready           => s_axil_arready,
      s_axil_rdata             => s_axil_rdata,
      s_axil_rresp             => s_axil_rresp,
      s_axil_rvalid            => s_axil_rvalid,
      s_axil_rready            => s_axil_rready
    );

  p_axis_clk : process is
  begin

    while true loop

      samp_aclk <= '0';
      wait for C_AXIS_PERIOD / 2;
      samp_aclk <= '1';
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

    variable lane_data : t_lane_data(0 to C_N_LANES - 1);

    -- The probe counter value read out of every buffer slot, indexed by slot.
    type t_sample_values is array (natural range <>) of natural;

    variable samples     : t_sample_values(0 to C_SAMP_BUFF_DEPTH - 1);
    variable trig_slot   : natural;
    variable prev_slot   : natural;
    variable wrap_count  : natural := 0;
    variable oldest_slot : natural := 0;
    variable oldest      : natural;
    variable newest      : natural;

  begin

    -- The check after the readout wants every slot, so the readout has to
    -- cover the whole buffer rather than a subset of it.
    assert C_SAMPLE_PRINT_COUNT = C_SAMP_BUFF_DEPTH
      report C_TEST_ID & ": readout covers " & integer'image(C_SAMPLE_PRINT_COUNT) &
             " of " & integer'image(C_SAMP_BUFF_DEPTH) & " buffer slots"
      severity failure;

    wait for 40 ns;
    i_rst_sync     <= '0';
    s_axil_aresetn <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_POS_ADDR, std_logic_vector(to_unsigned(C_TRIG_IDX, 32)));

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_arm(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- Status lives in the output register block, not the input configuration block.
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    report C_TEST_ID & ": status after arm = " & integer'image(to_integer(unsigned(status(2 downto 0))))
      severity note;

    for sample_index in 0 to C_SAMPLE_COUNT - 1 loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tvalid <= '1';
      probe_slave_axis_tdata  <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));
      probe_slave_axis_tlast  <= '0';

      if (sample_index >= C_TRIGGER_POINT and sample_index < C_TRIGGER_POINT + C_TRIGGER_PULSE) then
        i_ext_trig <= '1';
      else
        i_ext_trig <= '0';
      end if;

      wait until rising_edge(samp_aclk);

    end loop;

    i_ext_trig     <= '0';
    probe_slave_axis_tvalid <= '0';
    probe_slave_axis_tlast  <= '0';

    for attempt in 0 to 511 loop

      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
      exit when status(2) = '1';

    end loop;

    assert status(2) = '1'
      report C_TEST_ID & ": DONE did not assert"
      severity error;

    for settle_index in 1 to 4 loop

      wait until rising_edge(s_axil_aclk);

    end loop;

    -- The magic key is the next output register after the status register.
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_MAGIC_ADDR, read_data);
    assert read_data = x"B01DFACE"
      report C_TEST_ID & ": magic key mismatch"
      severity error;

    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_TRIG_IDX_ADDR, read_data);
    trig_slot := to_integer(unsigned(read_data));
    report C_TEST_ID & ": trig_idx readback, triggering sample sits in buffer slot " & integer'image(trig_slot)
      severity note;

    -- Reading back the output samples.
    -- Each sample is stored across the RAM window as one stride of 32-bit words.
    for sample_index in 0 to C_SAMPLE_PRINT_COUNT - 1 loop

      for lane_index in 0 to C_N_LANES - 1 loop

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

      report C_TEST_ID & ": sample " & integer'image(sample_index) &
             " | lane2=0x" & to_hstring(lane_data(2)) &
             " | lane1=0x" & to_hstring(lane_data(1)) &
             " | lane0=0x" & to_hstring(lane_data(0))
        severity note;

      -- The bench drives the probe with a counter that never reaches 2**32,
      -- so the upper word is a free check that the slot holds a sample at all.
      assert lane_data(1) = x"00000000"
        report C_TEST_ID & ": slot " & integer'image(sample_index) &
               " upper counter word is 0x" & to_hstring(lane_data(1)) & ", expected 0"
        severity error;

      samples(sample_index) := to_integer(unsigned(lane_data(0)));

      wait until rising_edge(s_axil_aclk);

    end loop;

    -- The probe carried an incrementing counter, so a correct capture is one
    -- contiguous run of it wrapped around the buffer: exactly one slot may
    -- fail to follow its predecessor, and that slot holds the oldest sample.
    for slot in 0 to C_SAMP_BUFF_DEPTH - 1 loop

      prev_slot := (slot + C_SAMP_BUFF_DEPTH - 1) mod C_SAMP_BUFF_DEPTH;

      if (samples(slot) /= samples(prev_slot) + 1) then
        wrap_count  := wrap_count + 1;
        oldest_slot := slot;
      end if;

    end loop;

    assert wrap_count = 1
      report C_TEST_ID & ": the " & integer'image(C_SAMP_BUFF_DEPTH) &
             " slots are not one contiguous run of the probe counter, " &
             integer'image(wrap_count) & " discontinuities"
      severity error;

    oldest := samples(oldest_slot);
    newest := samples((oldest_slot + C_SAMP_BUFF_DEPTH - 1) mod C_SAMP_BUFF_DEPTH);

    -- The slot the DUT reports as the trigger has to be the one holding the
    -- sample the bench triggered on, otherwise the readback points at
    -- history that is no longer in the buffer.
    assert samples(trig_slot) = C_TRIGGER_POINT
      report C_TEST_ID & ": trig_idx points at slot " & integer'image(trig_slot) &
             " holding sample " & integer'image(samples(trig_slot)) &
             ", the bench triggered on sample " & integer'image(C_TRIGGER_POINT)
      severity error;

    -- A trigger position of p keeps p samples of history, so the window starts
    -- p samples before the trigger and runs to the end of the buffer.
    assert oldest = C_TRIGGER_POINT - C_TRIG_POS
      report C_TEST_ID & ": capture window is " & integer'image(oldest) & ".." &
             integer'image(newest) & ", trigger position " & integer'image(C_TRIG_POS) &
             " asks for " & integer'image(C_TRIGGER_POINT - C_TRIG_POS) & ".." &
             integer'image(C_TRIGGER_POINT - C_TRIG_POS + C_SAMP_BUFF_DEPTH - 1)
      severity error;

    report C_TEST_ID & ": buffer holds samples " & integer'image(oldest) & ".." &
           integer'image(newest) & ", oldest in slot " & integer'image(oldest_slot) &
           ", trigger in slot " & integer'image(trig_slot) &
           ", as trigger position " & integer'image(C_TRIG_POS) & " asks"
      severity note;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
