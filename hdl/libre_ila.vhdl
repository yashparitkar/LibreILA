-------------------------------------------------------------------------------
-- File: libre_ila.vhdl
-- Author: Y.U.P. (yashparitkar)
-- Created: 2026-07-14 Tue 11:11
-- Last Modified: 2026-08-07 Fri 17:50
--
-- Description: A generic ILA, the probe is described by codegen/portmap.csv
-- Usage:
--   * The probe ports are pass through ports which are probed and saved
--     to a buffer. probe_slave_* faces the master of the probed link,
--     probe_master_* faces its slave.
--   * Configure the trigger and arm using the AXI4Lite port
--   * The buffer is read back using AXI4Lite port
--   * The data can be read back using the C driver provided
--
-- Copyright 2026 Yash Paritkar
-- SPDX-License-Identifier: CERN-OHL-P-2.0
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity libre_ila is
  generic (
    -- Clock speed of the sampling (probe) domain, used in plotting
    G_SAMP_CLK_FREQ   : integer := 100000000;
    G_AXIL_CLK_FREQ   : integer := 100000000;
    G_EXTERNAL_TRIG   : integer := 0;    -- 1 for external trigger pin
    G_PROBE_WIDTH     : natural := 67;
    G_SAMP_BUFF_DEPTH : natural := 2048; -- Keep it a power of two

    -- Identity of this instance, read back at UID. MGCKEY is the fixed constant
    -- that says "this is a LibreILA", this one says which one, so several cores
    -- in the same system can be told apart. Zero means unset.
    G_UID : natural := 0;

    C_S_AXIL_DATA_WIDTH : integer := 32; -- DONT CHANGE
    C_S_AXIL_ADDR_WIDTH : integer := 32  -- DONT CHANGE
  );
  port (
    i_rst_sync : in    std_logic;

    -- Sampling clock, the clock of the domain the probe lives in
    samp_aclk : in    std_logic;

    -- External tigger
    i_ext_trig : in    std_logic;
    o_trig_out : out   std_logic;

    -- Probe Slave ^^DI ---------------------------------------------
    -- Faces the master of the probed link, so it carries the port
    -- directions of that link's slave.
    -----------------------------------------------------------------

    -- Probe Master ^^DO --------------------------------------------
    -- Faces the slave of the probed link, every direction mirrored.
    -----------------------------------------------------------------

    -- AXI4Lite slave port
    s_axil_aclk    : in    std_logic;
    s_axil_aresetn : in    std_logic;
    s_axil_awaddr  : in    std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
    s_axil_awprot  : in    std_logic_vector(2 downto 0);
    s_axil_awvalid : in    std_logic;
    s_axil_awready : out   std_logic;
    s_axil_wdata   : in    std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
    s_axil_wstrb   : in    std_logic_vector((C_S_AXIL_DATA_WIDTH / 8) - 1 downto 0);
    s_axil_wvalid  : in    std_logic;
    s_axil_wready  : out   std_logic;
    s_axil_bresp   : out   std_logic_vector(1 downto 0);
    s_axil_bvalid  : out   std_logic;
    s_axil_bready  : in    std_logic;
    s_axil_araddr  : in    std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
    s_axil_arprot  : in    std_logic_vector(2 downto 0);
    s_axil_arvalid : in    std_logic;
    s_axil_arready : out   std_logic;
    s_axil_rdata   : out   std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
    s_axil_rresp   : out   std_logic_vector(1 downto 0);
    s_axil_rvalid  : out   std_logic;
    s_axil_rready  : in    std_logic
  );
end entity libre_ila;

