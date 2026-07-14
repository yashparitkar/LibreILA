-------------------------------------------------------------------------------
-- File: axi4s_ila.vhdl
-- Author: Y.U.P.
-- Created: 2026/07/14 11:11
-- Last modified: 2026/07/14 11:12
--
-- Description: An ILA for AXI4-Stream.
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

entity axi4s_ila is
  generic (
    G_EXTERNAL_TRIG     : integer := 0;    -- 1 for external trigger pin
    G_DATA_WIDTH        : natural := 64;   -- Keep it a multiple of 32 for best results
    G_DEPTH             : integer := 2048; -- Keep it a power of two for best results
    C_S_AXIL_DATA_WIDTH : integer := 32;
    C_S_AXIL_ADDR_WIDTH : integer := 32
  );
  port (
    i_rst_sync    : in    std_logic;
    axis_in_aclk  : in    std_logic;
    axis_out_aclk : in    std_logic;
    axil_s_aclk   : in    std_logic;

    -- External tigger
    i_ext_trig : in    std_logic;

    -- AXI4S_IN port
    axis_in_tready : out   std_logic;
    axis_in_tvalid : in    std_logic;
    axis_in_tlast  : in    std_logic;
    axis_in_tdata  : in    std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- AXI4S_OUT port
    axis_out_tready : in    std_logic;
    axis_out_tvalid : out   std_logic;
    axis_out_tlast  : out   std_logic;
    axis_out_tdata  : out   std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- AXI4Lite slave port
    axil_aclk    : in    std_logic;
    axil_aresetn : in    std_logic;
    axil_awaddr  : in    std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
    axil_awprot  : in    std_logic_vector(2 downto 0);
    axil_awvalid : in    std_logic;
    axil_awready : out   std_logic;
    axil_wdata   : in    std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
    axil_wstrb   : in    std_logic_vector((C_S_AXIL_DATA_WIDTH / 8) - 1 downto 0);
    axil_wvalid  : in    std_logic;
    axil_wready  : out   std_logic;
    axil_bresp   : out   std_logic_vector(1 downto 0);
    axil_bvalid  : out   std_logic;
    axil_bready  : in    std_logic;
    axil_araddr  : in    std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
    axil_arprot  : in    std_logic_vector(2 downto 0);
    axil_arvalid : in    std_logic;
    axil_arready : out   std_logic;
    axil_rdata   : out   std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
    axil_rresp   : out   std_logic_vector(1 downto 0);
    axil_rvalid  : out   std_logic;
    axil_rready  : in    std_logic
  );
end entity axi4s_ila;

architecture rtl of axi4s_ila is

  -- Making of the FIFO ---------------------------------------------
  constant C_ADDR_WIDTH : integer := integer(ceil(log2(real(G_DEPTH))));

  ------------------------ USER PARAMETER ---------------------------
  -- Number of signalling ports used in the ILA, make sure to change
  -- with the actual number of ports, eg, TKEEP is TDATA/8
  constant C_AXIS_N_SIGNALS : integer := 3;
  ---------------------- USER PARAMETER ENDS ------------------------

  type t_fifo_data is array (0 to G_DEPTH - 1) of std_logic_vector((G_DATA_WIDTH + C_AXIS_N_SIGNALS - 1) downto 0);

  signal r_fifo_data : t_fifo_data;
  attribute syn_ramstyle : string;
  attribute syn_ramstyle of r_fifo_data : signal is "lsram";

  signal r_wr_index : unsigned(C_ADDR_WIDTH  downto 0);
  signal w_wr_data  : std_logic_vector(G_DATA_WIDTH downto 0);
  -------------------------------------------------------------------

  -- ILA STATES -----------------------------------------------------
  constant ILA_IDLE  : std_logic_vector(1 downto 0) := "00";
  constant ILA_ARMED : std_logic_vector(1 downto 0) := "01";
  constant ILA_TRIGD : std_logic_vector(1 downto 0) := "10";
  constant ILA_DONE  : std_logic_vector(1 downto 0) := "11";

  signal ila_state : std_logic_vector(1 downto 0);
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

  signal trig_or   : std_logic;
  signal trig_and  : std_logic;
  signal trig_mask : std_logic_vector(C_S_AXIL_DATA_WIDTH);
  signal trig_cond : std_logic_vector(C_S_AXIL_DATA_WIDTH);

  signal trig_idx : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal trig_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);

  signal post_trig_sample_cnt : unsigned(C_ADDR_WIDTH - 1 downto 0);
  signal post_trig_sample_tgt : unsigned(C_ADDR_WIDTH - 1 downto 0);
-------------------------------------------------------------------

begin

  -- Shorting of AXI4S ports ----------------------------------------
  axis_out_tvalid <= axis_in_tvalid;
  axis_out_tdata  <= axis_in_tdata;
  axis_out_tlast  <= axis_in_tlast;
  axis_in_tready  <= axis_out_tready;
  -------------------------------------------------------------------

  -- MUXING of the ports --------------------------------------------
  w_wr_data <= axis_out_tlast
               & axis_in_tvalid
               & axis_in_tlast
               & axis_in_tdata;
  -------------------------------------------------------------------

  -- Write process inside the FIFO ----------------------------------
  p_write : process (axis_in_aclk) is
  begin

    if rising_edge(axis_in_aclk) then
      if (i_rst_sync = '1') then
        r_wr_index <= (others => '0');

      -- For the ILA purpose, we are sampling on all rising edges,
      -- user can optionally make this sample only valid handshakes.
      -- Example,
      -- elsif (axis_in_tvalid = '1' and axis_out_tready = '1') then
      elsif (en_wr = '1') then
        r_fifo_data(to_integer(r_wr_index( c_ADDR_WIDTH - 1 downto 0))) <= w_wr_data;
        r_wr_index                                                      <= r_wr_index + 1;
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

        ila_state <= IDLE;
      else

        case ila_state is

          when ILA_IDLE =>

            -- Reseting the trigger positions
            trig_idx             <= (others => '0');
            post_trig_sample_cnt <= (others => '0');

            if (arm = '1') then
              ila_state <= ARMED;
            end if;

          when ILA_ARMED =>

            if (trig = '1') then
              trig_idx             <= r_wr_index;
              ila_state            <= ILA_TRIGD;
              post_trig_sample_cnt <= G_DEPTH - trig_tgt - 1;
            else
              trig_idx             <= (others => '0');
              post_trig_sample_cnt <= (others => '0');
            end if;

          when ILA_TRIGD =>

            if (post_trig_sample_cnt = post_trig_sample_tgt) then
              ila_state <= ILA_DONE;
            else
              post_trig_sample_cnt <= post_trig_sample_cnt + 1;
            end if;

          when ILA_DONE =>

            if (arm = '1') then
              ila_state <= ARMED;
            end if;

        end case;

      end if;
    end if;

  end process p_ila;

-------------------------------------------------------------------

end architecture rtl;
