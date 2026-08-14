--------------------------------------------------------------------
-- File: axi4smaster_pktgen.vhdl
-- Author: Y.U.P.
-- Created: 2026-05-24 Sun 22:26
-- Last Modified: 2026-08-10 Mon 22:53
-- Description:
--   Generates AXI4-Stream packets for testing
--------------------------------------------------------------------

library ieee;
  use ieee.numeric_std.all;
  use ieee.std_logic_1164.all;
  use ieee.math_real.all;

entity axi4smaster_pktgen is
  generic (
    C_S0_AXIS_TDATA_WIDTH : integer := 64;
    C_S1_AXIL_DATA_WIDTH  : integer := 32;
    C_S1_AXIL_ADDR_WIDTH  : integer := 32
  );
  port (
    i_clk    : in    std_logic;
    i_resetn : in    std_logic;

    -- AXI4-Stream Master Interface
    s0_axis_aclk   : in    std_logic;
    s0_axis_tready : in    std_logic;
    s0_axis_tdata  : out   std_logic_vector((C_S0_AXIS_TDATA_WIDTH - 1) downto 0);
    s0_axis_tstrb  : out   std_logic_vector(((C_S0_AXIS_TDATA_WIDTH / 8) - 1) downto 0);
    s0_axis_tlast  : out   std_logic;
    s0_axis_tvalid : out   std_logic;

    -- AXI4Lite pins
    s1_axi_aclk    : in    std_logic;
    s1_axi_awaddr  : in    std_logic_vector(C_S1_AXIL_ADDR_WIDTH - 1 downto 0);
    s1_axi_awprot  : in    std_logic_vector(2 downto 0);
    s1_axi_awvalid : in    std_logic;
    s1_axi_awready : out   std_logic;
    s1_axi_wdata   : in    std_logic_vector(C_S1_AXIL_DATA_WIDTH - 1 downto 0);
    s1_axi_wstrb   : in    std_logic_vector((C_S1_AXIL_DATA_WIDTH / 8) - 1 downto 0);
    s1_axi_wvalid  : in    std_logic;
    s1_axi_wready  : out   std_logic;
    s1_axi_bresp   : out   std_logic_vector(1 downto 0);
    s1_axi_bvalid  : out   std_logic;
    s1_axi_bready  : in    std_logic;
    s1_axi_araddr  : in    std_logic_vector(C_S1_AXIL_ADDR_WIDTH - 1 downto 0);
    s1_axi_arprot  : in    std_logic_vector(2 downto 0);
    s1_axi_arvalid : in    std_logic;
    s1_axi_arready : out   std_logic;
    s1_axi_rdata   : out   std_logic_vector(C_S1_AXIL_DATA_WIDTH - 1 downto 0);
    s1_axi_rresp   : out   std_logic_vector(1 downto 0);
    s1_axi_rvalid  : out   std_logic;
    s1_axi_rready  : in    std_logic

  --    -- Remaining AXI4 signals
  --    S1_AXI_ARBURST : in  std_logic_vector( 2 downto 0 );
  --    S1_AXI_ARCACHE : in  std_logic;
  --    S1_AXI_ARID    : in  std_logic_vector( 3 downto 0 );
  --    S1_AXI_ARLEN   : in  std_logic_vector( 3 downto 0 );
  --    S1_AXI_ARLOCK  : in  std_logic_vector( 1 downto 0 );
  --    -- S1_AXI_ARQOS    :
  --    -- S1_AXI_ARREGION :
  --    S1_AXI_ARSIZE  : in  std_logic_vector( 2 downto 0 );
  --    -- S1_AXI_ARUSER   :
  --    S1_AXI_AWBURST : in  std_logic_vector( 1 downto 0 );
  --    S1_AXI_AWCACHE : in  std_logic_vector( 3 downto 0 );
  --    S1_AXI_AWID    : in  std_logic_vector( 3 downto 0 );
  --    S1_AXI_AWLEN   : in  std_logic_vector( 3 downto 0 );
  --    S1_AXI_AWLOCK  : in  std_logic_vector( 1 downto 0 );
  --    -- S1_AXI_AWQOS    :
  --    -- S1_AXI_AWREGION :
  --    S1_AXI_AWSIZE  : in  std_logic_vector( 2 downto 0 );
  --    -- S0_AXI_AWUSER   :
  --    S1_AXI_BID     : out std_logic_vector( 3 downto 0 );
  --    -- S0_AXI_BUSER    :
  --    S1_AXI_RID     : out std_logic_vector( 3 downto 0 );
  --    S1_AXI_RLAST   : out std_logic;
  --    -- S1_AXI_RUSER    :
  --    S1_AXI_WLAST   : in std_logic
  --    -- S1_AXI_WUSER    :
  );