architecture rtl of libre_ila is

  -- Fixing the width of the AXILite bus ----------------------------
  -------------------------------------------------------------------

  -- Making of the RAM buffer ---------------------------------------
  -- The RAM multilane with each lane of C_S_AXIL_DATA_WIDTH for easier
  -- muxing later
  constant C_ADDR_WIDTH : integer := integer(ceil(log2(real(G_SAMP_BUFF_DEPTH))));

  -- Registers one sample takes, the probe word packed 32 bits at a time
  constant C_N_LANES : integer := integer(ceil(real(G_PROBE_WIDTH) / real(C_S_AXIL_DATA_WIDTH)));

  -- Function for stride length calculation -------------------------

  pure function get_stride (
    lanes : integer
  ) return integer is

    variable calc_stride : integer;

  begin

    calc_stride := 1;

    -- Find the next power of two
    while calc_stride < lanes loop

      calc_stride := calc_stride * 2;

    end loop;

    -- Enforce the minimum stride of 4 for control registers
    if (calc_stride < 4) then
      return 4;
    else
      return calc_stride;
    end if;

  end function get_stride;

  -- Power of two check for G_SAMP_BUFF_DEPTH -----------------------
  -- G_SAMP_BUFF_DEPTH must be a power of two, r_wr_idx is a C_ADDR_WIDTH counter that
  -- wraps on 2**C_ADDR_WIDTH. Any other depth leaves the buffer tail
  -- unreachable and breaks the modular arithmetic in post_trig_samp_tgt.

  pure function is_power_of_two (
    val : natural
  ) return boolean is

    variable pow : natural;

  begin

    pow := 1;

    while pow < val loop

      pow := pow * 2;

    end loop;

    return (pow = val);

  end function is_power_of_two;

  -- Automatically scales based on G_PROBE_WIDTH
  constant C_AXIL_STRIDE : integer := get_stride(C_N_LANES);
  -------------------------------------------------------------------

  type t_lane is array (0 to G_SAMP_BUFF_DEPTH - 1) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  type t_lane_rd_arr is array (0 to C_N_LANES - 1) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  attribute syn_ramstyle : string;

  -- Shared read-address decode for the sample buffer, combinational, fans
  -- out to every lane in g_samp_lanes. r_intra_stride_idx trails it by one
  -- cycle so it lands together with lane_rd_data once that's registered.
  signal w_rd_hit           : std_logic;
  signal w_stride_idx       : integer range 0 to G_SAMP_BUFF_DEPTH - 1;
  signal w_intra_stride_idx : integer range 0 to C_AXIL_STRIDE - 1;
  signal r_intra_stride_idx : integer range 0 to C_AXIL_STRIDE - 1;

  -- One registered read per lane, muxed into samp_rd_data by
  -- p_samp_rd_mux once r_intra_stride_idx catches up
  signal lane_rd_data : t_lane_rd_arr;

  signal r_wr_idx  : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal w_probe   : std_logic_vector(G_PROBE_WIDTH - 1 downto 0);
  signal w_wr_data : std_logic_vector(C_S_AXIL_DATA_WIDTH * C_N_LANES - 1  downto 0);
  signal en_wr     : std_logic;
  -------------------------------------------------------------------

  -- Calculating required number of the AXILite regs ----------------
  -- The map is laid out output block, then input block, then the sample
  -- buffer. The output block is a fixed eight registers whatever the generics
  -- are, so MGCKEY, WIDTH and DEPTH always sit at the same addresses and a
  -- host can read the dimensions of the map out of the core before it knows
  -- any of them. The input block is the one that grows with C_AXIL_STRIDE, so
  -- it cannot come first without making the discovery registers unfindable
  -- until the probe width is already known.
  --
  -- Note that, the additional ( C_AXIL_STRIDE * G_SAMP_BUFF_DEPTH ) registers are coming from the
  -- buffer itself
  -- The trigger vector cond/mask block reuses C_AXIL_STRIDE so it lines up
  -- with the output sample stride layout, see trig_cond/trig_mask below.
  constant C_AXIL_N_CTRL_REGS_OUT : integer := 8;
  constant C_AXIL_N_CTRL_REGS_IN  : integer := 4 + 2 * C_AXIL_STRIDE;
  constant C_AXIL_N_CTRL_REGS     : integer := C_AXIL_N_CTRL_REGS_OUT + C_AXIL_N_CTRL_REGS_IN;

  -- Total AXI4Lite regs
  constant C_AXIL_N_REGS : integer := C_AXIL_N_CTRL_REGS + (C_AXIL_STRIDE  * G_SAMP_BUFF_DEPTH);
  ------------------------------------------------------------------

  -- ILA STATES -----------------------------------------------------
  constant ILA_IDLE  : std_logic_vector(1 downto 0) := "00";
  constant ILA_ARMED : std_logic_vector(1 downto 0) := "01";
  constant ILA_TRIGD : std_logic_vector(1 downto 0) := "10";
  constant ILA_DONE  : std_logic_vector(1 downto 0) := "11";

  signal ila_state : std_logic_vector(1 downto 0);

  signal ila_armed_samp : std_logic; -- done in the samp domain
  signal ila_armed_sync : std_logic;
  signal ila_armed_axil : std_logic; -- done in the axil domain

  signal ila_trigd_samp : std_logic; -- done in the samp domain
  signal ila_trigd_sync : std_logic;
  signal ila_trigd_axil : std_logic; -- done in the axil domain

  signal ila_done_samp : std_logic; -- done in the samp domain
  signal ila_done_sync : std_logic;
  signal ila_done_axil : std_logic; -- done in the axil domain
  -------------------------------------------------------------------

  -- Triggering signals ---------------------------------------------
  -- Positioning names : Oldest -> latest
  --
  -- Actual sample train:
  -- | pre trigg samples | post trig samples                        |
  --                     ^ trig_tgt               G_SAMP_BUFF_DEPTH ^
  --
  -- Inside the circular buffer:
  -- post trig samples   | pre trig samples | post trig samples     |
  --                                        ^ trig_idx
  -- <------- a --------->                  <--------- b ----------->
  -- a + b is the target number of post trig samples
  -- post_trig_samp_cnt is the counter for that

  signal trig_idx : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal trig_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);

  signal post_trig_samp_cnt : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal post_trig_samp_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);

  signal trig     : std_logic;
  signal trig_lvl : std_logic; -- reduced condition, before any edge detection
  signal trig_or  : std_logic;
  signal trig_and : std_logic;

  -- trig_lvl delayed by one sample, so the edge modes cost one flop instead of
  -- a registered copy of the whole probe word.
  signal trig_lvl_prev : std_logic;

  signal ext_trig_prev : std_logic;

  -- Merged trigger vector -- one bit per probed bit, laid out identically to
  -- the sampled probe word (w_probe), then zero padding up to the stride
  -- boundary.
  constant C_TRIG_VECT_WIDTH : integer := C_AXIL_STRIDE * C_S_AXIL_DATA_WIDTH;

  signal trig_samp_word : std_logic_vector(C_TRIG_VECT_WIDTH - 1 downto 0);
  signal trig_vect      : std_logic_vector(C_TRIG_VECT_WIDTH - 1 downto 0);
  signal trig_mask      : std_logic_vector(C_TRIG_VECT_WIDTH - 1 downto 0);
  signal trig_cond      : std_logic_vector(C_TRIG_VECT_WIDTH - 1 downto 0);
  signal trig_cfg       : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  -------------------------------------------------------------------

  -- Control signals interface --------------------------------------
  signal arm_toggler_axilite : std_logic; -- in the axilite domain
  signal arm_samp            : std_logic; -- synchronised in samp
  signal arm_sync            : std_logic_vector(2 downto 0);

  -- Disarm takes the same toggle-and-edge-detect route as arm. The two are
  -- independent paths, so back to back writes to ARM_FT and DISARM can land in
  -- either order in the sampling domain, software has to leave a gap between
  -- them if it cares which one wins.
  signal disarm_toggler_axilite : std_logic; -- in the axilite domain
  signal disarm_samp            : std_logic; -- synchronised in samp
  signal disarm_sync            : std_logic_vector(2 downto 0);
  -------------------------------------------------------------------

  -- From the axiliteslave template ---------------------------------

  type reg_array_out is array (0 to C_AXIL_N_CTRL_REGS_OUT - 1) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  type reg_array_in is array (0 to C_AXIL_N_CTRL_REGS_IN - 1) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  -- Number of Slave Registers 68
  signal slv_reg_out : reg_array_out;
  signal slv_reg_in  : reg_array_in;

  -- AXI4LITE signals
  signal axil_awaddr  : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal axil_awready : std_logic;
  signal axil_wready  : std_logic;
  signal axil_bresp   : std_logic_vector(1 downto 0);
  signal axil_bvalid  : std_logic;
  signal axil_araddr  : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal axil_arready : std_logic;
  signal axil_rresp   : std_logic_vector(1 downto 0);
  signal axil_rvalid  : std_logic;

  -- Registered read of the per-lane sample buffers, see p_samp_rd_mux
  signal samp_rd_data : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  -- Example-specific design signals
  -- local parameter for addressing 32 bit / 64 bit C_S_AXIL_DATA_WIDTH
  -- ADDR_LSB is used for addressing 32/64 bit registers/memories
  -- ADDR_LSB = 2 for 32 bits (n downto 2)
  -- ADDR_LSB = 3 for 64 bits (n downto 3)
  constant ADDR_LSB : integer := (C_S_AXIL_DATA_WIDTH / 32) + 1;

  -- THIS NEEDS MODIFICATION FOR ACCOMODATING THE G_SAMP_BUFF_DEPTH data regs
  -- constant OPT_MEM_ADDR_BITS : integer := integer(ceil(log2(real(C_AXIL_N_CTRL_REGS)))) - 1;
  constant OPT_MEM_ADDR_BITS : integer := integer(ceil(log2(real(C_AXIL_N_REGS)))) - 1;

  ------------------------------------------------
  -- Signals for user logic register space example
  --------------------------------------------------
  signal mem_logic : std_logic_vector(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);

  -- Widest index the address slice can decode to. The slice is sized to the
  -- whole map rounded up to a power of two, so it reaches past the last real
  -- register, and the range checks in p_wlg/p_rlg are what reject that. Those
  -- checks only get to run if the index can hold the value in the first
  -- place, hence this rather than the register count.
  constant C_MAX_DECODED_IDX : integer := 2 ** (OPT_MEM_ADDR_BITS + 1) - 1;

  -- State machine local parameters
  constant IDLE  : std_logic_vector(1 downto 0) := "00";
  constant RADDR : std_logic_vector(1 downto 0) := "10";
  constant RDATA : std_logic_vector(1 downto 0) := "11";
  constant WADDR : std_logic_vector(1 downto 0) := "10";
  constant WDATA : std_logic_vector(1 downto 0) := "11";

  -- State machine variables
  signal state_read  : std_logic_vector(1 downto 0);
  signal state_write : std_logic_vector(1 downto 0);
