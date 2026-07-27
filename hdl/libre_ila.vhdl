-------------------------------------------------------------------------------
-- File: libre_ila.vhdl
-- Author: Y.U.P. (paritkary25)
-- Created: 2026-07-14 Tue 11:11
-- Last Modified: 2026-07-27 Mon 10:25
--
-- Description: An ILA for AXI4-Stream
-- Usage:
--   * The AXI4Stream ports are pass through ports which are probed and saved
--     to a buffer
--   * Configure the trigger and arm using the AXI4Lite port
--   * The buffer is read back using AXI4Lite port
--   * The data can be read back using the C driver provided
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity libre_ila is
  generic (
    -- Clock speed of the AXIS, used in plotting
    G_AXIS_CLK_FREQ     : integer := 100000000;
    G_AXIL_CLK_FREQ     : integer := 100000000;
    G_EXTERNAL_TRIG     : integer := 0;    -- 1 for external trigger pin
    G_DATA_WIDTH        : natural := 64;   -- Keep it a multiple of 32 for best results
    G_DEPTH             : natural := 2048; -- Keep it a power of two for best results
    C_S_AXIL_DATA_WIDTH : integer := 32;   -- DONT CHANGE
    C_S_AXIL_ADDR_WIDTH : integer := 32    -- DONT CHANGE
  );
  port (
    i_rst_sync : in    std_logic;

    -- External tigger
    i_ext_trig : in    std_logic;
    o_trig_out : out   std_logic;

    -- AXI4S_IN port
    axis_in_aclk   : in    std_logic;
    axis_in_tready : out   std_logic;
    axis_in_tvalid : in    std_logic;
    axis_in_tlast  : in    std_logic;
    axis_in_tdata  : in    std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- AXI4S_OUT port
    axis_out_aclk   : out   std_logic;
    axis_out_tready : in    std_logic;
    axis_out_tvalid : out   std_logic;
    axis_out_tlast  : out   std_logic;
    axis_out_tdata  : out   std_logic_vector(G_DATA_WIDTH - 1 downto 0);

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
  constant C_ADDR_WIDTH : integer := integer(ceil(log2(real(G_DEPTH))));

  ------------------------ USER PARAMETER ---------------------------
  -- Number of signalling ports used in the ILA, make sure to change
  -- with the actual number of ports, eg, TKEEP is TDATA/8

  -- Currently its TREADY, TVALID and TLAST, so 3 signals
  constant C_AXIS_N_SIGNALS : integer := 3;

  -- Now, 3 signals can be fit inside a 1 32 bit regs hence,
  constant C_N_LANES : integer := G_DATA_WIDTH / 32 + 1;
  ---------------------- USER PARAMETER ENDS ------------------------

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

  -- Automatically scales based on G_DATA_WIDTH
  constant C_AXIL_STRIDE : integer := get_stride(C_N_LANES);
  -------------------------------------------------------------------

  type t_lane is array (0 to G_DEPTH - 1) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  type t_lane_arr is array (0 to C_N_LANES - 1) of t_lane;

  signal samp_buff : t_lane_arr;
  attribute syn_ramstyle : string;
  attribute syn_ramstyle of samp_buff : signal is "lsram";

  signal r_wr_idx  : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal w_wr_data : std_logic_vector(C_S_AXIL_DATA_WIDTH * C_N_LANES - 1  downto 0);
  signal en_wr     : std_logic;
  -------------------------------------------------------------------

  -- Calculating required number of the AXILite regs ----------------
  -- Note that, the additional ( (G_DATA_WIDTH / 32 + 1) * G_DEPTH ) registers are coming from the
  -- buffer itself
  constant C_AXIL_N_CTRL_REGS_IN  : integer := 4 + 2 * G_DATA_WIDTH / 32;
  constant C_AXIL_N_CTRL_REGS_OUT : integer := 8;
  constant C_AXIL_N_CTRL_REGS     : integer := C_AXIL_N_CTRL_REGS_IN + C_AXIL_N_CTRL_REGS_OUT;

  -- Total AXI4Lite regs
  constant C_AXIL_N_REGS : integer := C_AXIL_N_CTRL_REGS + (C_AXIL_STRIDE  * G_DEPTH);
  ------------------------------------------------------------------

  -- ILA STATES -----------------------------------------------------
  constant ILA_IDLE  : std_logic_vector(1 downto 0) := "00";
  constant ILA_ARMED : std_logic_vector(1 downto 0) := "01";
  constant ILA_TRIGD : std_logic_vector(1 downto 0) := "10";
  constant ILA_DONE  : std_logic_vector(1 downto 0) := "11";

  signal ila_state : std_logic_vector(1 downto 0);

  signal ila_armed_axis : std_logic; -- done in the axis domain
  signal ila_armed_sync : std_logic;
  signal ila_armed_axil : std_logic; -- done in the axil domain

  signal ila_trigd_axis : std_logic; -- done in the axis domain
  signal ila_trigd_sync : std_logic;
  signal ila_trigd_axil : std_logic; -- done in the axil domain

  signal ila_done_axis : std_logic; -- done in the axis domain
  signal ila_done_sync : std_logic;
  signal ila_done_axil : std_logic; -- done in the axil domain
  -------------------------------------------------------------------

  -- Triggering signals ---------------------------------------------
  -- Positioning names : Oldest -> latest
  --
  -- Actual sample train:
  -- | pre trigg samples | post trig samples                        |
  --                     ^ trig_tgt                         G_DEPTH ^
  --
  -- Inside the circular buffer:
  -- post trig samples   | pre trig samples | post trig samples     |
  --                                        ^ trig_idx
  -- <------- a --------->                  <--------- b ----------->
  -- a + b is the target number of post trig samples
  -- post_trig_sample_cnt is the counter for that

  signal trig_idx : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal trig_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);

  signal post_trig_sample_cnt : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal post_trig_sample_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);

  signal trig     : std_logic;
  signal trig_or  : std_logic;
  signal trig_and : std_logic;

  signal ext_trig      : std_logic;
  signal ext_trig_prev : std_logic;

  signal trig_vect : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  signal trig_mask : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  signal trig_cond : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  -- If the data is used as a condition
  signal trig_data      : std_logic; -- denotes if the data satisfies trig condition
  signal trig_data_cond : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  signal trig_data_mask : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  -------------------------------------------------------------------

  -- Control signals interface --------------------------------------
  signal arm_toggler_axilite : std_logic; -- in the axilite domain
  signal arm_axis            : std_logic; -- synchronised in axis
  signal arm_sync            : std_logic_vector(2 downto 0);
  -------------------------------------------------------------------

  -- From the axiliteslave template ---------------------------------

  type reg_array_in is array (0 to C_AXIL_N_CTRL_REGS_IN - 1) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  type reg_array_out is array (0 to (C_AXIL_N_CTRL_REGS - C_AXIL_N_CTRL_REGS_IN - 1)) of std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  -- Number of Slave Registers 68
  signal slv_reg_in  : reg_array_in;
  signal slv_reg_out : reg_array_out;

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

  -- Example-specific design signals
  -- local parameter for addressing 32 bit / 64 bit C_S_AXIL_DATA_WIDTH
  -- ADDR_LSB is used for addressing 32/64 bit registers/memories
  -- ADDR_LSB = 2 for 32 bits (n downto 2)
  -- ADDR_LSB = 3 for 64 bits (n downto 3)
  constant ADDR_LSB : integer := (C_S_AXIL_DATA_WIDTH / 32) + 1;

  -- THIS NEEDS MODIFICATION FOR ACCOMODATING THE G_DEPTH data regs
  -- constant OPT_MEM_ADDR_BITS : integer := integer(ceil(log2(real(C_AXIL_N_CTRL_REGS)))) - 1;
  constant OPT_MEM_ADDR_BITS : integer := integer(ceil(log2(real(C_AXIL_N_REGS)))) - 1;

  ------------------------------------------------
  -- Signals for user logic register space example
  --------------------------------------------------
  signal mem_logic : std_logic_vector(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);

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

  -- Shorting of AXI4S ports ----------------------------------------
  axis_out_aclk   <= axis_in_aclk;
  axis_out_tvalid <= axis_in_tvalid;
  axis_out_tdata  <= axis_in_tdata;
  axis_out_tlast  <= axis_in_tlast;
  axis_in_tready  <= axis_out_tready;
  -------------------------------------------------------------------

  -- MUXING of the ports --------------------------------------------
  w_wr_data <=
  (
    (C_S_AXIL_DATA_WIDTH * C_N_LANES - 1)  downto (G_DATA_WIDTH + C_AXIS_N_SIGNALS) => '0'
  )
    & axis_out_tready
    & axis_in_tvalid
    & axis_in_tlast
    & axis_in_tdata;
  -------------------------------------------------------------------

  -- Creating trigger ----------------------------------------------
  o_trig_out <= trig;

  g_ext_trig_0 : if G_EXTERNAL_TRIG = 0 generate
    trig <= trig_or when trig_cond(4) = '1' else
            trig_and;

    trig_data <= '1' when ((axis_in_tdata xor trig_data_cond) and trig_data_mask)
                          = (G_DATA_WIDTH - 1 downto 0 => '0') else
                 '0';

    trig_vect(0)                                <= axis_out_tready xnor trig_cond(0);
    trig_vect(1)                                <= axis_in_tvalid xnor trig_cond(1);
    trig_vect(2)                                <= axis_in_tlast xnor trig_cond(2);
    trig_vect(3)                                <= trig_data xnor trig_cond(3);
    trig_vect(C_S_AXIL_DATA_WIDTH - 1 downto 4) <= (others => '0');

    trig_or <= (trig_vect(0) and trig_mask(0)) or
               (trig_vect(1) and trig_mask(1)) or
               (trig_vect(2) and trig_mask(2)) or
               (trig_vect(3) and trig_mask(3));

    trig_and <= (trig_vect(0) nor  trig_mask(0)) and
                (trig_vect(1) nor  trig_mask(1)) and
                (trig_vect(2) nor  trig_mask(2)) and
                (trig_vect(3) nor  trig_mask(3));
  end generate g_ext_trig_0;

  g_ext_trig_1 : if G_EXTERNAL_TRIG = 1 generate

    p_edge_detect : process (axis_in_aclk) is
    begin

      if rising_edge(axis_in_aclk) then
        if (i_rst_sync = '1') then  -- Optional reset
          --  ext_trig_prev <= '0';
          ext_trig <= '0';
        else
          -- ext_trig      <= i_ext_trig;
          ext_trig_prev <= i_ext_trig;
        end if;
      end if;

    end process p_edge_detect;

    trig <= (not i_rst_sync) and (i_ext_trig and (not ext_trig_prev));

  end generate g_ext_trig_1;

  ------------------------------------------------------------------

  -- Write process inside the FIFO ----------------------------------
  p_write : process (axis_in_aclk) is
  begin

    if rising_edge(axis_in_aclk) then
      if (i_rst_sync = '1') then
        r_wr_idx <= (others => '0');

      -- For the ILA purpose, we are sampling on all rising edges,
      -- user can optionally make this sample only valid handshakes.
      -- Example,
      -- elsif (axis_in_tvalid = '1' and axis_out_tready = '1') then
      elsif (en_wr = '1') then

        for lane in 0 to C_N_LANES - 1 loop

          samp_buff(lane)(to_integer(r_wr_idx)) <= w_wr_data(lane * 32 + 31 downto lane * 32);

        end loop;

        r_wr_idx <= r_wr_idx + 1;
      end if;
    end if;

  end process p_write;

  -------------------------------------------------------------------

  -- ILA process ----------------------------------------------------
  p_ila : process (axis_in_aclk) is
  begin

    if rising_edge(axis_in_aclk) then
      if (i_rst_sync = '1') then
        -- Reseting the trigger positions
        trig_idx             <= (others => '0');
        post_trig_sample_cnt <= (others => '0');
        en_wr                <= '0';

        ila_state <= IDLE;

      -- We dont need to reset the buffer, we are storing full length data always
      else

        case ila_state is

          when ILA_IDLE =>

            en_wr <= '0';

            -- Reseting the trigger positions
            trig_idx             <= (others => '0');
            post_trig_sample_cnt <= (others => '0');

            if (arm_axis = '1') then
              ila_state <= ILA_ARMED;
            end if;

          when ILA_ARMED =>

            en_wr <= '1';

            if ((trig = '1') or (arm_axis = '1')) then
              trig_idx             <= r_wr_idx;
              ila_state            <= ILA_TRIGD;
              post_trig_sample_tgt <= G_DEPTH - trig_tgt - 1;
            else
              trig_idx             <= (others => '0');
              post_trig_sample_cnt <= (others => '0');
            end if;

          when ILA_TRIGD =>

            if (post_trig_sample_cnt = post_trig_sample_tgt) then
              ila_state <= ILA_DONE;
              en_wr     <= '0';
            else
              post_trig_sample_cnt <= post_trig_sample_cnt + 1;
              en_wr                <= '1';
            end if;

          when ILA_DONE =>

            if (arm_axis = '1') then
              ila_state <= ILA_ARMED;
            end if;

          when others =>

            ila_state <= ILA_ARMED;

        end case;

      end if;
    end if;

  end process p_ila;

  -------------------------------------------------------------------

  -- SIGNAL synchroniser process ---------------------------------------
  p_signal_cdc : process (axis_in_aclk) is
  begin

    if (rising_edge(axis_in_aclk)) then
      if (i_rst_sync = '1') then
        arm_sync <= (others => '0');
      else
        arm_sync <= arm_sync(1 downto 0) & arm_toggler_axilite;
      end if;
    end if;

  end process p_signal_cdc;

  arm_axis <= arm_sync(2) xor arm_sync(1);
  -------------------------------------------------------------------

  -- STATE synchroniser process --------------------------------------
  ila_armed_axis <= '1' when ila_state = ILA_ARMED else
                    '0';
  ila_trigd_axis <= '1' when ila_state = ILA_TRIGD else
                    '0';
  ila_done_axis  <= '1' when ila_state = ILA_DONE else
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
        ila_armed_sync <= ila_armed_axis;
        ila_armed_axil <= ila_armed_sync;

        ila_trigd_sync <= ila_trigd_axis;
        ila_trigd_axil <= ila_trigd_sync;

        ila_done_sync <= ila_done_axis;
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
  -- Outstanding write transactions are not supported by the slave i.e., master should assert bready to receive response on or before it starts sending the new transaction
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

            -- At this state, slave is ready to receive address along with corresponding control signals and first data packet. Response valid is also handled at this state
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

            -- At this state, slave is ready to receive the data packets until the number of transfers is equal to burst length
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

    variable idx : integer range 0 to C_AXIL_N_CTRL_REGS - 1;

  begin

    if rising_edge(s_axil_aclk) then
      if (s_axil_aresetn = '0') then
        -- clear the register array
        arm_toggler_axilite <= '0';

        for i in 0 to C_AXIL_N_CTRL_REGS_IN - 1 loop

          slv_reg_in(i) <= (others => '0');

        end loop;

      else
        if (s_axil_wvalid = '1') then
          -- compute index from address slice and write bytes per WSTRB
          idx := to_integer(unsigned(mem_logic));
          if (idx >= 0 and idx < C_AXIL_N_CTRL_REGS_IN) then
            if (idx = 3) then
              arm_toggler_axilite <= not arm_toggler_axilite;
            end if;
            slv_reg_in(idx) <= s_axil_wdata;
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

            -- At this state, slave is ready to send the data packets until the number of transfers is equal to burst length
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

  -- Implement memory mapped register select and read logic generation
  -- Bounds-check address to avoid out-of-range access on register arrays.
  p_rlg : process (axil_araddr, slv_reg_in, slv_reg_out, samp_buff) is

    variable rd_idx           : integer range 0 to C_AXIL_N_REGS - 1;
    variable samp_rd_idx      : integer range 0 to ((G_DEPTH + 1) * C_AXIL_STRIDE);
    variable stride_idx       : integer range 0 to G_DEPTH - 1;
    variable intra_stride_idx : integer range 0 to C_AXIL_STRIDE - 1;

  begin

    rd_idx := to_integer(unsigned(axil_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)));

    if (rd_idx < C_AXIL_N_CTRL_REGS_IN) then
      -- Mapping of the input regs
      s_axil_rdata <= slv_reg_in(rd_idx);
    elsif (rd_idx < C_AXIL_N_CTRL_REGS) then
      -- Mapping of the output regs
      s_axil_rdata <= slv_reg_out(rd_idx - C_AXIL_N_CTRL_REGS_IN);
    elsif (rd_idx < (C_AXIL_N_CTRL_REGS + G_DEPTH  * C_AXIL_STRIDE)) then
      -- Mapping of the RAM regs
      samp_rd_idx      := rd_idx - C_AXIL_N_CTRL_REGS;
      stride_idx       := samp_rd_idx / C_AXIL_STRIDE;
      intra_stride_idx := samp_rd_idx mod C_AXIL_STRIDE;

      -- Display the data STRIDE wise

      if (intra_stride_idx < C_N_LANES) then
        s_axil_rdata <= samp_buff(intra_stride_idx)(stride_idx);
      else
        s_axil_rdata <= (others => '0');
      end if;
    else
      s_axil_rdata <= (others => '0');
    end if;

  end process p_rlg;

  -------------------------------------------------------------------------------
  -- Example usage:
  -- o_my_output <= slv_reg_in(0)(14 downto 0);
  -- slv_reg_out( N -(C_AXI_N_REGS_IN) )(3 downto 0) <= i_my_input;
  -- Note that, here N means Nth register among all the AXI4Lite registers
  -- We need output offset of ( C_AXI_N_REGS_IN - 1 ) offset to properly map slv_reg_out
  -- Add user connections here --------------------------------------------------
  trig_cond <= slv_reg_in(0);
  trig_mask <= slv_reg_in(1);
  trig_tgt  <= unsigned(slv_reg_in(2)(trig_tgt'range));

  data_cond_gen : for i in 0 to (G_DATA_WIDTH / 32) - 1  generate
    trig_data_cond(i * 32 + 31 downto 32 * i ) <= slv_reg_in(i + 4);
  end generate data_cond_gen;

  data_mask_gen : for i in 0 to (G_DATA_WIDTH / 32) - 1 generate
    trig_data_mask(i * 32 + 31 downto 32 * i ) <= slv_reg_in(i + 4 + G_DATA_WIDTH / 32);
  end generate data_mask_gen;

  slv_reg_out(0)(0)                                <= ila_armed_axil;
  slv_reg_out(0)(1)                                <= ila_trigd_axil;
  slv_reg_out(0)(2)                                <= ila_done_axil;
  slv_reg_out(0)(4 downto 3)                       <= ila_state;
  slv_reg_out(0)(C_S_AXIL_DATA_WIDTH - 1 downto 5) <= (others => '0');

  slv_reg_out(1) <= x"B01DFACE";

  slv_reg_out(2) <= STD_LOGIC_VECTOR(to_unsigned(G_AXIS_CLK_FREQ, C_S_AXIL_DATA_WIDTH));

  slv_reg_out(3)(31 downto 16) <= STD_LOGIC_VECTOR(to_unsigned(C_AXIS_N_SIGNALS, 16));
  slv_reg_out(3)(15 downto  0) <= STD_LOGIC_VECTOR(to_unsigned(G_DATA_WIDTH, 16));

  slv_reg_out(4) <= STD_LOGIC_VECTOR(to_unsigned(G_DEPTH, C_S_AXIL_DATA_WIDTH));

  slv_reg_out(5) <= (others => '0');

  slv_reg_out(6)(trig_idx'range)                               <= STD_LOGIC_VECTOR(trig_idx);
  slv_reg_out(6)(C_S_AXIL_DATA_WIDTH - 1 downto C_ADDR_WIDTH ) <= (others => '0');

  slv_reg_out(7)(r_wr_idx'range)                               <= STD_LOGIC_VECTOR(r_wr_idx);
  slv_reg_out(7)(C_S_AXIL_DATA_WIDTH - 1 downto  C_ADDR_WIDTH) <= (others => '0');

-------------------------------------------------------------------------------
-------------------------------------------------------------------

end architecture rtl;