end entity axi4smaster_pktgen;

architecture arch of axi4smaster_pktgen is

  -- Machine states enumeration -------------------------------------
  constant STATE_IDLE : std_logic := '0';
  constant STATE_SEND : std_logic := '1';
  -------------------------------------------------------------------

  -- Machine states -------------------------------------------------
  signal state : std_logic;
  -------------------------------------------------------------------

  -- Counters -------------------------------------------------------
  signal trx_cnt : unsigned(15 downto 0);

  signal num_pkt    : unsigned(31 downto 0);
  signal num_frames : unsigned(31 downto 0);

  signal pkt_cnt   : unsigned(31 downto 0);
  signal frame_cnt : unsigned(31 downto 0);
  -------------------------------------------------------------------

  -- Frame ----------------------------------------------------------
  signal frame         : std_logic_vector(63 downto 0); -- always 64 bits, but only c_s0_axis_tdata_width bits are sent out
  signal frame_resized : std_logic_vector((C_S0_AXIS_TDATA_WIDTH - 1) downto 0);
  -------------------------------------------------------------------

  -- Signals for AXI4-Stream interface ------------------------------
  signal tdata  : std_logic_vector((C_S0_AXIS_TDATA_WIDTH - 1) downto 0);
  signal tvalid : std_logic;
  signal tlast  : std_logic;
  -------------------------------------------------------------------

  -- Signals for AXI4Lite interface ---------------------------------
  signal en_tlast : std_logic;
  signal start    : std_logic;

  signal num_pkt_reg    : std_logic_vector(31 downto 0);
  signal num_frames_reg : std_logic_vector(31 downto 0);

  -- Data density config: number of transfers between bubbles
  -- (tvalid deasserted for one cycle). 0 disables bubble insertion.
  signal density_reg : std_logic_vector(15 downto 0);
  signal density     : unsigned(15 downto 0);

  signal bubble_cnt : unsigned(15 downto 0);
  signal in_bubble  : std_logic;
  -------------------------------------------------------------------

  -- AXI4Lite component ---------------------------------------------
  component axiliteslave is
    generic (
      C_AXI_N_REGS       : integer range 4 to 4096 := 8;
      C_AXI_N_REGS_IN    : integer range 4 to 4096 := 4;
      C_S_AXI_DATA_WIDTH : integer := 32;
      C_S_AXI_ADDR_WIDTH : integer := 32
    );
    port (
      i_last_frame : in    std_logic_vector(63 downto 0);
      i_state      : in    std_logic;

      o_num_pkt    : out   std_logic_vector(31 downto 0);
      o_num_frames : out   std_logic_vector(31 downto 0);
      o_start      : out   std_logic;
      o_en_tlast   : out   std_logic;
      o_density    : out   std_logic_vector(15 downto 0);

      s_axi_aclk    : in    std_logic;
      s_axi_aresetn : in    std_logic;
      s_axi_awaddr  : in    std_logic_vector(c_s_axi_addr_width - 1 downto 0);
      s_axi_awprot  : in    std_logic_vector(2 downto 0);
      s_axi_awvalid : in    std_logic;
      s_axi_awready : out   std_logic;
      s_axi_wdata   : in    std_logic_vector(c_s_axi_data_width - 1 downto 0);
      s_axi_wstrb   : in    std_logic_vector((c_s_axi_data_width / 8) - 1 downto 0);
      s_axi_wvalid  : in    std_logic;
      s_axi_wready  : out   std_logic;
      s_axi_bresp   : out   std_logic_vector(1 downto 0);
      s_axi_bvalid  : out   std_logic;
      s_axi_bready  : in    std_logic;
      s_axi_araddr  : in    std_logic_vector(c_s_axi_addr_width - 1 downto 0);
      s_axi_arprot  : in    std_logic_vector(2 downto 0);
      s_axi_arvalid : in    std_logic;
      s_axi_arready : out   std_logic;
      s_axi_rdata   : out   std_logic_vector(c_s_axi_data_width - 1 downto 0);
      s_axi_rresp   : out   std_logic_vector(1 downto 0);
      s_axi_rvalid  : out   std_logic;
      s_axi_rready  : in    std_logic

    -- -- Remaining AXI4 signals
    -- S0_AXI_ARBURST  : in  std_logic_vector( 2 downto 0 );
    -- S0_AXI_ARCACHE  : in  std_logic;
    -- S0_AXI_ARID     : in  std_logic_vector( 3 downto 0 );
    -- S0_AXI_ARLEN    : in  std_logic_vector( 3 downto 0 );
    -- S0_AXI_ARLOCK   : in  std_logic_vector( 1 downto 0 );
    -- -- S0_AXI_ARQOS    :
    -- -- S0_AXI_ARREGION :
    -- S0_AXI_ARSIZE   : in  std_logic_vector( 2 downto 0 );
    -- -- S0_AXI_ARUSER   :
    -- S0_AXI_AWBURST  : in  std_logic_vector( 1 downto 0 );
    -- S0_AXI_AWCACHE  : in  std_logic_vector( 3 downto 0 );
    -- S0_AXI_AWID     : in  std_logic_vector( 3 downto 0 );
    -- S0_AXI_AWLEN    : in  std_logic_vector( 3 downto 0 );
    -- S0_AXI_AWLOCK   : in  std_logic_vector( 1 downto 0 );
    -- -- S0_AXI_AWQOS    :
    -- -- S0_AXI_AWREGION :
    -- S0_AXI_AWSIZE   : in  std_logic_vector( 2 downto 0 );
    -- -- S0_AXI_AWUSER   :
    -- S0_AXI_BID      : out std_logic_vector( 3 downto 0 );
    -- -- S0_AXI_BUSER    :
    -- S0_AXI_RID      : out std_logic_vector( 3 downto 0 );
    -- S0_AXI_RLAST    : out std_logic;
    -- -- S0_AXI_RUSER    :
    -- S0_AXI_WLAST    : in std_logic;
    -- -- S0_AXI_WUSER    :
    );
  end component axiliteslave;