-------------------------------------------------------------------

begin

  -- Generic check --------------------------------------------------
  assert (G_PROBE_WIDTH > 0)
    report "G_PROBE_WIDTH must be greater than 0"
    severity failure;

  -- A depth of 1 would give C_ADDR_WIDTH = 0, so two samples is the floor
  assert (G_SAMP_BUFF_DEPTH > 1)
    report "G_SAMP_BUFF_DEPTH must be greater than 1"
    severity failure;

  assert is_power_of_two(G_SAMP_BUFF_DEPTH)
    report "G_SAMP_BUFF_DEPTH must be a power of two"
    severity failure;
  -------------------------------------------------------------------

  -- Shorting of the probe slave and master ports ^^SH ---------------
  -------------------------------------------------------------------

  -- MUXING of the probe ports ^^MX ---------------------------------
  -- The probe word, packed LSB first in the order the signals are listed
  -- in portmap.csv. This concatenation is the single definition of the
  -- probe bit order, the sample buffer and the trigger vector both
  -- inherit it.
  -------------------------------------------------------------------

  -- Zero padded up to the lane boundary on its way into the buffer
  w_wr_data <= std_logic_vector(resize(unsigned(w_probe), w_wr_data'length));
  -------------------------------------------------------------------

  -- Creating trigger ----------------------------------------------
  o_trig_out <= trig;

  g_ext_trig_0 : if G_EXTERNAL_TRIG = 0 generate
    trig_lvl <= trig_or when trig_cfg(0) = '1' else
                trig_and;

    -- Same bit layout as w_wr_data, zero-extended up to the stride boundary
    trig_samp_word <= std_logic_vector(resize(unsigned(w_wr_data), C_TRIG_VECT_WIDTH));

    trig_vect <= trig_samp_word xnor trig_cond;

    -- OR: trigger if any enabled (mask=1) bit matches its condition
    trig_or <= '0' when (trig_vect and trig_mask) = (trig_vect'range => '0') else
               '1';

    -- AND: trigger only if every enabled (mask=1) bit matches its condition
    trig_and <= '1' when (trig_mask and not trig_vect) = (trig_vect'range => '0') else
                '0';

    -- For edge triggers
    p_trig_edge : process (samp_aclk) is
    begin

      if rising_edge(samp_aclk) then
        if (i_rst_sync = '1') then
          trig_lvl_prev <= '0';
        elsif (arm_samp = '1') then
          trig_lvl_prev <= trig_lvl;
        elsif (en_wr = '1') then
          trig_lvl_prev <= trig_lvl;
        end if;
      end if;

    end process p_trig_edge;

    -- trig_cfg(1): 0 = level, 1 = edge
    -- trig_cfg(2): 0 = rising, 1 = falling, only read when trig_cfg(1) = '1'
    trig <= trig_lvl when trig_cfg(1) = '0' else
            (trig_lvl and (not trig_lvl_prev)) when trig_cfg(2) = '0' else
            ((not trig_lvl) and trig_lvl_prev);

  end generate g_ext_trig_0;

  g_ext_trig_1 : if G_EXTERNAL_TRIG = 1 generate

    p_edge_detect : process (samp_aclk) is
    begin

      if rising_edge(samp_aclk) then
        ext_trig_prev <= i_ext_trig;
      end if;

    end process p_edge_detect;

    trig <= (not i_rst_sync) and (i_ext_trig and (not ext_trig_prev));

  end generate g_ext_trig_1;

  ------------------------------------------------------------------

  -- Write process inside the FIFO ----------------------------------
  p_write : process (samp_aclk) is
  begin

    if rising_edge(samp_aclk) then
      if (i_rst_sync = '1') then
        r_wr_idx <= (others => '0');

      -- For the ILA purpose, we are sampling on all rising edges,
      -- user can optionally make this sample only valid handshakes.
      -- Example,
      -- elsif (probe_slave_tvalid = '1' and probe_master_tready = '1') then
      elsif (en_wr = '1') then
        r_wr_idx <= r_wr_idx + 1;
      end if;
    end if;

  end process p_write;

  -- Sample buffer storage, one independent flat RAM per lane; using array of lanes didn't get synthesized as RAMs in both GHDL and Libero 2025.2

  g_samp_lanes : for lane in 0 to C_N_LANES - 1 generate

    signal lane_mem : t_lane;
    attribute syn_ramstyle of lane_mem : signal is "lsram";

  begin

    p_lane_write : process (samp_aclk) is
    begin

      if rising_edge(samp_aclk) then
        if (en_wr = '1') then
          lane_mem(to_integer(r_wr_idx)) <= w_wr_data(lane * 32 + 31 downto lane * 32);
        end if;
      end if;

    end process p_lane_write;

    p_lane_read : process (s_axil_aclk) is
    begin

      if rising_edge(s_axil_aclk) then
        if (w_rd_hit = '1') then
          lane_rd_data(lane) <= lane_mem(w_stride_idx);
        end if;
      end if;

    end process p_lane_read;

  end generate g_samp_lanes;

  -------------------------------------------------------------------

  -- ILA process ----------------------------------------------------
  p_ila : process (samp_aclk) is

    variable v_post_trig_samp_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);

  begin

    if rising_edge(samp_aclk) then
      -- strictly, post_trig_samp_tgt := G_SAMP_BUFF_DEPTH - trig_tgt - 1
      -- but G_SAMP_BUFF_DEPTH = 2**k
      v_post_trig_samp_tgt := not trig_tgt;

      if (i_rst_sync = '1') then
        -- Reseting the trigger positions
        trig_idx           <= (others => '0');
        post_trig_samp_cnt <= (others => '0');
        en_wr              <= '0';

        ila_state <= IDLE;

      -- We dont need to reset the buffer, we are storing full length data always
      else

        case ila_state is

          when ILA_IDLE =>

            en_wr <= '0';

            -- Reseting the trigger positions
            trig_idx           <= (others => '0');
            post_trig_samp_cnt <= (others => '0');

            if (arm_samp = '1') then
              ila_state <= ILA_ARMED;
              en_wr     <= '1';
            end if;

          when ILA_ARMED =>

            if ((trig = '1') or (arm_samp = '1')) then
              trig_idx           <= r_wr_idx;
              post_trig_samp_tgt <= v_post_trig_samp_tgt;

              if (v_post_trig_samp_tgt = (v_post_trig_samp_tgt'range => '0')) then
                ila_state <= ILA_DONE;
                en_wr     <= '0';
              else
                ila_state <= ILA_TRIGD;
              end if;
            -- A trigger landing in the same cycle as a disarm wins, the capture
            -- the host asked for is worth more than the cancel it changed its
            -- mind about. It can always disarm again from ILA_TRIGD
            elsif (disarm_samp = '1') then
              ila_state          <= ILA_IDLE;
              en_wr              <= '0';
              trig_idx           <= (others => '0');
              post_trig_samp_cnt <= (others => '0');
            else
              trig_idx           <= (others => '0');
              post_trig_samp_cnt <= (others => '0');
            end if;

          when ILA_TRIGD =>

            if (post_trig_samp_cnt = post_trig_samp_tgt - 1) then
              ila_state <= ILA_DONE;
              en_wr     <= '0';
            -- Aborting a capture whose trigger has already fired, for a trigger
            -- condition that turned out to be the wrong one. The samples taken
            -- so far stay in the buffer, but trig_idx goes back to zero with the
            -- state so nothing claims they are a capture
            elsif (disarm_samp = '1') then
              ila_state          <= ILA_IDLE;
              en_wr              <= '0';
              trig_idx           <= (others => '0');
              post_trig_samp_cnt <= (others => '0');
            else
              post_trig_samp_cnt <= post_trig_samp_cnt + 1;
              en_wr              <= '1';
            end if;

          when ILA_DONE =>

            -- Deliberately no disarm here. ILA_DONE means a capture is sitting
            -- in the buffer waiting to be read and going to ILA_IDLE would clear
            -- trig_idx, the one thing the host needs to unwrap it. Disarm cancels
            -- a capture, it does not discard a finished one
            if (arm_samp = '1') then
              ila_state <= ILA_ARMED;
              en_wr     <= '1';
            end if;

          when others =>

            ila_state <= ILA_ARMED;

        end case;

      end if;
    end if;

  end process p_ila;

  -------------------------------------------------------------------

  -- SIGNAL synchroniser process ---------------------------------------
  p_signal_cdc : process (samp_aclk) is
  begin

    if (rising_edge(samp_aclk)) then
      if (i_rst_sync = '1') then
        arm_sync    <= (others => '0');
        disarm_sync <= (others => '0');
      else
        arm_sync    <= arm_sync(1 downto 0) & arm_toggler_axilite;
        disarm_sync <= disarm_sync(1 downto 0) & disarm_toggler_axilite;
      end if;
    end if;

  end process p_signal_cdc;

  arm_samp    <= arm_sync(2) xor arm_sync(1);
  disarm_samp <= disarm_sync(2) xor disarm_sync(1);
  -------------------------------------------------------------------

  -- STATE synchroniser process --------------------------------------
  ila_armed_samp <= '1' when ila_state = ILA_ARMED else
                    '0';
  ila_trigd_samp <= '1' when ila_state = ILA_TRIGD else
                    '0';
  ila_done_samp  <= '1' when ila_state = ILA_DONE else
                    '0';

  p_state_cdc : process (s_axil_aclk) is
  begin

    if (rising_edge(s_axil_aclk)) then
      if (s_axil_aresetn = '0') then
        ila_armed_axil <= '0';
        ila_armed_sync <= '0';

        ila_trigd_axil <= '0';
        ila_trigd_sync <= '0';

        ila_done_axil <= '0';
        ila_done_sync <= '0';
      else
        ila_armed_sync <= ila_armed_samp;
        ila_armed_axil <= ila_armed_sync;

        ila_trigd_sync <= ila_trigd_samp;
        ila_trigd_axil <= ila_trigd_sync;

        ila_done_sync <= ila_done_samp;
        ila_done_axil <= ila_done_sync;
      end if;
    end if;

  end process p_state_cdc;

  -------------------------------------------------------------------

  -- From axiliteslave template -------------------------------------
  -- I/O Connections assignments
  s_axil_awready <= axil_awready;
  s_axil_wready  <= axil_wready;
  s_axil_bresp   <= axil_bresp;
  s_axil_bvalid  <= axil_bvalid;
  s_axil_arready <= axil_arready;
  s_axil_rresp   <= axil_rresp;
  s_axil_rvalid  <= axil_rvalid;

  mem_logic <= s_axil_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)
               when (s_axil_awvalid = '1') else
               axil_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);

  -- Implement Write state machine
  -- Outstanding write transactions are not supported by the slave i.e., master
  -- should assert bready to receive response on or before it starts sending
  -- the new transaction
  p_wsm : process (s_axil_aclk) is
  begin

    -------------------------------------------------------------------------------
    -- Unused AXI4 Signals
    -- s0_axil_bid    <= s_axil_awid;    -- The values should match for valid transation
    -- s0_axil_rid    <= s_axil_arid;
    -- s0_axil_rlast  <= s0_axil_rvalid; -- Each transaction is last
    -------------------------------------------------------------------------------

    if rising_edge(s_axil_aclk) then
      if (s_axil_aresetn = '0') then
        -- asserting initial values to all 0's during reset
        axil_awready <= '0';
        axil_wready  <= '0';
        axil_bvalid  <= '0';
        axil_bresp   <= (others => '0');
        state_write  <= IDLE;
      else

        case (state_write) is

          when IDLE =>

            -- Initial state indicating reset is done and ready to receive read/write transactions
            if (s_axil_aresetn = '1') then
              axil_awready <= '1';
              axil_wready  <= '1';
              state_write  <= WADDR;
            else
              state_write <= state_write;
            end if;

          when WADDR =>

            -- At this state, slave is ready to receive address along with
            -- corresponding control signals and first data packet. Response
            -- valid is also handled at this state
            if (s_axil_awvalid = '1' and axil_awready = '1') then
              axil_awaddr <= s_axil_awaddr;
              if (s_axil_wvalid = '1') then
                axil_awready <= '1';
                state_write  <= WADDR;
                axil_bvalid  <= '1';
              else
                axil_awready <= '0';
                state_write  <= WDATA;
                if (s_axil_bready = '1' and axil_bvalid = '1') then
                  axil_bvalid <= '0';
                end if;
              end if;
            else
              state_write <= state_write;
              if (s_axil_bready = '1' and axil_bvalid = '1') then
                axil_bvalid <= '0';
              end if;
            end if;

          when WDATA =>

            -- At this state, slave is ready to receive the data packets
            -- until the number of transfers is equal to burst length
            if (s_axil_wvalid = '1') then
              state_write  <= WADDR;
              axil_bvalid  <= '1';
              axil_awready <= '1';
            else
              state_write <= state_write;
              if (s_axil_bready = '1' and axil_bvalid = '1') then
                axil_bvalid <= '0';
              end if;
            end if;

          when others =>

            -- reserved
            axil_awready <= '0';
            axil_wready  <= '0';
            axil_bvalid  <= '0';

        end case;

      end if;
    end if;

  end process p_wsm;

  -- Implement memory mapped register select and write logic generation
  -- The write data is accepted and written to memory mapped registers when
  -- axil_awready, S_AXI_WVALID, axil_wready and S_AXI_WVALID are asserted. Write strobes are used to
  -- select byte enables of slave registers while writing.
  -- These registers are cleared when reset (active low) is applied.
  -- Slave register write enable is asserted when valid address and data are available
  -- and the slave is ready to accept the write address and write data.
  p_wlg : process (s_axil_aclk) is

    variable idx    : integer range 0 to C_MAX_DECODED_IDX;
    variable in_idx : integer range 0 to C_AXIL_N_CTRL_REGS_IN - 1;

  begin

    if rising_edge(s_axil_aclk) then
      if (s_axil_aresetn = '0') then
        -- clear the register array
        arm_toggler_axilite    <= '0';
        disarm_toggler_axilite <= '0';

        for i in 0 to C_AXIL_N_CTRL_REGS_IN - 1 loop

          slv_reg_in(i) <= (others => '0');

        end loop;

      else
        if (s_axil_wvalid = '1') then
          -- compute index from address slice and write bytes per WSTRB
          idx := to_integer(unsigned(mem_logic));
          -- The output block sits below the input one and is read only, so a
          -- write anywhere under C_AXIL_N_CTRL_REGS_OUT is dropped along with
          -- one aimed at the sample buffer.
          if (idx >= C_AXIL_N_CTRL_REGS_OUT and idx < C_AXIL_N_CTRL_REGS) then
            in_idx := idx - C_AXIL_N_CTRL_REGS_OUT;
            -- ARM_FT and DISARM act on the write itself, the data written is
            -- stored like any other input register but never looked at
            if (in_idx = 1) then
              arm_toggler_axilite <= not arm_toggler_axilite;
            elsif (in_idx = 3) then
              disarm_toggler_axilite <= not disarm_toggler_axilite;
            end if;
            slv_reg_in(in_idx) <= s_axil_wdata;
          end if;
        end if;
      end if;
    end if;

  end process p_wlg;

  -- Implement read state machine
  p_rsm : process (s_axil_aclk) is
  begin

    if rising_edge(s_axil_aclk) then
      if (s_axil_aresetn = '0') then
        -- asserting initial values to all 0's during reset
        axil_arready <= '0';
        axil_rvalid  <= '0';
        axil_rresp   <= (others => '0');
        state_read   <= IDLE;
      else

        case (state_read) is

          when IDLE =>

            -- Initial state indicating reset is done and ready to receive read/write transactions
            if (s_axil_aresetn = '1') then
              axil_arready <= '1';
              state_read   <= RADDR;
            else
              state_read <= state_read;
            end if;

          when RADDR =>

            -- At this state, slave is ready to receive address along with corresponding control signals
            if (s_axil_arvalid = '1' and axil_arready = '1') then
              state_read   <= RDATA;
              axil_rvalid  <= '1';
              axil_arready <= '0';
              axil_araddr  <= s_axil_araddr;
            else
              state_read <= state_read;
            end if;

          when RDATA =>

            -- At this state, slave is ready to send the data packets until
            -- the number of transfers is equal to burst length
            if (axil_rvalid = '1' and s_axil_rready = '1') then
              axil_rvalid  <= '0';
              axil_arready <= '1';
              state_read   <= RADDR;
            else
              state_read <= state_read;
            end if;

          when others =>

            -- reserved
            axil_arready <= '0';
            axil_rvalid  <= '0';

        end case;

      end if;
    end if;

  end process p_rsm;

  -- Address decode is combinational and shared by every lane in
  p_rd_decode : process (s_axil_araddr, state_read, s_axil_arvalid, axil_arready) is

    variable rd_idx      : integer range 0 to C_MAX_DECODED_IDX;
    variable samp_rd_idx : integer range 0 to ((G_SAMP_BUFF_DEPTH + 1) * C_AXIL_STRIDE);

  begin

    w_rd_hit           <= '0';
    w_stride_idx       <= 0;
    w_intra_stride_idx <= 0;

    if (state_read = RADDR and s_axil_arvalid = '1' and axil_arready = '1') then
      rd_idx := to_integer(unsigned(s_axil_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)));

      if (rd_idx >= C_AXIL_N_CTRL_REGS and rd_idx < (C_AXIL_N_CTRL_REGS + G_SAMP_BUFF_DEPTH * C_AXIL_STRIDE)) then
        samp_rd_idx := rd_idx - C_AXIL_N_CTRL_REGS;

        w_stride_idx       <= samp_rd_idx / C_AXIL_STRIDE;
        w_intra_stride_idx <= samp_rd_idx mod C_AXIL_STRIDE;
        w_rd_hit           <= '1';
      end if;
    end if;

  end process p_rd_decode;

  -- processing stride index
  p_rd_meta : process (s_axil_aclk) is
  begin

    if rising_edge(s_axil_aclk) then
      if (w_rd_hit = '1') then
        r_intra_stride_idx <= w_intra_stride_idx;
      end if;
    end if;

  end process p_rd_meta;

  -- reading proper lane
  p_samp_rd_mux : process (r_intra_stride_idx, lane_rd_data) is
  begin

    samp_rd_data <= (others => '0');

    if (r_intra_stride_idx < C_N_LANES) then
      samp_rd_data <= lane_rd_data(r_intra_stride_idx);
    end if;

  end process p_samp_rd_mux;

  -------------------------------------------------------------------

  -- Implement memory mapped register select and read logic generation
  -- Bounds-check address to avoid out-of-range access on register arrays.
  p_rlg : process (axil_araddr, slv_reg_in, slv_reg_out, samp_rd_data) is

    variable rd_idx           : integer range 0 to C_MAX_DECODED_IDX;
    variable samp_rd_idx      : integer range 0 to ((G_SAMP_BUFF_DEPTH + 1) * C_AXIL_STRIDE);
    variable intra_stride_idx : integer range 0 to C_AXIL_STRIDE - 1;

  begin

    rd_idx := to_integer(unsigned(axil_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)));

    if (rd_idx < C_AXIL_N_CTRL_REGS_OUT) then
      -- Mapping of the output regs
      s_axil_rdata <= slv_reg_out(rd_idx);
    elsif (rd_idx < C_AXIL_N_CTRL_REGS) then
      -- Mapping of the input regs
      s_axil_rdata <= slv_reg_in(rd_idx - C_AXIL_N_CTRL_REGS_OUT);
    elsif (rd_idx < (C_AXIL_N_CTRL_REGS + G_SAMP_BUFF_DEPTH  * C_AXIL_STRIDE)) then
      -- Mapping of the RAM regs
      samp_rd_idx      := rd_idx - C_AXIL_N_CTRL_REGS;
      intra_stride_idx := samp_rd_idx mod C_AXIL_STRIDE;

      -- Display the data STRIDE wise

      if (intra_stride_idx < C_N_LANES) then
        s_axil_rdata <= samp_rd_data;
      else
        s_axil_rdata <= (others => '0');
      end if;
    else
      s_axil_rdata <= (others => '0');
    end if;

  end process p_rlg;

  -------------------------------------------------------------------------------
  -- Example usage:
  -- slv_reg_out(N)(3 downto 0) <= i_my_input;
  -- o_my_output <= slv_reg_in( N -(C_AXIL_N_CTRL_REGS_OUT) )(14 downto 0);
  -- Note that, here N means Nth register among all the AXI4Lite registers
  -- The output block comes first, so slv_reg_out is indexed directly and it is
  -- slv_reg_in that needs the C_AXIL_N_CTRL_REGS_OUT offset taken off
  -- Add user connections here --------------------------------------------------
  trig_tgt <= unsigned(slv_reg_in(0)(trig_tgt'range));
  trig_cfg <= slv_reg_in(2);
  -- slv_reg_in(1) is ARM_FT and slv_reg_in(3) is DISARM, both write-triggered,
  -- see p_wlg

  trig_cond_gen : for i in 0 to C_AXIL_STRIDE - 1 generate
    trig_cond(i * 32 + 31 downto 32 * i) <= slv_reg_in(i + 4);
  end generate trig_cond_gen;

  trig_mask_gen : for i in 0 to C_AXIL_STRIDE - 1 generate
    trig_mask(i * 32 + 31 downto 32 * i) <= slv_reg_in(i + 4 + C_AXIL_STRIDE);
  end generate trig_mask_gen;

  slv_reg_out(0)(0)                                <= ila_armed_axil;
  slv_reg_out(0)(1)                                <= ila_trigd_axil;
  slv_reg_out(0)(2)                                <= ila_done_axil;
  slv_reg_out(0)(4 downto 3)                       <= ila_state;
  slv_reg_out(0)(C_S_AXIL_DATA_WIDTH - 1 downto 5) <= (others => '0');

  slv_reg_out(1) <= x"B01DFACE";

  slv_reg_out(2) <= STD_LOGIC_VECTOR(to_unsigned(G_SAMP_CLK_FREQ, C_S_AXIL_DATA_WIDTH));

  -- Total probed bits, data and signalling ports together. Software derives
  -- the lane count from this alone, it has no reason to know the split.
  slv_reg_out(3) <= STD_LOGIC_VECTOR(to_unsigned(G_PROBE_WIDTH, C_S_AXIL_DATA_WIDTH));

  slv_reg_out(4) <= STD_LOGIC_VECTOR(to_unsigned(G_SAMP_BUFF_DEPTH, C_S_AXIL_DATA_WIDTH));

  -- Identity of this instance, not of the core. Nothing reads it back on the
  -- hardware side and every value is legal, zero included: MGCKEY above is
  -- what a host checks to know it is talking to a LibreILA at all.
  slv_reg_out(5) <= STD_LOGIC_VECTOR(to_unsigned(G_UID, C_S_AXIL_DATA_WIDTH));

  slv_reg_out(6)(trig_idx'range)                               <= STD_LOGIC_VECTOR(trig_idx);
  slv_reg_out(6)(C_S_AXIL_DATA_WIDTH - 1 downto C_ADDR_WIDTH ) <= (others => '0');

  slv_reg_out(7)(r_wr_idx'range)                               <= STD_LOGIC_VECTOR(r_wr_idx);
  slv_reg_out(7)(C_S_AXIL_DATA_WIDTH - 1 downto  C_ADDR_WIDTH) <= (others => '0');

-------------------------------------------------------------------------------
-------------------------------------------------------------------

end architecture rtl;
