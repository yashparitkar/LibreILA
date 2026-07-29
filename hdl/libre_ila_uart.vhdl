-------------------------------------------------------------------------------
-- File: libre_ila_uart.vhdl
-- Author: Y.U.P. (paritkary25)
-- Created: 2026-07-21 Tue 20:12
-- Last Modified: 2026-07-29 Wed 12:43
--
-- Description: This is a wrapper for the libre_ila. This exposes two UART
-- pins through which the ILA can be controller allowing the external debug
-- of the ILA with serial port.
-- Usage:
--   * Add the all the .vhdl files to your project
--   * Instantiate the wrapper
--   * Expose the UART RX and TX to the outside world
--   * Connect the RX and TX to PC with any serial USB adapter
--   * Use the python interface to work with the ILA
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity libre_ila_uart is
  generic (
    G_SAMP_CLK_FREQ      : integer := 100_000_000;
    G_AXIL_CLK_FREQ      : integer := 100_000_000;
    G_EXTERNAL_TRIG      : integer := 0;      -- 1 for external trigger pin
    G_PROBE_WIDTH        : natural := 67;     -- Keep it a multiple of 32 for best results
    G_SAMP_BUFF_DEPTH    : natural := 2048;   -- Keep it a power of two for best results
    G_UART_RX_FIFO_DEPTH : natural := 1024;   -- Depth of the FIFO for UART RX
    G_UART_TX_FIFO_DEPTH : natural := 1024;   -- Depth of the FIFO for UART TX
    G_BAUD_RATE          : integer := 115_200; -- Baud rate for UART communication
    C_S_AXIL_DATA_WIDTH  : integer := 32;     -- DONT CHANGE
    C_S_AXIL_ADDR_WIDTH  : integer := 32      -- DONT CHANGE
  );
  port (
    i_rst_sync : in    std_logic;

    -- Sampling clock, the clock of the domain the probe lives in
    samp_aclk : in    std_logic;

    -- AXI4Lite clock
    s_axil_aclk : in    std_logic;

    -- UART port
    uart_rx : in    std_logic;
    uart_tx : out   std_logic;

    -- Probe Slave ^^DI ---------------------------------------------
    -- Faces the master of the probed link, so it carries the port
    -- directions of that link's slave.
    -----------------------------------------------------------------

    -- Probe Master ^^DO --------------------------------------------
    -- Faces the slave of the probed link, every direction mirrored.
    -----------------------------------------------------------------

    -- External tigger
    i_ext_trig : in    std_logic;
    o_trig_out : out   std_logic
  );
end entity libre_ila_uart;

