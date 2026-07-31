---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Created: 2026-07-30 Thu
--
-- Description: Level vs edge triggering, trig_cfg bits 1 and 2.
--
-- The condition under test is "TVALID = '1'", enabled on its own in the
-- trigger mask, and the bench deliberately holds it TRUE across the arm.
-- That is the case the three modes disagree about:
--
--   level   : the condition is already true, so it triggers on the first
--             sample the ILA takes and captures nothing of interest
--   rising  : it waits for the 0 -> 1 transition at C_RISE_POINT
--   falling : it waits for the 1 -> 0 transition at C_FALL_POINT
--
-- Because TVALID is true at the arm, this bench also pins the seeding of
-- trig_lvl_prev: if it were cleared to '0' on arm instead of loaded with the
-- live condition, the rising run would fire on the first sample like the
-- level run does, and its check below would fail.
--
-- The Makefile runs this bench once per mode, each run in its own work
-- directory with its own copy of this file and C_MODE patched in it, see the
-- VARIANTS list there.
--
-- The level run triggers so early that fewer than C_TRIG_IDX samples have been
-- captured by then, so the pre trigger slots of its readout print as X. That is
-- unwritten RAM rather than a fault, and the checks below only look at the slot
-- the DUT names in trig_idx.
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

  -- The mode under test: 0 = level, 1 = rising, 2 = falling. The Makefile
  -- rewrites the right hand side of this one line per work directory, so keep
  -- it on a single line and keep the name, otherwise the sweep silently falls
  -- back to this value.
  constant C_MODE : natural := 1;

  -- TVALID is high from before the arm, drops at C_FALL_POINT and comes back
  -- at C_RISE_POINT. Both are far enough apart that a run triggering on the
  -- wrong one is unmistakable in the readback.
  constant C_FALL_POINT   : natural := 20;
  constant C_RISE_POINT   : natural := 40;
  constant C_SAMPLE_COUNT : natural := 80;

  constant C_TRIG_IDX : natural := 2;

  -- Only TVALID participates. Probe bit 64 is TLAST, 65 is TVALID and 66 is
  -- TREADY, so TVALID is bit 1 of the control word of the cond/mask vector.
  constant C_TVALID_BIT  : natural                       := 1;
  constant C_TRIGGER_COND : std_logic_vector(31 downto 0) := x"00000002";
  constant C_TRIGGER_MASK : std_logic_vector(31 downto 0) := x"00000002";

  constant C_AXIL_WORD_BYTES : natural := 4;
  constant C_N_SIGNALS       : natural := 3;
  constant C_PROBE_WIDTH     : natural := C_DATA_WIDTH + C_N_SIGNALS;
  constant C_N_LANES         : natural := integer(ceil(real(C_PROBE_WIDTH) / 32.0));
  -- Matches the DUT's C_AXIL_STRIDE: next power-of-two lane count, minimum 4
  constant C_STRIDE : natural := maximum(4, 2 ** integer(ceil(log2(real(C_N_LANES)))));

  -- The DUT maps the fixed size output block at the base address and the
  -- input block, which grows with C_STRIDE, above it
  constant C_OUTPUT_REG_COUNT : natural := 8;
  constant C_INPUT_REG_COUNT  : natural := 4 + 2 * C_STRIDE;
  constant C_OUTPUT_REG_BASE  : natural := 0;
  constant C_INPUT_REG_BASE   : natural := C_OUTPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE  : natural := (C_OUTPUT_REG_COUNT + C_INPUT_REG_COUNT) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE   : natural := C_STRIDE;

  constant C_TRIG_POS_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_ARM_FT_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_CFG_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 2 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_COND_BASE : natural                       := C_INPUT_REG_BASE + 4 * C_AXIL_WORD_BYTES;
  constant C_TRIG_MASK_BASE : natural                       := C_INPUT_REG_BASE + (4 + C_STRIDE) * C_AXIL_WORD_BYTES;
  -- TLAST/TVALID/TREADY live in the word right above the TDATA words
  constant C_CTRL_WORD_IDX  : natural                       := C_DATA_WIDTH / 32;
  constant C_CTRL_COND_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_COND_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));
  constant C_CTRL_MASK_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_MASK_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));

  constant C_STATUS_ADDR   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_IDX_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 6 * C_AXIL_WORD_BYTES, 32));

  -- trig_cfg for the mode under test. bit0 = 0 keeps the AND reduction, which
  -- with a single enabled bit is the same as OR anyway.
  --   bit1 : 0 = level, 1 = edge
  --   bit2 : 0 = rising, 1 = falling

  pure function mode_cfg (
    m : natural
  ) return std_logic_vector is
  begin

    case m is

      when 0 =>
        return x"00000000";

      when 1 =>
        return x"00000002";

      when others =>
        return x"00000006";

    end case;

  end function mode_cfg;

  -- The probe counter value the triggering sample must carry.
  --
  -- The level run triggers on the first sample the ILA takes, which happens
  -- while the arm is still settling and before the counter loop starts
  -- driving TDATA, so that sample carries 0. The two edge runs trigger on
  -- their transition and carry the loop index of it.

  pure function mode_expect (
    m : natural
  ) return natural is
  begin

    case m is

      when 0 =>
        return 0;

      when 1 =>
        return C_RISE_POINT;

      when others =>
        return C_FALL_POINT;

    end case;

  end function mode_expect;

  -- TVALID as captured in the triggering sample. A falling edge is the only
  -- one of the three that triggers on the condition being false.

  pure function mode_expect_tvalid (
    m : natural
  ) return std_logic is
  begin

    if (m = 2) then
      return '0';
    else
      return '1';
    end if;

  end function mode_expect_tvalid;

  pure function mode_name (
    m : natural
  ) return string is
  begin

    case m is

      when 0 =>
        return "level";

      when 1 =>
        return "rising";

      when others =>
        return "falling";

    end case;

  end function mode_name;

  constant C_TRIG_CFG       : std_logic_vector(31 downto 0) := mode_cfg(C_MODE);
  constant C_EXPECT_SAMPLE  : natural                       := mode_expect(C_MODE);
  constant C_EXPECT_TVALID  : std_logic                     := mode_expect_tvalid(C_MODE);

  -- Every report carries the mode, the three runs of the sweep otherwise
  -- print the same lines and cannot be told apart in the log.
  constant C_TEST_ID : string := "07_sim_edge_test[" & mode_name(C_MODE) & "]";

  signal i_rst_sync  : std_logic := '1';
  signal samp_aclk   : std_logic := '0';
  signal s_axil_aclk : std_logic := '0';

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
    -- back-to-back write.
    wait until rising_edge(clk) and awready = '1' and wready = '1';

    awvalid <= '0';
    wvalid  <= '0';
    bready  <= '1';

    wait until rising_edge(clk) and bvalid = '1';
    bready <= '0';

  end procedure axil_write;

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
      g_external_trig   => 0,
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

    variable trig_slot    : natural;
    variable trig_sample  : natural;
    variable trig_tvalid  : std_logic;

  begin

    assert C_FALL_POINT < C_RISE_POINT and C_RISE_POINT < C_SAMPLE_COUNT
      report C_TEST_ID & ": the TVALID schedule is out of order, fall " &
             integer'image(C_FALL_POINT) & " rise " & integer'image(C_RISE_POINT) &
             " of " & integer'image(C_SAMPLE_COUNT) & " samples"
      severity failure;

    -- The edge runs need enough samples after their transition to fill the
    -- post trigger part of the buffer and reach DONE.
    assert C_SAMPLE_COUNT - C_RISE_POINT > C_SAMP_BUFF_DEPTH
      report C_TEST_ID & ": only " & integer'image(C_SAMPLE_COUNT - C_RISE_POINT) &
             " samples after the rising edge, need more than " &
             integer'image(C_SAMP_BUFF_DEPTH)
      severity failure;

    wait for 40 ns;
    i_rst_sync     <= '0';
    s_axil_aresetn <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_POS_ADDR, std_logic_vector(to_unsigned(C_TRIG_IDX, 32)));

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_CFG_ADDR, C_TRIG_CFG);

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_COND_ADDR, C_TRIGGER_COND);

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_MASK_ADDR, C_TRIGGER_MASK);

    report C_TEST_ID & ": trig_cfg = 0x" & to_hstring(C_TRIG_CFG) &
           ", expecting the trigger on probe counter " & integer'image(C_EXPECT_SAMPLE)
      severity note;

    -- The condition goes true BEFORE the arm. This is the whole point of the
    -- bench: the level run has nothing to wait for, the edge runs do.
    probe_slave_axis_tvalid <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    report C_TEST_ID & ": status after arm = " & integer'image(to_integer(unsigned(status(2 downto 0))))
      severity note;

    for sample_index in 0 to C_SAMPLE_COUNT - 1 loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tdata <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));

      -- High from before the arm, low from C_FALL_POINT, high again from
      -- C_RISE_POINT. One falling and one rising transition, both after arming.
      if (sample_index >= C_FALL_POINT and sample_index < C_RISE_POINT) then
        probe_slave_axis_tvalid <= '0';
      else
        probe_slave_axis_tvalid <= '1';
      end if;

      wait until rising_edge(samp_aclk);

    end loop;

    probe_slave_axis_tvalid  <= '0';
    probe_master_axis_tready <= '1';

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

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_MAGIC_ADDR, read_data);
    assert read_data = x"B01DFACE"
      report C_TEST_ID & ": magic key mismatch"
      severity error;

    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_TRIG_IDX_ADDR, read_data);
    trig_slot := to_integer(unsigned(read_data));
    report C_TEST_ID & ": trig_idx readback, triggering sample sits in buffer slot " & integer'image(trig_slot)
      severity note;

    -- Every slot gets printed, the one the DUT points at gets checked.
    for sample_index in 0 to C_SAMP_BUFF_DEPTH - 1 loop

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

      if (sample_index = trig_slot) then
        trig_sample := to_integer(unsigned(lane_data(0)));
        trig_tvalid := lane_data(C_CTRL_WORD_IDX)(C_TVALID_BIT);
      end if;

      wait until rising_edge(s_axil_aclk);

    end loop;

    -- The check that separates the three modes. A rising run that fired on
    -- the first sample instead of the transition lands on 0 here, which is
    -- exactly what a cleared rather than seeded trig_lvl_prev would do.
    assert trig_sample = C_EXPECT_SAMPLE
      report C_TEST_ID & ": triggered on probe counter " & integer'image(trig_sample) &
             " (buffer slot " & integer'image(trig_slot) & "), expected " &
             integer'image(C_EXPECT_SAMPLE)
      severity error;

    -- A falling edge is the one mode that triggers with the condition false.
    assert trig_tvalid = C_EXPECT_TVALID
      report C_TEST_ID & ": the triggering sample carries TVALID = " &
             std_logic'image(trig_tvalid) & ", expected " &
             std_logic'image(C_EXPECT_TVALID)
      severity error;

    report C_TEST_ID & " SUCCESS: triggered on probe counter " &
           integer'image(trig_sample) & " in buffer slot " &
           integer'image(trig_slot) & ", TVALID = " & std_logic'image(trig_tvalid)
      severity note;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
