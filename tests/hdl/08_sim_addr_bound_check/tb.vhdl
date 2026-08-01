---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Created: 2026-07-31 Fri
--
-- Description: Address decoding at and past the end of the register map.
--
--   The core decodes araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) and
--   nothing else, so an address it cannot serve is truncated rather than
--   rejected and rresp/bresp stay OKAY either way. That leaves three regions
--   the rest of the tests never touch:
--
--     mapped        0 .. C_N_REGS-1            real registers
--     unmapped      C_N_REGS .. slice top      decodable, nothing behind it
--     above         slice top and up           the high bits are dropped, so
--                                              it aliases back onto the map
--
--   This test pins what each of them does. The unmapped region is the
--   interesting one: the range checks in p_wlg/p_rlg are the only thing
--   standing between it and an out of range array index, so a read there has
--   to come back zero and a write there has to change nothing.
--
--   It also pins the output block being read only, which is a property of the
--   map order rather than of any explicit write protection: the block sits
--   below the input one and p_wlg rebases the write index onto the input
--   block, so a write under C_OUTPUT_REG_COUNT falls out of range by
--   construction.
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
  constant C_DEPTH       : natural := 8;
  constant C_AXIS_PERIOD : time    := 10 ns;
  constant C_AXIL_PERIOD : time    := 10 ns;

  -- All post trigger, so the buffer ends up full of stimulus rather than of
  -- whatever the RAM powered up as. The boundary check below needs the last
  -- mapped register to hold something a zero read can be told apart from.
  constant C_TRIG_IDX         : natural := 0;
  constant C_FORCE_TRIG_POINT : natural := 16;
  constant C_SAMPLE_COUNT     : natural := 48;

  -- TREADY/TVALID/TLAST all high. TLAST is never asserted by the stimulus, so
  -- the natural trigger cannot fire and the force trigger is the only way in.
  constant TRIGGER_COND : std_logic_vector(31 downto 0) := x"00000007";
  constant TRIGGER_MASK : std_logic_vector(31 downto 0) := x"00000007";

  constant C_AXIL_WORD_BYTES : natural := 4;
  constant C_N_SIGNALS       : natural := 3;
  constant C_PROBE_WIDTH     : natural := C_DATA_WIDTH + C_N_SIGNALS;
  constant C_N_LANES         : natural := integer(ceil(real(C_PROBE_WIDTH) / 32.0));

  constant C_STRIDE : natural := maximum(4, 2 ** integer(ceil(log2(real(C_N_LANES)))));

  -- The DUT maps the fixed size output block at the base address and the
  -- input block, which grows with C_STRIDE, above it.
  constant C_OUTPUT_REG_COUNT : natural := 8;
  constant C_INPUT_REG_COUNT  : natural := 4 + 2 * C_STRIDE;
  constant C_OUTPUT_REG_BASE  : natural := 0;
  constant C_INPUT_REG_BASE   : natural := C_OUTPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE  : natural := (C_OUTPUT_REG_COUNT + C_INPUT_REG_COUNT) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE    : natural := C_STRIDE;

  constant C_N_CTRL_REGS : natural := C_OUTPUT_REG_COUNT + C_INPUT_REG_COUNT;
  constant C_N_REGS      : natural := C_N_CTRL_REGS + C_STRIDE * C_DEPTH;

  -- Width of the address slice the DUT actually decodes. It sizes
  -- OPT_MEM_ADDR_BITS from the register count rounded up to a power of two, so
  -- the slice reaches past the last register whenever the count is not one
  -- already. Mirrors ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB.
  constant C_ADDR_SLICE_BITS : natural := integer(ceil(log2(real(C_N_REGS))));
  constant C_N_DECODED_REGS  : natural := 2 ** C_ADDR_SLICE_BITS;

  -- Input block, indices relative to C_INPUT_REG_BASE: 0=trig pos, 1=ARM_FT,
  -- 2=trig cfg (AND/OR), 3=reserved,
  -- 4..4+a-1=trig vector cond, 4+a..4+2a-1=trig vector mask (a = C_STRIDE)
  constant C_TRIG_POS_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_ARM_FT_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_CFG_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 2 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_COND_BASE : natural                       := C_INPUT_REG_BASE + 4 * C_AXIL_WORD_BYTES;
  constant C_TRIG_MASK_BASE : natural                       := C_INPUT_REG_BASE + (4 + C_STRIDE) * C_AXIL_WORD_BYTES;
  -- TLAST/TVALID/TREADY live in the word right above the TDATA words
  constant C_CTRL_WORD_IDX  : natural                       := C_DATA_WIDTH / 32;
  constant C_CTRL_COND_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_COND_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));
  constant C_CTRL_MASK_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_MASK_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));

  constant C_STATUS_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));

  -- Lane 0 of the newest sample, the last register of the map that carries
  -- probe bits rather than stride padding.
  constant C_LAST_SAMPLE_ADDR : std_logic_vector(31 downto 0) :=
    std_logic_vector(to_unsigned(C_SAMPLE_RAM_BASE + (C_DEPTH - 1) * C_SAMPLE_STRIDE * C_AXIL_WORD_BYTES, 32));

  -- One register past the map, still inside the decoded slice
  constant C_UNMAPPED_ADDR : std_logic_vector(31 downto 0) :=
    std_logic_vector(to_unsigned(C_N_REGS * C_AXIL_WORD_BYTES, 32));

  -- First address whose index no longer fits the slice, so the DUT drops the
  -- bit that carries it and serves register 0 instead.
  constant C_ALIAS_ADDR : std_logic_vector(31 downto 0) :=
    std_logic_vector(to_unsigned(C_N_DECODED_REGS * C_AXIL_WORD_BYTES, 32));

  constant C_POISON  : std_logic_vector(31 downto 0) := x"DEADBEEF";
  constant C_TEST_ID : string                        := "08_sim_addr_bound_check";

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

  -- The unmapped region only exists because the register count is not a power
  -- of two. If it ever becomes one there is no gap left between the last
  -- register and the top of the decoded slice, and everything below would pass
  -- while checking nothing at all.
  assert C_N_REGS < C_N_DECODED_REGS
    report C_TEST_ID & ": the map fills the decoded address slice exactly ("
           & integer'image(C_N_REGS) & " registers), there is no unmapped "
           & "region left to test, pick a different C_DEPTH"
    severity failure;

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

    type t_reg_data is array (natural range <>) of std_logic_vector(31 downto 0);

    variable read_data : std_logic_vector(31 downto 0);
    variable status    : std_logic_vector(31 downto 0);
    variable snapshot  : t_reg_data(0 to C_N_CTRL_REGS - 1);
    variable addr      : std_logic_vector(31 downto 0);

  begin

    report C_TEST_ID & ": map is " & integer'image(C_N_REGS) & " registers, the "
           & "decoder reaches " & integer'image(C_N_DECODED_REGS) & ", so "
           & integer'image(C_N_DECODED_REGS - C_N_REGS) & " unmapped registers "
           & "sit between them"
      severity note;

    wait for 40 ns;
    i_rst_sync     <= '0';
    s_axil_aresetn <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- STEP 1: fill the buffer, so the last mapped register holds a value a
    -- zero read can be told apart from ------------------------------------
    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_POS_ADDR, std_logic_vector(to_unsigned(C_TRIG_IDX, 32)));

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_CFG_ADDR, x"00000000");

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_COND_ADDR, TRIGGER_COND);

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_MASK_ADDR, TRIGGER_MASK);

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    -- Counting from one, so no captured sample reads back as the zero an
    -- unmapped register would give
    for sample_index in 1 to C_SAMPLE_COUNT loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tvalid  <= '1';
      probe_slave_axis_tlast   <= '0';
      probe_slave_axis_tdata   <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));
      probe_master_axis_tready <= '1';

      if (sample_index = C_FORCE_TRIG_POINT) then
        axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");
      end if;

      wait until rising_edge(samp_aclk);

    end loop;

    probe_slave_axis_tvalid <= '0';

    for attempt in 0 to 511 loop

      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
      exit when status(2) = '1';

    end loop;

    assert status(2) = '1'
      report C_TEST_ID & ": the ILA never reached DONE, the checks below need a "
             & "settled core"
      severity failure;

    -- STEP 2: the boundary between the last mapped register and the first
    -- unmapped one ---------------------------------------------------------
    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_LAST_SAMPLE_ADDR, read_data);

    report C_TEST_ID & ": last mapped sample word at 0x" & to_hstring(C_LAST_SAMPLE_ADDR)
           & " reads 0x" & to_hstring(read_data)
      severity note;

    assert read_data /= x"00000000"
      report C_TEST_ID & ": the last mapped sample word reads back as zero, so "
             & "the check below cannot tell a served register from an unmapped one"
      severity failure;

    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_UNMAPPED_ADDR, read_data);

    assert read_data = x"00000000"
      report C_TEST_ID & ": the register right past the map at 0x"
             & to_hstring(C_UNMAPPED_ADDR) & " reads 0x" & to_hstring(read_data)
             & ", expected zero"
      severity failure;

    -- STEP 3: every unmapped register reads zero ---------------------------
    -- This is what the range check in p_rlg is for. Without it the decoded
    -- index runs off the end of the register arrays instead, which is a bound
    -- check failure rather than a zero.
    for reg_index in C_N_REGS to C_N_DECODED_REGS - 1 loop

      addr := std_logic_vector(to_unsigned(reg_index * C_AXIL_WORD_BYTES, 32));

      wait until rising_edge(s_axil_aclk);
      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, addr, read_data);

      assert read_data = x"00000000"
        report C_TEST_ID & ": unmapped register " & integer'image(reg_index)
               & " at 0x" & to_hstring(addr) & " reads 0x" & to_hstring(read_data)
               & ", expected zero"
        severity failure;

    end loop;

    report C_TEST_ID & ": all " & integer'image(C_N_DECODED_REGS - C_N_REGS)
           & " unmapped registers read back zero"
      severity note;

    -- STEP 4: snapshot the whole control block -----------------------------
    -- The ILA is DONE and its write enable is low, so trig_idx and the write
    -- pointer are frozen and every one of these is stable for the rest of the
    -- run. Anything that moves from here on was moved by a write that should
    -- not have landed.
    for reg_index in 0 to C_N_CTRL_REGS - 1 loop

      addr := std_logic_vector(to_unsigned(reg_index * C_AXIL_WORD_BYTES, 32));

      wait until rising_edge(s_axil_aclk);
      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, addr, snapshot(reg_index));

    end loop;

    -- STEP 5: writes past the map change nothing ---------------------------
    for reg_index in C_N_REGS to C_N_DECODED_REGS - 1 loop

      addr := std_logic_vector(to_unsigned(reg_index * C_AXIL_WORD_BYTES, 32));

      wait until rising_edge(s_axil_aclk);
      axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, addr, C_POISON);

    end loop;

    -- STEP 6: writes into the read only output block change nothing --------
    -- ARM_FT is the one that matters here. It is the second register of the
    -- input block, so under the old map order it sat at index 1 and a write
    -- aimed at what is now the magic key would have armed the ILA.
    for reg_index in 0 to C_OUTPUT_REG_COUNT - 1 loop

      addr := std_logic_vector(to_unsigned(reg_index * C_AXIL_WORD_BYTES, 32));

      wait until rising_edge(s_axil_aclk);
      axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, addr, C_POISON);

    end loop;

    for settle_index in 1 to 8 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- STEP 7: the control block is exactly as it was -----------------------
    for reg_index in 0 to C_N_CTRL_REGS - 1 loop

      addr := std_logic_vector(to_unsigned(reg_index * C_AXIL_WORD_BYTES, 32));

      wait until rising_edge(s_axil_aclk);
      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, addr, read_data);

      assert read_data = snapshot(reg_index)
        report C_TEST_ID & ": control register " & integer'image(reg_index)
               & " at 0x" & to_hstring(addr) & " moved from 0x"
               & to_hstring(snapshot(reg_index)) & " to 0x" & to_hstring(read_data)
               & " after writes that should all have been dropped"
        severity failure;

    end loop;

    -- The magic key doubles as a check that the output block is still being
    -- served from the constants rather than from anything the writes left
    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_MAGIC_ADDR, read_data);

    assert read_data = x"B01DFACE"
      report C_TEST_ID & ": the magic key reads 0x" & to_hstring(read_data)
             & " after a write to it, the output block is not read only"
      severity failure;

    -- The ILA has to still be DONE. An arm would have cleared it, which is
    -- what a stray write landing on ARM_FT looks like from out here.
    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);

    assert status(2) = '1'
      report C_TEST_ID & ": status is 0x" & to_hstring(status)
             & " after the dropped writes, the ILA left DONE so one of them "
             & "reached ARM_FT"
      severity failure;

    -- STEP 8: past the decoded slice the address aliases back ---------------
    -- Not a guarantee worth relying on, it is what truncating instead of
    -- rejecting comes to. Stated here so a change to the decoder shows up as a
    -- failing test rather than as a driver quietly reading the wrong register.
    wait until rising_edge(s_axil_aclk);
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_ALIAS_ADDR, read_data);

    assert read_data = snapshot(0)
      report C_TEST_ID & ": 0x" & to_hstring(C_ALIAS_ADDR) & " reads 0x"
             & to_hstring(read_data) & ", expected it to alias onto register 0 "
             & "and give 0x" & to_hstring(snapshot(0))
      severity failure;

    report C_TEST_ID & " SUCCESS: reads past the map return zero, writes past it "
           & "and into the output block are dropped, and 0x"
           & to_hstring(C_ALIAS_ADDR) & " aliases onto register 0"
      severity note;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
