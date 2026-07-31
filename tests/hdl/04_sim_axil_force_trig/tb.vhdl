---------------------------------------------------------------------
-- File: tb.vhdl
-- Author: Y.U.P.
-- Created: 2026-07-22 Wed 19:20
-- Last Modified: 2026-07-31 Fri 11:19
--
-- Description: Test the ILA Force Trigger functionality via Arm_FT (0x04)
--   when armed prior to the condition-based trigger.
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

  constant C_DATA_WIDTH       : natural := 64;
  constant C_DEPTH            : natural := 8;
  constant C_AXIS_PERIOD      : time    := 10 ns;
  constant C_AXIL_PERIOD      : time    := 10 ns;
  constant C_TRIG_IDX         : natural := 3;
  constant C_FORCE_TRIG_POINT : natural := 20;  -- Force trigger injected here
  constant C_TRIGGER_POINT    : natural := 100; -- Natural trigger condition (TLAST=1)
  constant C_SAMPLE_COUNT     : natural := 192;

  -- Fixed explicit range definitions to prevent vector slicing errors
  constant TRIGGER_COND : std_logic_vector(31 downto 0) := x"00000007"; -- TREADY=1, TVALID=1, TLAST=1
  constant TRIGGER_MASK : std_logic_vector(31 downto 0) := x"00000007";

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
  constant C_STRIDE          : natural := maximum(4, 2 ** integer(ceil(log2(real(C_N_LANES)))));
  -- The DUT maps the fixed size output block at the base address and the
  -- input block, which grows with C_STRIDE, above it
  constant C_OUTPUT_REG_COUNT : natural := 8;
  constant C_INPUT_REG_COUNT  : natural := 4 + 2 * C_STRIDE;
  constant C_OUTPUT_REG_BASE  : natural := 0;
  constant C_INPUT_REG_BASE   : natural := C_OUTPUT_REG_COUNT * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_RAM_BASE  : natural := (C_OUTPUT_REG_COUNT + C_INPUT_REG_COUNT) * C_AXIL_WORD_BYTES;
  constant C_SAMPLE_STRIDE   : natural := C_STRIDE;

  -- Input block, indices relative to C_INPUT_REG_BASE: 0=trig pos, 1=ARM_FT,
  -- 2=trig cfg (AND/OR), 3=reserved,
  -- 4..4+a-1=trig vector cond, 4+a..4+2a-1=trig vector mask (a = C_STRIDE)
  constant C_TRIG_POS_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_ARM_FT_ADDR    : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_CFG_ADDR  : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_INPUT_REG_BASE + 2 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_COND_BASE : natural                       := C_INPUT_REG_BASE + 4 * C_AXIL_WORD_BYTES;
  constant C_TRIG_MASK_BASE : natural                       := C_INPUT_REG_BASE + (4 + C_STRIDE) * C_AXIL_WORD_BYTES;
  -- TLAST/TVALID/TREADY live in the word right above the TDATA words, matching
  -- the w_wr_data bit layout the DUT merges the trigger vector against.
  constant C_CTRL_WORD_IDX  : natural                       := C_DATA_WIDTH / 32;
  constant C_CTRL_COND_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_COND_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));
  constant C_CTRL_MASK_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_TRIG_MASK_BASE + C_CTRL_WORD_IDX * C_AXIL_WORD_BYTES, 32));

  constant C_SAMPLE_PRINT_COUNT : natural                       := C_DEPTH;
  constant C_STATUS_ADDR        : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 0 * C_AXIL_WORD_BYTES, 32));
  constant C_MAGIC_ADDR         : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 1 * C_AXIL_WORD_BYTES, 32));
  constant C_TRIG_IDX_ADDR      : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(C_OUTPUT_REG_BASE + 6 * C_AXIL_WORD_BYTES, 32));

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

    variable read_data         : std_logic_vector(31 downto 0);
    variable status            : std_logic_vector(31 downto 0);
    variable captured_trig_val : integer := -1;

    type t_lane_data is array (natural range <>) of std_logic_vector(31 downto 0);

    variable lane_data : t_lane_data(0 to C_N_LANES - 1);

  begin

    wait for 40 ns;
    i_rst_sync     <= '0';
    s_axil_aresetn <= '1';

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- Configure trigger position index
    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_POS_ADDR, std_logic_vector(to_unsigned(C_TRIG_IDX, 32)));

    -- AND mode: trigger only once every enabled (mask=1) bit matches
    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_TRIG_CFG_ADDR, x"00000000");

    -- Set natural trigger condition to TLAST=1 & TVALID=1 & TREADY=1
    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_COND_ADDR, TRIGGER_COND);

    wait until rising_edge(s_axil_aclk);
    axil_write(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_CTRL_MASK_ADDR, TRIGGER_MASK);

    for settle_index in 1 to 4 loop

      wait until rising_edge(samp_aclk);

    end loop;

    -- STEP 1: First write to Arm_FT -> ARMS the ILA
    axil_arm(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");

    for settle_index in 1 to 16 loop

      wait until rising_edge(samp_aclk);

    end loop;

    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
    report "04_sim_force_trig: Status after initial ARM = 0x" & to_hstring(status)
      severity note;
    assert status(0) = '1'
      report "04_sim_force_trig: ILA failed to ARM"
      severity error;

    -- STEP 2: Stream samples and issue FORCE TRIGGER (before natural trigger at sample)
    for sample_index in 0 to C_SAMPLE_COUNT - 1 loop

      wait until falling_edge(samp_aclk);
      probe_slave_axis_tvalid <= '1';
      probe_slave_axis_tdata  <= std_logic_vector(to_unsigned(sample_index, C_DATA_WIDTH));

      -- Natural condition occurs ONLY at sample 80
      if (sample_index = C_TRIGGER_POINT) then
        probe_slave_axis_tlast <= '1';
      else
        probe_slave_axis_tlast <= '0';
      end if;

      probe_master_axis_tready <= '1';
      i_ext_trig      <= '0';

      -- Inject FORCE TRIGGER write to Arm_FT (0x04) when sample_index matches C_FORCE_TRIG_POINT
      if (sample_index = C_FORCE_TRIG_POINT) then
        report "04_sim_force_trig: *** Issuing FORCE TRIGGER via Arm_FT write at sample " & integer'image(sample_index) & " ***"
          severity note;
        axil_arm(s_axil_aclk, s_axil_awaddr, s_axil_awvalid, s_axil_wdata, s_axil_wvalid, s_axil_bready, s_axil_bvalid, s_axil_awready, s_axil_wready, C_ARM_FT_ADDR, x"00000001");
      end if;

      wait until rising_edge(samp_aclk);

    end loop;

    i_ext_trig      <= '0';
    probe_slave_axis_tvalid  <= '0';
    probe_slave_axis_tlast   <= '0';
    probe_master_axis_tready <= '1';

    -- STEP 3: Wait for DONE status bit
    for attempt in 0 to 511 loop

      axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_STATUS_ADDR, status);
      exit when status(2) = '1';

    end loop;

    assert status(2) = '1'
      report "04_sim_force_trig: DONE did not assert after force trigger"
      severity error;

    for settle_index in 1 to 4 loop

      wait until rising_edge(s_axil_aclk);

    end loop;

    -- Verify Magic Key
    axil_read(s_axil_aclk, s_axil_araddr, s_axil_arvalid, s_axil_rready, s_axil_rdata, s_axil_rvalid, C_MAGIC_ADDR, read_data);
    assert read_data = x"B01DFACE"
      report "04_sim_force_trig: magic key mismatch"
      severity error;

    -- STEP 4: Read buffer RAM and verify force trigger index
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

      if (sample_index = C_TRIG_IDX) then
        captured_trig_val := to_integer(unsigned(lane_data(0)));
      end if;

      report "04_sim_force_trig: sample " & integer'image(sample_index) &
             " | lane2=0x" & to_hstring(lane_data(2)) &
             " | lane1=0x" & to_hstring(lane_data(1)) &
             " | lane0=0x" & to_hstring(lane_data(0))
        severity note;

      wait until rising_edge(s_axil_aclk);

    end loop;

    -- STEP 5: Confirm captured trigger data reflects Force Trigger (~sample 30-34), NOT natural trigger (sample 80)
    assert captured_trig_val >= C_FORCE_TRIG_POINT and captured_trig_val < C_TRIGGER_POINT
      report "04_sim_force_trig FAILURE: Trigger occurred at sample " & integer'image(captured_trig_val) &
             ", expected near Force Trigger point (" & integer'image(C_FORCE_TRIG_POINT) & ")"
      severity error;

    report "04_sim_force_trig SUCCESS: Force Trigger took effect at sample " & integer'image(captured_trig_val) &
           " (well before condition match at sample " & integer'image(C_TRIGGER_POINT) & ")."
      severity note;

    std.env.stop;
    wait;

  end process p_stimulus;

end architecture sim;