architecture rtl of libre_ila_uart is

  -- Watchdog signals -----------------------------------------------
  constant WDT_TRIGGER : unsigned(31 downto 0) := to_unsigned(G_AXIL_CLK_FREQ, 32);

  signal wdt_counter : unsigned(31 downto 0);
  signal wdt_trig    : std_logic;
  signal wdt_reset   : std_logic;
  -------------------------------------------------------------------

  -- Wrapper state machine ------------------------------------------
  constant IUW_IDLE : std_logic_vector(2 downto 0) := "000";
  constant IUW_REQ  : std_logic_vector(2 downto 0) := "001";
  constant IUW_ADDR : std_logic_vector(2 downto 0) := "011";
  constant IUW_HDR  : std_logic_vector(2 downto 0) := "010";
  constant IUW_RD   : std_logic_vector(2 downto 0) := "100";
  constant IUW_WR   : std_logic_vector(2 downto 0) := "101";

  signal iuw_state : std_logic_vector(2 downto 0);
  -------------------------------------------------------------------

  -- Operating side -------------------------------------------------
  constant TXN_FETCH : std_logic := '1';
  constant TXN_WRITE : std_logic := '0';

  signal txn_side : std_logic;
  -------------------------------------------------------------------

  -- FIFO signals ---------------------------------------------------
  signal uart_tx_fifo_wr_en   : std_logic;
  signal uart_tx_fifo_wr_data : std_logic_vector(7 downto 0);
  signal uart_tx_fifo_nfull   : std_logic;

  -- o_nfull lags a push by one cycle, so a second push issued on that
  -- cycle would be silently discarded once the FIFO is full.
  signal uart_tx_fifo_wr_en_d1 : std_logic;

  signal uart_rx_fifo_rd_en   : std_logic;
  signal uart_rx_fifo_rd_data : std_logic_vector(7 downto 0);
  signal uart_rx_fifo_nempty  : std_logic;

  -- o_nempty/o_rd_data lag a pop by one cycle, so the byte must not be
  -- re-examined on that cycle.
  signal uart_rx_fifo_rd_en_d1 : std_logic;
  -------------------------------------------------------------------

  -- Main process logic signals -------------------------------------
  signal byte_count  : unsigned(3 downto 0);
  signal word_count  : unsigned(6 downto 0);
  signal word_target : unsigned(6 downto 0);
  signal word_addr   : std_logic_vector(31 downto 0);
  signal word_data   : std_logic_vector(31 downto 0);
  signal req_type    : std_logic; -- '0' for read, '1' for write

  -- AXI4Lite read process signals ----------------------------------
  constant ARP_IDLE : std_logic_vector(1 downto 0) := "00";
  constant ARP_READ : std_logic_vector(1 downto 0) := "01";

  signal arp_state : std_logic_vector(1 downto 0);

  signal axil_rd_req  : std_logic;
  signal axil_rd_addr : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal axil_rd_data : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  signal axil_rd_done : std_logic;

  -- axil_rd_req is held high across the handshake and cleared a cycle
  -- late, so ARP_IDLE needs an edge, not a level, or it re-fires.
  signal axil_rd_req_d1 : std_logic;
  -------------------------------------------------------------------

  -- AXI4Lite write process signals ---------------------------------
  constant AWP_IDLE : std_logic_vector(1 downto 0) := "00";
  constant AWP_RESP : std_logic_vector(1 downto 0) := "01";

  signal awp_state : std_logic_vector(1 downto 0);

  signal axil_wr_req  : std_logic;
  signal axil_wr_addr : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal axil_wr_data : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);

  -- Managing ready and valid
  signal axil_wr_req_d1 : std_logic;
  signal axil_wr_done   : std_logic;
  -------------------------------------------------------------------

  -- Internal AXI4Lite connections ----------------------------------
  signal s_axil_aresetn : std_logic;
  signal s_axil_awaddr  : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal s_axil_awprot  : std_logic_vector(2 downto 0);
  signal s_axil_awvalid : std_logic;
  signal s_axil_awready : std_logic;
  signal s_axil_wdata   : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  signal s_axil_wstrb   : std_logic_vector(C_S_AXIL_DATA_WIDTH / 8 - 1 downto 0);
  signal s_axil_wvalid  : std_logic;
  signal s_axil_wready  : std_logic;
  signal s_axil_bresp   : std_logic_vector(1 downto 0);
  signal s_axil_bvalid  : std_logic;
  signal s_axil_bready  : std_logic;
  signal s_axil_araddr  : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal s_axil_arprot  : std_logic_vector(2 downto 0);
  signal s_axil_arvalid : std_logic;
  signal s_axil_arready : std_logic;
  signal s_axil_rdata   : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  signal s_axil_rresp   : std_logic_vector(1 downto 0);
  signal s_axil_rvalid  : std_logic;
  signal s_axil_rready  : std_logic;
  -------------------------------------------------------------------

  -- UART signals ---------------------------------------------------
  signal uart_data_in      : std_logic_vector(7 downto 0);
  signal uart_data_in_stb  : std_logic;
  signal uart_data_in_ack  : std_logic;
  signal uart_data_out     : std_logic_vector(7 downto 0);
  signal uart_data_out_stb : std_logic;
  -------------------------------------------------------------------

  -- Component instantiations ---------------------------------------

  -- LibreILA
  --   Our star of the show
  component libre_ila is
    generic (
      G_SAMP_CLK_FREQ     : integer;
      G_AXIL_CLK_FREQ     : integer;
      G_EXTERNAL_TRIG     : integer;
      G_PROBE_WIDTH       : natural;
      G_SAMP_BUFF_DEPTH   : natural;
      C_S_AXIL_DATA_WIDTH : integer;
      C_S_AXIL_ADDR_WIDTH : integer
    );
    port (
      i_rst_sync : in    std_logic;

      samp_aclk : in    std_logic;

      i_ext_trig : in    std_logic;
      o_trig_out : out   std_logic;

      -- Probe slave ^^DI -------------------------------------------
      ---------------------------------------------------------------

      -- Probe master ^^DO ------------------------------------------
      ---------------------------------------------------------------

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
  end component libre_ila;

  -- FIFO
  component fifo is
    generic (
      G_WIDTH : natural := 64;
      G_DEPTH : natural := 4
    );
    port (
      i_rst_sync : in    std_logic;
      i_clk      : in    std_logic;

      -- FIFO Write Interface
      i_wr_en   : in    std_logic;
      i_wr_data : in    std_logic_vector(G_WIDTH - 1 downto 0);

      -- FIFO Read Interface
      i_rd_en   : in    std_logic;
      o_rd_data : out   std_logic_vector(G_WIDTH - 1 downto 0);

      -- Occupancy indicators
      o_nfull  : out   std_logic;
      o_nempty : out   std_logic
    );
  end component fifo;

  -- UART
  component uart is
    generic (
      BAUD            : positive;
      CLOCK_FREQUENCY : positive
    );
    port (
      clock               : in    std_logic;
      reset               : in    std_logic;
      data_stream_in      : in    std_logic_vector(7 downto 0);
      data_stream_in_stb  : in    std_logic;
      data_stream_in_ack  : out   std_logic;
      data_stream_out     : out   std_logic_vector(7 downto 0);
      data_stream_out_stb : out   std_logic;
      tx                  : out   std_logic;
      rx                  : in    std_logic
    );
  end component uart;

-------------------------------------------------------------------

begin

  -- Signal assignments ---------------------------------------------
  s_axil_aresetn <= not i_rst_sync;

  -- Default values for AXI4Lite signals
  s_axil_awprot <= (others => '0');
  s_axil_arprot <= (others => '0');
  s_axil_wstrb  <= (others => '1');
  -------------------------------------------------------------------

  libre_ila_inst : component libre_ila
    generic map (
      g_samp_clk_freq     => G_SAMP_CLK_FREQ,
      g_axil_clk_freq     => G_AXIL_CLK_FREQ,
      g_external_trig     => G_EXTERNAL_TRIG,
      g_probe_width       => G_PROBE_WIDTH,
      g_samp_buff_depth   => G_SAMP_BUFF_DEPTH,
      c_s_axil_data_width => C_S_AXIL_DATA_WIDTH,
      c_s_axil_addr_width => C_S_AXIL_ADDR_WIDTH
    )

    port map (
      i_rst_sync => i_rst_sync,

      -- Sampling clock
      samp_aclk => samp_aclk,

      -- External tigger
      i_ext_trig => i_ext_trig,
      o_trig_out => o_trig_out,

      -- Probe Slave Mapping ^^MI -----------------------------------
      ---------------------------------------------------------------

      -- Probe Master Mapping ^^MO ----------------------------------
      ---------------------------------------------------------------

      -- AXI4Lite slave port
      s_axil_aclk    => s_axil_aclk,
      s_axil_aresetn => s_axil_aresetn,
      s_axil_awaddr  => s_axil_awaddr,
      s_axil_awprot  => s_axil_awprot,
      s_axil_awvalid => s_axil_awvalid,
      s_axil_awready => s_axil_awready,
      s_axil_wdata   => s_axil_wdata,
      s_axil_wstrb   => s_axil_wstrb,
      s_axil_wvalid  => s_axil_wvalid,
      s_axil_wready  => s_axil_wready,
      s_axil_bresp   => s_axil_bresp,
      s_axil_bvalid  => s_axil_bvalid,
      s_axil_bready  => s_axil_bready,
      s_axil_araddr  => s_axil_araddr,
      s_axil_arprot  => s_axil_arprot,
      s_axil_arvalid => s_axil_arvalid,
      s_axil_arready => s_axil_arready,
      s_axil_rdata   => s_axil_rdata,
      s_axil_rresp   => s_axil_rresp,
      s_axil_rvalid  => s_axil_rvalid,
      s_axil_rready  => s_axil_rready
    );

  uart_tx_fifo_inst : component fifo
    generic map (
      g_width => 8,
      g_depth => G_UART_TX_FIFO_DEPTH
    )
    port map (
      i_rst_sync => i_rst_sync,
      i_clk      => s_axil_aclk,
      i_wr_en    => uart_tx_fifo_wr_en,
      i_wr_data  => uart_tx_fifo_wr_data,
      i_rd_en    => uart_data_in_ack,
      o_rd_data  => uart_data_in,
      o_nfull    => uart_tx_fifo_nfull,
      o_nempty   => uart_data_in_stb
    );

  uart_rx_fifo_inst : component fifo
    generic map (
      g_width => 8,
      g_depth => G_UART_RX_FIFO_DEPTH
    )
    port map (
      i_rst_sync => i_rst_sync,
      i_clk      => s_axil_aclk,
      i_wr_en    => uart_data_out_stb,
      i_wr_data  => uart_data_out,
      i_rd_en    => uart_rx_fifo_rd_en,
      o_rd_data  => uart_rx_fifo_rd_data,
      o_nfull    => open,
      o_nempty   => uart_rx_fifo_nempty
    );

  uart_inst : component uart
    generic map (
      baud            => G_BAUD_RATE,
      clock_frequency => G_AXIL_CLK_FREQ
    )
    port map (
      clock               => s_axil_aclk,
      reset               => i_rst_sync,
      data_stream_in      => uart_data_in,
      data_stream_in_stb  => uart_data_in_stb,
      data_stream_in_ack  => uart_data_in_ack,
      data_stream_out     => uart_data_out,
      data_stream_out_stb => uart_data_out_stb,
      tx                  => uart_tx,
      rx                  => uart_rx
    );

  -- Watchdog timer process -----------------------------------------
  p_wdt : process (s_axil_aclk) is
  begin

    if rising_edge(s_axil_aclk) then
      if ((i_rst_sync = '1') or (wdt_reset = '1')) then
        wdt_counter <= (others => '0');
        wdt_trig    <= '0';
      else
        if (wdt_counter = WDT_TRIGGER) then
          wdt_trig    <= '1';
          wdt_counter <= (others => '0');
        else
          wdt_trig    <= '0';
          wdt_counter <= wdt_counter + 1;
        end if;
      end if;
    end if;

  end process p_wdt;

  -------------------------------------------------------------------

  -- Main process ---------------------------------------------------
  -- Handles the main logic of the wrapper. This includes reading and
  -- writing to the UART FIFOs, and handling the AXI4Lite read and
  -- write requests.
  p_main : process (s_axil_aclk) is

    variable byte_count_int : integer range 0 to 15;

  begin

    byte_count_int := to_integer(unsigned(byte_count));

    if rising_edge(s_axil_aclk) then
      if ((i_rst_sync = '1') or (wdt_trig = '1')) then
        -- Reset logic
        iuw_state             <= IUW_IDLE;
        uart_tx_fifo_wr_en    <= '0';
        uart_tx_fifo_wr_en_d1 <= '0';
        uart_rx_fifo_rd_en    <= '0';
        uart_rx_fifo_rd_en_d1 <= '0';
        byte_count            <= (others => '0');
        axil_rd_req           <= '0';
        axil_wr_req           <= '0';
      else
        -- Default values
        uart_tx_fifo_wr_en    <= '0';
        uart_tx_fifo_wr_en_d1 <= '0';
        uart_rx_fifo_rd_en    <= '0';
        wdt_reset             <= '0';
        uart_rx_fifo_rd_en_d1 <= '0';

        case iuw_state is

          when IUW_IDLE =>

            wdt_reset   <= '1';
            axil_rd_req <= '0';
            axil_wr_req <= '0';

            -- Check if there is proper sync/valid packet in the UART RX FIFO
            if (uart_rx_fifo_nempty = '1' and uart_rx_fifo_rd_en_d1 = '0') then
              if (uart_rx_fifo_rd_data = x"55") then
                -- Read the data from the UART RX FIFO
                uart_rx_fifo_rd_en    <= '1';
                uart_rx_fifo_rd_en_d1 <= '1';
                iuw_state             <= IUW_REQ;
              else
                -- Invalid packet, stay in IDLE, flush the FIFO
                uart_rx_fifo_rd_en    <= '1';
                uart_rx_fifo_rd_en_d1 <= '1';
                iuw_state             <= IUW_IDLE;
              end if;
            end if;

          when IUW_REQ =>

            -- Get the next byte from the UART RX FIFO
            if (uart_rx_fifo_nempty = '1' and uart_rx_fifo_rd_en_d1 = '0') then
              uart_rx_fifo_rd_en    <= '1';
              uart_rx_fifo_rd_en_d1 <= '1';
              word_count            <= (others => '0');
              word_target           <= unsigned(uart_rx_fifo_rd_data(6 downto 0));
              req_type              <= uart_rx_fifo_rd_data(7);
              iuw_state             <= IUW_ADDR;
            end if;

          when IUW_ADDR =>

            -- Get next 4 bytes from the UART RX FIFO for the address, MSB first
            if (byte_count < 4) then
              if (uart_rx_fifo_nempty = '1' and uart_rx_fifo_rd_en_d1 = '0') then
                uart_rx_fifo_rd_en                                                    <= '1';
                uart_rx_fifo_rd_en_d1                                                 <= '1';
                word_addr((31 - byte_count_int * 8) downto (24 - byte_count_int * 8)) <= uart_rx_fifo_rd_data;
                byte_count                                                            <= byte_count + 1;
              end if;
            else
              -- Address received, move to header frame preparation
              wdt_reset  <= '1';
              byte_count <= (others => '0');
              iuw_state  <= IUW_HDR;
            end if;

          when IUW_HDR =>

            wdt_reset <= '1';
            if (uart_tx_fifo_nfull = '1' and uart_tx_fifo_wr_en_d1 = '0') then
              uart_tx_fifo_wr_en    <= '1';
              uart_tx_fifo_wr_en_d1 <= '1';

              case byte_count is

                when "0000" =>

                  uart_tx_fifo_wr_data <= x"AA";

                when "0001" =>

                  uart_tx_fifo_wr_data <= '1' & std_logic_vector(word_target);

                when "0010" =>

                  uart_tx_fifo_wr_data <= word_addr(31 downto 24);

                when "0011" =>

                  uart_tx_fifo_wr_data <= word_addr(23 downto 16);

                when "0100" =>

                  uart_tx_fifo_wr_data <= word_addr(15 downto 8);

                when "0101" =>

                  uart_tx_fifo_wr_data <= word_addr(7 downto 0);

                when others =>

                  null;

              end case;

              if (byte_count = 5) then
                byte_count <= (others => '0');
                txn_side   <= TXN_FETCH;

                if (req_type = '0') then
                  iuw_state <= IUW_RD;
                else
                  iuw_state <= IUW_WR;
                end if;
              else
                byte_count <= byte_count + 1;
              end if;
            end if;

          when IUW_RD =>

            -- Get 4 bytes from the AXI4Lite registers at the given address
            -- Write them to the UART TX FIFO, incrementing the address
            if (word_count < word_target) then

              case txn_side is

                when TXN_FETCH =>

                  -- Request AXI4Lite Read process
                  axil_rd_req  <= '1';
                  axil_rd_addr <= word_addr;

                  if (axil_rd_done = '1') then
                    axil_rd_req <= '0';
                    wdt_reset   <= '1';
                    word_data   <= axil_rd_data;
                    txn_side    <= TXN_WRITE;
                    byte_count  <= (others => '0');
                  end if;

                when TXN_WRITE =>

                  -- Write the data into the UART TX FIFO, MSB first
                  if (byte_count < 4) then
                    if (uart_tx_fifo_nfull = '1' and uart_tx_fifo_wr_en_d1 = '0') then
                      uart_tx_fifo_wr_en    <= '1';
                      uart_tx_fifo_wr_en_d1 <= '1';
                      uart_tx_fifo_wr_data  <= word_data((31 - byte_count_int * 8) downto (24 - byte_count_int * 8));
                      byte_count            <= byte_count + 1;
                      wdt_reset             <= '1';
                    end if;
                  else
                    -- All bytes written, increment word count and address.
                    -- byte_count is reset here (not left for the next
                    -- TXN_FETCH pass) because on the last word this state
                    -- exits straight to IDLE without ever revisiting
                    -- TXN_FETCH, which would otherwise leave a stale
                    -- byte_count=4 to corrupt the next message's ADDR
                    -- parsing.
                    word_count <= word_count + 1;
                    word_addr  <= std_logic_vector(unsigned(word_addr) + 4);
                    byte_count <= (others => '0');
                    txn_side   <= TXN_FETCH;
                  end if;

                when others =>

                  txn_side <= TXN_FETCH;

              end case;

            else
              -- All words read, go back to IDLE state
              axil_rd_req <= '0';
              iuw_state   <= IUW_IDLE;
            end if;

          when IUW_WR =>

            -- Get 4 bytes from the UART RX FIFO
            -- Write the words to the AXI4Lite registers, incrementing the
            -- address for each word
            if (word_count < word_target) then

              case txn_side is

                when TXN_FETCH =>

                  -- Get the next byte from the UART RX FIFO
                  if (byte_count < 4) then
                    if (uart_rx_fifo_nempty = '1' and uart_rx_fifo_rd_en_d1 = '0') then
                      uart_rx_fifo_rd_en                                                <= '1';
                      uart_rx_fifo_rd_en_d1                                             <= '1';
                      word_data(31 - byte_count_int * 8 downto 24 - byte_count_int * 8) <= uart_rx_fifo_rd_data;
                      byte_count                                                        <= byte_count + 1;
                    end if;
                  else
                    -- All bytes received, request AXI4Lite Write process
                    axil_wr_req  <= '1';
                    axil_wr_addr <= word_addr;
                    axil_wr_data <= word_data;
                    txn_side     <= TXN_WRITE;
                  end if;

                when TXN_WRITE =>

                  -- Wait for AXI4Lite Write process completion
                  if (axil_wr_done = '1') then
                    axil_wr_req <= '0';
                    word_count  <= word_count + 1;
                    word_addr   <= std_logic_vector(unsigned(word_addr) + 4);
                    byte_count  <= (others => '0');
                    txn_side    <= TXN_FETCH;
                    wdt_reset   <= '1';
                  end if;

                when others =>

                  txn_side <= TXN_FETCH;

              end case;

            else
              -- All words written, go back to IDLE state
              axil_wr_req <= '0';
              iuw_state   <= IUW_IDLE;
            end if;

          when others =>

            iuw_state <= IUW_IDLE;

        end case;

      end if;
    end if;

  end process p_main;

  -- AXI4Lite Write Process -----------------------------------------
  p_axil_write : process (s_axil_aclk) is
  begin

    if rising_edge(s_axil_aclk) then
      if (i_rst_sync = '1') then
        awp_state      <= AWP_IDLE;
        s_axil_awvalid <= '0';
        s_axil_wvalid  <= '0';
        s_axil_bready  <= '0';
        s_axil_awaddr  <= (others => '0');
        s_axil_wdata   <= (others => '0');
        axil_wr_done   <= '0';
        axil_wr_req_d1 <= '0';
      else
        axil_wr_req_d1 <= axil_wr_req;

        case awp_state is

          when AWP_IDLE =>

            axil_wr_done <= '0';

            if (axil_wr_req = '1' and axil_wr_req_d1 = '0') then
              s_axil_awaddr  <= axil_wr_addr;
              s_axil_wdata   <= axil_wr_data;
              s_axil_awvalid <= '1';
              s_axil_wvalid  <= '1';
              s_axil_bready  <= '1';
              awp_state      <= AWP_RESP;
            end if;

          when AWP_RESP =>

            if (s_axil_awready = '1') then
              s_axil_awvalid <= '0';
            end if;

            if (s_axil_wready = '1') then
              s_axil_wvalid <= '0';
            end if;

            if (s_axil_bvalid = '1') then
              s_axil_bready <= '0';
              axil_wr_done  <= '1';
              awp_state     <= AWP_IDLE;
            end if;

          when others =>

            awp_state <= AWP_IDLE;

        end case;

      end if;
    end if;

  end process p_axil_write;

  -------------------------------------------------------------------

  -- AXI4Lite Read Process ------------------------------------------
  p_axil_read : process (s_axil_aclk) is
  begin

    if rising_edge(s_axil_aclk) then
      if (i_rst_sync = '1') then
        arp_state      <= ARP_IDLE;
        s_axil_arvalid <= '0';
        s_axil_rready  <= '0';
        s_axil_araddr  <= (others => '0');
        axil_rd_done   <= '0';
        axil_rd_data   <= (others => '0');
        axil_rd_req_d1 <= '0';
      else
        axil_rd_req_d1 <= axil_rd_req;

        case arp_state is

          when ARP_IDLE =>

            axil_rd_done <= '0';

            if (axil_rd_req = '1' and axil_rd_req_d1 = '0') then
              s_axil_araddr  <= axil_rd_addr;
              s_axil_arvalid <= '1';
              s_axil_rready  <= '1';
              arp_state      <= ARP_READ;
            end if;

          when ARP_READ =>

            if (s_axil_arready = '1') then
              s_axil_arvalid <= '0';
            end if;

            if (s_axil_rvalid = '1') then
              axil_rd_data  <= s_axil_rdata;
              s_axil_rready <= '0';
              axil_rd_done  <= '1';
              arp_state     <= ARP_IDLE;
            end if;

          when others =>

            arp_state <= ARP_IDLE;

        end case;

      end if;
    end if;

  end process p_axil_read;

-------------------------------------------------------------------

end architecture rtl;
