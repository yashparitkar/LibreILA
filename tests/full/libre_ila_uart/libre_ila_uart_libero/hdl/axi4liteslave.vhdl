-------------------------------------------------------------------------------
-- File: s_axi_lite_template.vhdl
-- Author: Y.U.P.
-- Last Modified: 2026/05/28 00:55
--
-- Modified template for the AXI Slave bus
-- Drawbacks in the default template in the Vivado:
--     - The slv_reg are not array
--     - Having large number of slave registers was pain
--
-- Updated in this version:
--     - There are two sets of arrays: slv_reg_in & slv_reg_out
--     - Input registers are ordered first
--
-- How to use:
--     - Update the constants C_AXI_N_REGS and C_AXI_N_REGS_IN in the signal declaration
--     - Map the registers near the end of file
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity axiliteslave is
  generic (
    -- Users to add parameters here

    -- User parameters ends
    -- Do not modify the parameters beyond this line

    -- Number of AXI4Lite registers
    C_AXI_N_REGS : integer range 4 to 4096 := 8;
    -- Number of AXI4Lite input registers
    C_AXI_N_REGS_IN : integer range 4 to 4096 := 4;
    -- Width of S_AXI data bus
    C_S_AXI_DATA_WIDTH : integer := 32;
    -- Width of S_AXI address bus
    C_S_AXI_ADDR_WIDTH : integer := 32
  -- Number of Slave Registers)
  );
  port (
    -- Users to add ports here
    i_last_frame : in    std_logic_vector(63 downto 0);
    i_state      : in    std_logic;

    o_num_pkt    : out   std_logic_vector(31 downto 0);
    o_num_frames : out   std_logic_vector(31 downto 0);
    o_start      : out   std_logic;
    o_en_tlast   : out   std_logic;
    o_density    : out   std_logic_vector(15 downto 0);

    -- User ports ends
    -- Do not modify the ports beyond this line

    -- Global Clock Signal
    s_axi_aclk : in    std_logic;
    -- Global Reset Signal. This Signal is Active LOW
    s_axi_aresetn : in    std_logic;
    -- Write address (issued by master, acceped by Slave)
    s_axi_awaddr : in    std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
    -- Write channel Protection type. This signal indicates the
    -- privilege and security level of the transaction, and whether
    -- the transaction is a data access or an instruction access.
    s_axi_awprot : in    std_logic_vector(2 downto 0);
    -- Write address valid. This signal indicates that the master signaling
    -- valid write address and control information.
    s_axi_awvalid : in    std_logic;
    -- Write address ready. This signal indicates that the slave is ready
    -- to accept an address and associated control signals.
    s_axi_awready : out   std_logic;
    -- Write data (issued by master, acceped by Slave)
    s_axi_wdata : in    std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    -- Write strobes. This signal indicates which byte lanes hold
    -- valid data. There is one write strobe bit for each eight
    -- bits of the write data bus.
    s_axi_wstrb : in    std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
    -- Write valid. This signal indicates that valid write
    -- data and strobes are available.
    s_axi_wvalid : in    std_logic;
    -- Write ready. This signal indicates that the slave
    -- can accept the write data.
    s_axi_wready : out   std_logic;
    -- Write response. This signal indicates the status
    -- of the write transaction.
    s_axi_bresp : out   std_logic_vector(1 downto 0);
    -- Write response valid. This signal indicates that the channel
    -- is signaling a valid write response.
    s_axi_bvalid : out   std_logic;
    -- Response ready. This signal indicates that the master
    -- can accept a write response.
    s_axi_bready : in    std_logic;
    -- Read address (issued by master, acceped by Slave)
    s_axi_araddr : in    std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
    -- Protection type. This signal indicates the privilege
    -- and security level of the transaction, and whether the
    -- transaction is a data access or an instruction access.
    s_axi_arprot : in    std_logic_vector(2 downto 0);
    -- Read address valid. This signal indicates that the channel
    -- is signaling valid read address and control information.
    s_axi_arvalid : in    std_logic;
    -- Read address ready. This signal indicates that the slave is
    -- ready to accept an address and associated control signals.
    s_axi_arready : out   std_logic;
    -- Read data (issued by slave)
    s_axi_rdata : out   std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    -- Read response. This signal indicates the status of the
    -- read transfer.
    s_axi_rresp : out   std_logic_vector(1 downto 0);
    -- Read valid. This signal indicates that the channel is
    -- signaling the required read data.
    s_axi_rvalid : out   std_logic;
    -- Read ready. This signal indicates that the master can
    -- accept the read data and response information.
    s_axi_rready : in    std_logic

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
end entity axiliteslave;

architecture arch_imp of axiliteslave is

  type reg_array_in is array (0 to c_axi_n_regs_in - 1) of std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);

  type reg_array_out is array (0 to (c_axi_n_regs - c_axi_n_regs_in - 1)) of std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);

  -- Number of Slave Registers 68
  signal slv_reg_in  : reg_array_in;
  signal slv_reg_out : reg_array_out;

  -- AXI4LITE signals
  signal axi_awaddr  : std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
  signal axi_awready : std_logic;
  signal axi_wready  : std_logic;
  signal axi_bresp   : std_logic_vector(1 downto 0);
  signal axi_bvalid  : std_logic;
  signal axi_araddr  : std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
  signal axi_arready : std_logic;
  signal axi_rresp   : std_logic_vector(1 downto 0);
  signal axi_rvalid  : std_logic;

  -- Example-specific design signals
  -- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
  -- ADDR_LSB is used for addressing 32/64 bit registers/memories
  -- ADDR_LSB = 2 for 32 bits (n downto 2)
  -- ADDR_LSB = 3 for 64 bits (n downto 3)
  constant ADDR_LSB          : integer := (C_S_AXI_DATA_WIDTH / 32) + 1;
  constant OPT_MEM_ADDR_BITS : integer := integer(ceil(log2(real(C_AXI_N_REGS)))) - 1;
  ------------------------------------------------
  -- Signals for user logic register space example
  --------------------------------------------------

  signal byte_index : integer;

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