-------------------------------------------------------------------

begin

  -- Instantiating AXI4Lite slave -----------------------------------
  axi4liteslave_inst : component axiliteslave
    generic map (
      c_axi_n_regs       => 8,
      c_axi_n_regs_in    => 4,
      c_s_axi_data_width => 32,
      c_s_axi_addr_width => 32
    )
    port map (
      i_last_frame => frame,
      i_state      => state,

      o_num_pkt    => num_pkt_reg,
      o_num_frames => num_frames_reg,
      o_start      => start,
      o_en_tlast   => en_tlast,
      o_density    => density_reg,

      s_axi_aclk    => i_clk,
      s_axi_aresetn => i_resetn,
      s_axi_awaddr  => s1_axi_awaddr,
      s_axi_awprot  => s1_axi_awprot,
      s_axi_awvalid => s1_axi_awvalid,
      s_axi_awready => s1_axi_awready,
      s_axi_wdata   => s1_axi_wdata,
      s_axi_wstrb   => s1_axi_wstrb,
      s_axi_wvalid  => s1_axi_wvalid,
      s_axi_wready  => s1_axi_wready,
      s_axi_bresp   => s1_axi_bresp,
      s_axi_bvalid  => s1_axi_bvalid,
      s_axi_bready  => s1_axi_bready,
      s_axi_araddr  => s1_axi_araddr,
      s_axi_arprot  => s1_axi_arprot,
      s_axi_arvalid => s1_axi_arvalid,
      s_axi_arready => s1_axi_arready,
      s_axi_rdata   => s1_axi_rdata,
      s_axi_rresp   => s1_axi_rresp,
      s_axi_rvalid  => s1_axi_rvalid,
      s_axi_rready  => s1_axi_rready
    );

  -------------------------------------------------------------------

  -- Converting config to unsigned ----------------------------------
  num_pkt    <= unsigned(num_pkt_reg);
  num_frames <= unsigned(num_frames_reg);
  density    <= unsigned(density_reg);
  -------------------------------------------------------------------

  -- Frame generation -----------------------------------------------
  frame <= x"B01D" & std_logic_vector(trx_cnt) & std_logic_vector(num_pkt(7 downto 0)) & std_logic_vector(num_frames(7 downto 0)) & std_logic_vector(pkt_cnt(7 downto 0)) & std_logic_vector(frame_cnt(7 downto 0));
  -------------------------------------------------------------------

  -- Compile-time Safe Truncation and Padding (VHDL-2008) -----------

  gen_truncate : if C_S0_AXIS_TDATA_WIDTH <= 64 generate
    frame_resized <= frame(C_S0_AXIS_TDATA_WIDTH - 1 downto 0);
  end generate gen_truncate;

  gen_pad : if C_S0_AXIS_TDATA_WIDTH > 64 generate
    frame_resized(63 downto 0)                         <= frame;
    frame_resized(C_S0_AXIS_TDATA_WIDTH - 1 downto 64) <= (others => '0');
  end generate gen_pad;

  -------------------------------------------------------------------

  -- AXI4-Stream signal assignments ---------------------------------
  s0_axis_tdata  <= tdata;
  s0_axis_tvalid <= tvalid;
  s0_axis_tlast  <= tlast;
  s0_axis_tstrb  <= (others => '1'); -- all bytes are valid
  -------------------------------------------------------------------

  -- AXI4-Stream packet generation ----------------------------------
  main_process : process (i_clk) is
  begin

    if rising_edge(i_clk) then
      tvalid <= '0';
      tlast  <= '0';

      if (i_resetn = '0') then
        state      <= STATE_IDLE;
        trx_cnt    <= (others => '0');
        pkt_cnt    <= (others => '0');
        frame_cnt  <= (others => '0');
        bubble_cnt <= (others => '0');
        in_bubble  <= '0';
      else

        case state is

          when STATE_IDLE =>

            if (start = '1') then
              state      <= STATE_SEND;
              pkt_cnt    <= (others => '0');
              frame_cnt  <= (others => '0');
              trx_cnt    <= trx_cnt + 1;
              bubble_cnt <= (others => '0');
              in_bubble  <= '0';
            end if;

          when STATE_SEND =>

            if (in_bubble = '1') then
              -- forced idle cycle: tvalid stays low (default), resume next cycle
              in_bubble <= '0';
            elsif (s0_axis_tready = '1') then
              tdata  <= frame_resized;
              tvalid <= '1';

              -- data density: after `density` back-to-back transfers, insert
              -- a one cycle bubble (tvalid = 0). density = 0 disables this.
              if (density /= 0 and bubble_cnt = (density - 1)) then
                bubble_cnt <= (others => '0');
                in_bubble  <= '1';
              else
                bubble_cnt <= bubble_cnt + 1;
              end if;

              if (frame_cnt = (num_frames - 1)) then
                frame_cnt <= (others => '0');
                pkt_cnt   <= pkt_cnt + 1;

                if (en_tlast = '1') then
                  tlast <= '1';
                else
                  tlast <= '0';
                end if;

                if (pkt_cnt = (num_pkt - 1)) then
                  pkt_cnt <= (others => '0');
                  state   <= STATE_IDLE;
                end if;
              else
                frame_cnt <= frame_cnt + 1;
              end if;
            end if;

          when others =>

            state <= STATE_IDLE;

        end case;

      end if;
    end if;

  end process main_process;

-------------------------------------------------------------------

end architecture arch;
