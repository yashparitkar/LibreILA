---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Created: 2026-08-04 Tue
--
-- Description: Test the ILA disarm path via the DISARM register (input
--   index 3, 0x2C). Disarm has to take a capture back from both sides of
--   the trigger and leave a finished one alone, so this walks the four
--   states in the order that keeps every arm coming out of ILA_IDLE:
--
--     A  armed, no trigger yet   -> disarm returns to idle, and the
--                                   trigger condition is then ignored
--     B  triggered, counting     -> disarm aborts, DONE never arrives
--     C  a clean capture after   -> the path still works once disarmed
--     D  done                    -> disarm is ignored, the capture stays
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

  constant C_DATA_WIDTH  : natural := 64;
  -- Deep enough that the post trigger countdown outlasts an AXI4Lite write.
  -- A trigger position of zero leaves the whole buffer for post trigger
  -- samples, so ILA_TRIGD lasts C_DEPTH-1 sampling clocks and there is room
  -- to catch the state and disarm out of it. That is what phases A and B want.
  constant C_DEPTH        : natural := 64;
  constant C_TRIG_POS     : natural := 0;
  -- Phase C reads the trigger sample back instead, so it wants the opposite:
  -- few enough post trigger samples that the run does not wrap the buffer and
  -- overwrite the slot trig_idx names.
  constant C_TRIG_POS_LATE : natural := C_DEPTH - 8;
  constant C_AXIS_PERIOD   : time    := 10 ns;
  constant C_AXIL_PERIOD   : time    := 10 ns;

  -- TREADY=1, TVALID=1, TLAST=1, the same condition every other axil test uses
  constant TRIGGER_COND : std_logic_vector(31 downto 0) := x"00000007";
  constant TRIGGER_MASK : std_logic_vector(31 downto 0) := x"00000007";

  constant C_AXIL_WORD_BYTES : natural := 4;
  constant C_N_SIGNALS       : natural := 3;
  constant C_PROBE_WIDTH     : natural := C_DATA_WIDTH + C_N_SIGNALS;
  constant C_N_LANES         : natural := integer(ceil(real(C_PROBE_WIDTH) / 32.0));
  -- Matches the DUT's C_AXIL_STRIDE: next power-of-two lane count, minimum 4
  constant C_STRIDE          : natural := maximum(4, 2 ** integer(ceil(log2(real(C_N_LANES)))));

  constant C_OUTPUT_REG_COUNT : natural := 8;
  constant C_INPUT_REG_COUNT  : natural := 4 + 2 * C_STRIDE;
  constant C_OUTPUT_REG_BASE  : natural := 0;
  constant C_INPUT_REG_BASE   : natural := C_OUTPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE  : natural := (C_OUTPUT_REG_COUNT + C_INPUT_REG_COUNT) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE    : natural := C_STRIDE;

  -- Input block, indices relative to C_INPUT_REG_BASE: 0=trig pos, 1=ARM_FT,
  -- 2=trig cfg (AND/OR), 3=DISARM,
  -- 4..4+a-1=trig vector cond, 4+a..4+2a-1=trig vector mask (a = C_STRIDE)
  constant C_TRIG_POS_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_ARM_FT_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_CFG_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 2 * C_AXIL_WORD_BYTES, 32));
  constant C_DISARM_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 3 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_COND_BASE : natural                       := C_INPUT_REG_BASE + 4 * C_AXIL_WORD_BYTES;
  constant C_TRIG_MASK_BASE : natural                       := C_INPUT_REG_BASE + (4 + C_STRIDE) * C_AXIL_WORD_BYTES;
  -- TLAST/TVALID/TREADY live in the word right above the TDATA words
  constant C_CTRL_WORD_IDX  : natural                       := C_DATA_WIDTH / 32;
  constant C_CTRL_COND_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_COND_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));
  constant C_CTRL_MASK_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_MASK_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));

  constant C_STATUS_ADDR   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_IDX_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 6 * C_AXIL_WORD_BYTES, 32));

  -- The probe counter value carried by the sample that fires the trigger in
  -- phases B and C. Both sit well inside their streaming loop so the sample
  -- either side of them is a non trigger one.
  constant C_TRIG_POINT_B : natural := 24;
  constant C_TRIG_POINT_C : natural := 32;

  signal i_rst_sync   : std_logic := '1';
  signal samp_aclk    : std_logic := '0';
  signal s_axil_aclk  : std_logic := '0';

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

    -- One idle cycle first, so a transaction issued straight after another one
    -- starts from a settled write channel. This test issues far more back to
    -- back traffic than the others, and the sequencing matters here: an arm
    -- that gets decoded twice is a forced trigger, not an arm.
    wait until rising_edge(clk);

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

    -- Always give the address a clock edge to take effect. Sampling rdata on
    -- an RVALID left over from the previous read hands back the previous
    -- register, which is the sort of thing this test would then blame on the
    -- disarm.
    loop

      wait until rising_edge(clk);
      exit when rvalid = '1';

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
      g_samp_buff_depth => C_DEPTH
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

    variable read_data    : std_logic_vector(31 downto 0);
    variable status       : std_logic_vector(31 downto 0);
    variable trig_idx     : std_logic_vector(31 downto 0);
    variable trig_idx_was : std_logic_vector(31 downto 0);
    variable trig_sample  : integer := -1;

  begin

    wait for 40 ns;
    i_rst_sync     <= '0';
    s_axil_aresetn <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- The whole buffer goes to post trigger samples, so ILA_TRIGD is long
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_POS_ADDR, std_logic_vector(to_unsigned(C_TRIG_POS, 32)));

    -- AND mode, level sensitive
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_CFG_ADDR, x"00000000");

    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_COND_ADDR, TRIGGER_COND);

    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_MASK_ADDR, TRIGGER_MASK);

    probe_master_axis_tready <= '1';
    probe_slave_axis_tvalid  <= '1';
    probe_slave_axis_tlast   <= '0';

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_MAGIC_ADDR, read_data);
    assert read_data = x"B01DFACE"
      report "09_sim_axil_disarm: magic key mismatch"
      severity error;

    ------------------------------------------------------------------
    -- PHASE A: disarm out of ILA_ARMED, before any trigger
    ------------------------------------------------------------------
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(0) = '1'
      report "09_sim_axil_disarm[A]: ILA failed to ARM, status = 0x" & to_hstring(status)
      severity error;

    -- Stream a while with the condition false, so the ILA is sitting in
    -- ILA_ARMED waiting rather than part way through a capture
    for sample_index in 0 to 15 loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tdata <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));
      probe_slave_axis_tlast <= '0';
      wait until rising_edge(samp_aclk);

    end loop;

    report "09_sim_axil_disarm[A]: *** DISARM while armed and untriggered ***"
      severity note;
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_DISARM_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(2 downto 0) = "000"
      report "09_sim_axil_disarm[A]: disarm left the ILA out of idle, status = 0x" & to_hstring(status)
      severity error;

    -- And the state really is idle rather than merely not armed: the trigger
    -- condition now goes by without being taken
    for sample_index in 0 to 31 loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tdata <= std_logic_vector(to_unsigned(100 + sample_index, C_DATA_WIDTH));
      probe_slave_axis_tlast <= '1';
      wait until rising_edge(samp_aclk);

    end loop;

    probe_slave_axis_tlast <= '0';

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(2 downto 0) = "000"
      report "09_sim_axil_disarm[A]: a disarmed ILA took the trigger, status = 0x" & to_hstring(status)
      severity error;

    report "09_sim_axil_disarm[A]: disarm from ILA_ARMED returned to idle and the trigger is ignored there"
      severity note;

    ------------------------------------------------------------------
    -- PHASE B: disarm out of ILA_TRIGD, after the trigger has fired
    ------------------------------------------------------------------
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(0) = '1'
      report "09_sim_axil_disarm[B]: ILA failed to re-ARM after a disarm, status = 0x" & to_hstring(status)
      severity error;

    for sample_index in 0 to C_TRIG_POINT_B + 3 loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tdata <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));

      if (sample_index = C_TRIG_POINT_B) then
        probe_slave_axis_tlast <= '1';
      else
        probe_slave_axis_tlast <= '0';
      end if;

      wait until rising_edge(samp_aclk);

    end loop;

    -- Caught part way through the post trigger countdown, which is what makes
    -- this a different branch of the state machine from phase A
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(1) = '1' and status(2) = '0'
      report "09_sim_axil_disarm[B]: expected ILA_TRIGD before the disarm, status = 0x" & to_hstring(status)
      severity error;

    report "09_sim_axil_disarm[B]: *** DISARM while triggered and counting ***"
      severity note;
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_DISARM_ADDR, x"00000001");

    -- Well past the C_DEPTH-1 post trigger samples the capture had left, so a
    -- disarm that only stopped the ILA reaching ILA_DONE late would still show
    for settle_index in 1 to 4 * C_DEPTH loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(2 downto 0) = "000"
      report "09_sim_axil_disarm[B]: the aborted capture completed anyway, status = 0x" & to_hstring(status)
      severity error;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_TRIG_IDX_ADDR, trig_idx);
    assert trig_idx = x"00000000"
      report "09_sim_axil_disarm[B]: an aborted capture left a trigger index behind, 0x" & to_hstring(trig_idx)
      severity error;

    report "09_sim_axil_disarm[B]: disarm from ILA_TRIGD aborted the capture and cleared the trigger index"
      severity note;

    ------------------------------------------------------------------
    -- PHASE C: a clean capture still works after two disarms
    ------------------------------------------------------------------
    -- Most of the buffer to pre trigger samples now, so the trigger slot is
    -- still the trigger sample by the time the capture stops
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_POS_ADDR, std_logic_vector(to_unsigned(C_TRIG_POS_LATE, 32)));

    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- The arm must not have carried a trigger with it, or the sample the test
    -- reads back below would be whatever was live at arm time
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(0) = '1' and status(1) = '0' and status(2) = '0'
      report "09_sim_axil_disarm[C]: expected a plain ARMED after the arm, status = 0x" & to_hstring(status)
      severity error;

    -- One uninterrupted stream, no AXI traffic in the loop, so the sample the
    -- DUT names in trig_idx is the one carrying C_TRIG_POINT_C exactly
    for sample_index in 0 to 2 * C_DEPTH loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tdata <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));

      if (sample_index = C_TRIG_POINT_C) then
        probe_slave_axis_tlast <= '1';
      else
        probe_slave_axis_tlast <= '0';
      end if;

      wait until rising_edge(samp_aclk);

    end loop;

    probe_slave_axis_tvalid <= '0';
    probe_slave_axis_tlast  <= '0';

    for attempt in 0 to 511 loop

      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
      exit when status(2) = '1';

    end loop;

    assert status(2) = '1'
      report "09_sim_axil_disarm[C]: DONE never arrived on the capture after the disarms, status = 0x" & to_hstring(status)
      severity error;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_TRIG_IDX_ADDR, trig_idx);

    axil_read(
              s_axil_aclk,
              s_axil_araddr,
              s_axil_arvalid,
              s_axil_rready,
              s_axil_rdata,
              s_axil_rvalid,
              std_logic_vector(to_unsigned(C_SAMPLE_RAM_BASE + to_integer(unsigned(trig_idx)) * C_SAMPLE_STRIDE * C_AXIL_WORD_BYTES, 32)),
              read_data
            );
    trig_sample := to_integer(unsigned(read_data));

    assert trig_sample = C_TRIG_POINT_C
      report "09_sim_axil_disarm[C]: trigger sample carries " & integer'image(trig_sample) &
             ", expected " & integer'image(C_TRIG_POINT_C)
      severity error;

    report "09_sim_axil_disarm[C]: capture after the disarms completed, trigger sample " &
           integer'image(trig_sample) & " at buffer slot " & integer'image(to_integer(unsigned(trig_idx)))
      severity note;

    ------------------------------------------------------------------
    -- PHASE D: a finished capture is not thrown away by a disarm
    ------------------------------------------------------------------
    trig_idx_was := trig_idx;

    report "09_sim_axil_disarm[D]: *** DISARM while done, expected to be ignored ***"
      severity note;
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_DISARM_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    assert status(2) = '1'
      report "09_sim_axil_disarm[D]: a disarm discarded a finished capture, status = 0x" & to_hstring(status)
      severity error;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_TRIG_IDX_ADDR, trig_idx);
    assert trig_idx = trig_idx_was
      report "09_sim_axil_disarm[D]: a disarm moved the trigger index of a finished capture, 0x" &
             to_hstring(trig_idx_was) & " -> 0x" & to_hstring(trig_idx)
      severity error;

    axil_read(
              s_axil_aclk,
              s_axil_araddr,
              s_axil_arvalid,
              s_axil_rready,
              s_axil_rdata,
              s_axil_rvalid,
              std_logic_vector(to_unsigned(C_SAMPLE_RAM_BASE + to_integer(unsigned(trig_idx)) * C_SAMPLE_STRIDE * C_AXIL_WORD_BYTES, 32)),
              read_data
            );

    assert to_integer(unsigned(read_data)) = C_TRIG_POINT_C
      report "09_sim_axil_disarm[D]: the finished capture moved under a disarm, trigger sample now " &
             integer'image(to_integer(unsigned(read_data)))
      severity error;

    report "09_sim_axil_disarm SUCCESS: disarm takes a capture back from ILA_ARMED and from ILA_TRIGD, " &
           "leaves a finished one alone, and arming still works after each one"
      severity note;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