begin

  -- I/O Connections assignments
  s_axi_awready <= axi_awready;
  s_axi_wready  <= axi_wready;
  s_axi_bresp   <= axi_bresp;
  s_axi_bvalid  <= axi_bvalid;
  s_axi_arready <= axi_arready;
  s_axi_rresp   <= axi_rresp;
  s_axi_rvalid  <= axi_rvalid;

  mem_logic <= s_axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)
               when (s_axi_awvalid = '1') else
               axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);

  -- Implement Write state machine
  -- Outstanding write transactions are not supported by the slave i.e., master should assert bready to receive response on or before it starts sending the new transaction
  p_wsm : process (s_axi_aclk) is
  begin

    -------------------------------------------------------------------------------
    -- Unused AXI4 Signals
    -- s0_axi_bid    <= s_axi_awid;    -- The values should match for valid transation
    -- s0_axi_rid    <= s_axi_arid;
    -- s0_axi_rlast  <= s0_axi_rvalid; -- Each transaction is last
    -- s_axis_tready <= '1' when cnt < wide_reg_width / 32 else
    --                   '0';           -- accept data only once
    -------------------------------------------------------------------------------

    if rising_edge(s_axi_aclk) then
      if (s_axi_aresetn = '0') then
        -- asserting initial values to all 0's during reset
        axi_awready <= '0';
        axi_wready  <= '0';
        axi_bvalid  <= '0';
        axi_bresp   <= (others => '0');
        state_write <= IDLE;
      else

        case (state_write) is

          when IDLE =>

            -- Initial state indicating reset is done and ready to receive read/write transactions
            if (s_axi_aresetn = '1') then
              axi_awready <= '1';
              axi_wready  <= '1';
              state_write <= WADDR;
            else
              state_write <= state_write;
            end if;

          when WADDR =>

            -- At this state, slave is ready to receive address along with corresponding control signals and first data packet. Response valid is also handled at this state
            if (s_axi_awvalid = '1' and axi_awready = '1') then
              axi_awaddr <= s_axi_awaddr;
              if (s_axi_wvalid = '1') then
                axi_awready <= '1';
                state_write <= WADDR;
                axi_bvalid  <= '1';
              else
                axi_awready <= '0';
                state_write <= WDATA;
                if (s_axi_bready = '1' and axi_bvalid = '1') then
                  axi_bvalid <= '0';
                end if;
              end if;
            else
              state_write <= state_write;
              if (s_axi_bready = '1' and axi_bvalid = '1') then
                axi_bvalid <= '0';
              end if;
            end if;

          when WDATA =>

            -- At this state, slave is ready to receive the data packets until the number of transfers is equal to burst length
            if (s_axi_wvalid = '1') then
              state_write <= WADDR;
              axi_bvalid  <= '1';
              axi_awready <= '1';
            else
              state_write <= state_write;
              if (s_axi_bready = '1' and axi_bvalid = '1') then
                axi_bvalid <= '0';
              end if;
            end if;

          when others =>

            -- reserved
            axi_awready <= '0';
            axi_wready  <= '0';
            axi_bvalid  <= '0';

        end case;

      end if;
    end if;

  end process p_wsm;

  -- Implement memory mapped register select and write logic generation
  -- The write data is accepted and written to memory mapped registers when
  -- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
  -- select byte enables of slave registers while writing.
  -- These registers are cleared when reset (active low) is applied.
  -- Slave register write enable is asserted when valid address and data are available
  -- and the slave is ready to accept the write address and write data.
  p_wlg : process (s_axi_aclk) is

    variable idx : integer range 0 to C_AXI_N_REGS - 1;

  begin

    if rising_edge(s_axi_aclk) then
      o_start <= '0';
      if (s_axi_aresetn = '0') then
        -- clear the register array
        for i in 0 to C_AXI_N_REGS_IN - 1 loop

          slv_reg_in(i) <= (others => '0');

        end loop;

      else
        if (s_axi_wvalid = '1') then
          -- compute index from address slice and write bytes per WSTRB
          idx := to_integer(unsigned(mem_logic));
          if (idx >= 0 and idx < C_AXI_N_REGS_IN) then
            -- CUSTOMISING TO DETECT WRITE TO 0x18 START REGISTER ---
            if (idx = 3) then
              o_start <= '1';
            end if;
            ---------------------------------------------------------
            slv_reg_in(idx) <= s_axi_wdata;
          end if;
        end if;
      end if;
    end if;

  end process p_wlg;

  -- Implement read state machine
  p_rsm : process (s_axi_aclk) is
  begin

    if rising_edge(s_axi_aclk) then
      if (s_axi_aresetn = '0') then
        -- asserting initial values to all 0's during reset
        axi_arready <= '0';
        axi_rvalid  <= '0';
        axi_rresp   <= (others => '0');
        state_read  <= IDLE;
      else

        case (state_read) is

          when IDLE =>

            -- Initial state indicating reset is done and ready to receive read/write transactions
            if (s_axi_aresetn = '1') then
              axi_arready <= '1';
              state_read  <= RADDR;
            else
              state_read <= state_read;
            end if;

          when RADDR =>

            -- At this state, slave is ready to receive address along with corresponding control signals
            if (s_axi_arvalid = '1' and axi_arready = '1') then
              state_read  <= RDATA;
              axi_rvalid  <= '1';
              axi_arready <= '0';
              axi_araddr  <= s_axi_araddr;
            else
              state_read <= state_read;
            end if;

          when RDATA =>

            -- At this state, slave is ready to send the data packets until the number of transfers is equal to burst length
            if (axi_rvalid = '1' and s_axi_rready = '1') then
              axi_rvalid  <= '0';
              axi_arready <= '1';
              state_read  <= RADDR;
            else
              state_read <= state_read;
            end if;

          when others =>

            -- reserved
            axi_arready <= '0';
            axi_rvalid  <= '0';

        end case;

      end if;
    end if;

  end process p_rsm;

  -- Implement memory mapped register select and read logic generation
  -- Bounds-check address to avoid out-of-range access on register arrays.
  p_rlg : process (axi_araddr, slv_reg_in, slv_reg_out) is

    variable rd_idx : integer range 0 to C_AXI_N_REGS - 1;

  begin

    rd_idx := to_integer(unsigned(axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)));

    if (rd_idx < C_AXI_N_REGS_IN) then
      s_axi_rdata <= slv_reg_in(rd_idx);
    elsif (rd_idx < C_AXI_N_REGS) then
      s_axi_rdata <= slv_reg_out(rd_idx - C_AXI_N_REGS_IN);
    else
      s_axi_rdata <= (others => '0');
    end if;

  end process p_rlg;

  -- S_AXI_RDATA <= slv_reg_out(to_integer(unsigned(axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB)) - C_AXI_N_REGS_IN));

  -------------------------------------------------------------------------------
  -- Example usage:
  -- o_my_output <= slv_reg_in(0)(14 downto 0);
  -- slv_reg_out( N -(C_AXI_N_REGS_IN) )(3 downto 0) <= i_my_input;
  -- Note that, here N means Nth register among all the AXI4Lite registers
  -- We need output offset of ( C_AXI_N_REGS_IN - 1 ) offset to properly map slv_reg_out
  -- Add user connections here --------------------------------------------------
  o_num_pkt    <= slv_reg_in(0);
  o_num_frames <= slv_reg_in(1);
  o_en_tlast   <= slv_reg_in(2)(0);
  o_density    <= slv_reg_in(2)(31 downto 16);

  slv_reg_out(4 - (C_AXI_N_REGS_IN))    <= i_last_frame(31 downto 0);
  slv_reg_out(5 - (C_AXI_N_REGS_IN))    <= i_last_frame(63 downto 32);
  slv_reg_out(6 - (C_AXI_N_REGS_IN))(0) <= i_state;
-------------------------------------------------------------------------------

end architecture arch_imp;
