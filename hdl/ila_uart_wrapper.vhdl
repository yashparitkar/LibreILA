-------------------------------------------------------------------------------
-- File: ila_uart_wrapper.vhdl
-- Author: Y.U.P. (paritkary25)
-- Created: 2026-07-21 Tue 20:12
-- Last Modified: 2026/07/24 17:07
--
-- Description: This is a wrapper for the axi4s_ila. This exposes two UART
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

entity ila_uart_wrapper is
  generic (
    G_AXIS_CLK_FREQ      : integer := 100_000_000;
    G_EXTERNAL_TRIG      : integer := 0;      -- 1 for external trigger pin
    G_DATA_WIDTH         : natural := 64;     -- Keep it a multiple of 32 for best results
    G_DEPTH              : natural := 2048;   -- Keep it a power of two for best results
    C_S_AXIL_DATA_WIDTH  : integer := 32;     -- DONT CHANGE
    C_S_AXIL_ADDR_WIDTH  : integer := 32;     -- DONT CHANGE
    G_UART_RX_FIFO_DEPTH : natural := 1024;   -- Depth of the FIFO for UART RX
    G_UART_TX_FIFO_DEPTH : natural := 1024;   -- Depth of the FIFO for UART TX
    BAUD_RATE            : integer := 115_200 -- Baud rate for UART communication
  );
  port (
    i_rst_sync : in    std_logic;

    -- AXI4Lite clock
    s_axil_aclk : in    std_logic;

    -- UART port
    uart_rx : in    std_logic;
    uart_tx : out   std_logic;

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
    axis_out_tdata  : out   std_logic_vector(G_DATA_WIDTH - 1 downto 0)
  );
end entity ila_uart_wrapper;

architecture rtl of ila_uart_wrapper is

  -- Wrapper state machine ------------------------------------------
  constant IUW_IDLE : std_logic_vector(2 downto 0) := "000";
  constant IUW_REQ  : std_logic_vector(2 downto 0) := "001";
  constant IUW_ADDR : std_logic_vector(2 downto 0) := "010";
  constant IUW_RD   : std_logic_vector(2 downto 0) := "011";
  constant IUW_WR   : std_logic_vector(2 downto 0) := "110";

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

  signal uart_rx_fifo_rd_en   : std_logic;
  signal uart_rx_fifo_rd_data : std_logic_vector(7 downto 0);
  signal uart_rx_fifo_nempty  : std_logic;
  -------------------------------------------------------------------

  -- Main process logic signals -------------------------------------
  signal byte_count  : unsigned(3 downto 0);
  signal word_count  : unsigned(6 downto 0);
  signal word_target : unsigned(6 downto 0);
  signal word_addr   : std_logic_vector(31 downto 0);
  signal word_data   : std_logic_vector(31 downto 0);
  signal req_type    : std_logic;             -- '0' for read, '1' for write

  -- Read logic signals
  -------------------------------------------------------------------

  -- Internal AXI4Lite connections ----------------------------------
  signal s_axil_aresetn : std_logic;
  signal s_axil_awaddr  : std_logic_vector(C_S_AXIL_ADDR_WIDTH - 1 downto 0);
  signal s_axil_awprot  : std_logic_vector(2 downto 0);
  signal s_axil_awvalid : std_logic;
  signal s_axil_awready : std_logic;
  signal s_axil_wdata   : std_logic_vector(C_S_AXIL_DATA_WIDTH - 1 downto 0);
  signal s_axil_wstrb   : std_logic_vector(C_S_AXIL_DATA_WIDTH/8 - 1 downto 0);
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

  -- AXI4S ILA
  --   Our star of the show
  component axi4s_ila is
    generic (
      G_AXIS_CLK_FREQ     : integer;
      G_EXTERNAL_TRIG     : integer;
      G_DATA_WIDTH        : natural;
      G_DEPTH             : natural;
      C_S_AXIL_DATA_WIDTH : integer;
      C_S_AXIL_ADDR_WIDTH : integer
    );
    port (
      i_rst_sync : in    std_logic;

      i_ext_trig : in    std_logic;
      o_trig_out : out   std_logic;

      axis_in_aclk   : in    std_logic;
      axis_in_tready : out   std_logic;
      axis_in_tvalid : in    std_logic;
      axis_in_tlast  : in    std_logic;
      axis_in_tdata  : in    std_logic_vector(G_DATA_WIDTH - 1 downto 0);

      axis_out_aclk   : out   std_logic;
      axis_out_tready : in    std_logic;
      axis_out_tvalid : out   std_logic;
      axis_out_tlast  : out   std_logic;
      axis_out_tdata  : out   std_logic_vector(G_DATA_WIDTH - 1 downto 0);

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
  end component axi4s_ila;

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

  -------------------------------------------------------------------
  end component uart;

begin
  -- Signal assignments ---------------------------------------------
  s_axil_aresetn <= not i_rst_sync;

  -- Default values for AXI4Lite signals
  s_axil_awprot <= (others => '0');
  s_axil_arprot <= (others => '0');
  s_axil_wstrb  <= (others => '1');
  -------------------------------------------------------------------

  axi4s_ila_inst : component axi4s_ila
    generic map (
      -- Clock speed of the AXIS, used in plotting
      g_axis_clk_freq     => G_AXIS_CLK_FREQ,
      g_external_trig     => G_EXTERNAL_TRIG,
      g_data_width        => G_DATA_WIDTH,
      g_depth             => G_DEPTH,
      c_s_axil_data_width => C_S_AXIL_DATA_WIDTH,
      c_s_axil_addr_width => C_S_AXIL_ADDR_WIDTH
    )

    port map (
      i_rst_sync => i_rst_sync,

      -- External tigger
      i_ext_trig => i_ext_trig,
      o_trig_out => o_trig_out,

      -- AXI4S_IN port
      axis_in_aclk   => axis_in_aclk,
      axis_in_tready => axis_in_tready,
      axis_in_tvalid => axis_in_tvalid,
      axis_in_tlast  => axis_in_tlast,
      axis_in_tdata  => axis_in_tdata,

      -- AXI4S_OUT port
      axis_out_aclk   => axis_out_aclk,
      axis_out_tready => axis_out_tready,
      axis_out_tvalid => axis_out_tvalid,
      axis_out_tlast  => axis_out_tlast,
      axis_out_tdata  => axis_out_tdata,

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
      baud            => BAUD_RATE,
      clock_frequency => G_AXIS_CLK_FREQ
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

  -- Main process ---------------------------------------------------
  -- Handles the main logic of the wrapper. This includes reading and
  -- writing to the UART FIFOs, and handling the AXI4Lite read and
  -- write requests.
  p_main : process (s_axil_aclk) is
  begin

    if rising_edge(s_axil_aclk) then
      if (i_rst_sync = '1') then
        -- Reset logic
        iuw_state          <= IUW_IDLE;
        uart_tx_fifo_wr_en <= '0';
        uart_rx_fifo_rd_en <= '0';
        byte_count         <= (others => '0');
      else
        -- Default values
        uart_tx_fifo_wr_en <= '0';
        uart_rx_fifo_rd_en <= '0';

        case iuw_state is

          when IUW_IDLE =>

            -- Check if there is proper sync/valid packet in the UART RX FIFO
            if (uart_rx_fifo_nempty = '1') then
              if (uart_rx_fifo_rd_data = x"55") then
                -- Read the data from the UART RX FIFO
                uart_rx_fifo_rd_en <= '1';
                iuw_state          <= IUW_REQ;
              else
                -- Invalid packet, stay in IDLE, flush the FIFO
                uart_rx_fifo_rd_en <= '1';
                iuw_state          <= IUW_IDLE;
              end if;
            end if;

          when IUW_REQ =>

            -- Get the next byte from the UART RX FIFO
            if (uart_rx_fifo_nempty = '1') then
              uart_rx_fifo_rd_en <= '1';
              word_count         <= (others => '0');
              word_target        <= unsigned(uart_rx_fifo_rd_data(6 downto 0));
              req_type           <= uart_rx_fifo_rd_data(7);
              iuw_state          <= IUW_ADDR;
            end if;

          when IUW_ADDR =>

            -- Get next 4 bytes from the UART RX FIFO for the address, MSB first
            if (byte_count < 4) then
              if (uart_rx_fifo_nempty = '1') then
                uart_rx_fifo_rd_en                                                                    <= '1';
                word_addr((31 - to_integer(byte_count) * 8) downto (24 - to_integer(byte_count) * 8)) <= uart_rx_fifo_rd_data;
                byte_count                                                                            <= byte_count + 1;
              end if;
            else
              -- Address received, move to read or write state based on req_type
              byte_count <= (others => '0');
              txn_side   <= TXN_FETCH;
              if (req_type = '0') then
                iuw_state <= IUW_RD;
              else
                iuw_state <= IUW_WR;
              end if;
            end if;

          when IUW_RD =>

            -- Get 4 bytes from the AXI4Lite registers at the given address
            -- Write them to the UART TX FIFO, incrementing the address
            if (word_count < word_target) then

              case txn_side is

                when TXN_FETCH =>

                  -- initiate AXI4Lite read transaction
                  s_axil_araddr  <= std_logic_vector(word_addr);
                  s_axil_arvalid <= '1';
                  s_axil_rready  <= '1';
                  txn_side       <= TXN_FETCH;

                  if (s_axil_rvalid = '1') then
                    word_data      <= s_axil_rdata;
                    s_axil_arvalid <= '0';
                    txn_side       <= TXN_WRITE;
                    byte_count     <= (others => '0');
                  end if;

                when TXN_WRITE =>

                  -- Write the data into the UART TX FIFO, MSB first
                  if (byte_count < 4) then
                    if (uart_tx_fifo_nfull = '1') then
                      uart_tx_fifo_wr_en   <= '1';
                      uart_tx_fifo_wr_data <= word_data((31 - to_integer(byte_count) * 8) downto (24 - to_integer(byte_count) * 8));
                      byte_count           <= byte_count + 1;
                    end if;
                  else
                    -- All bytes written, increment word count and address
                    word_count <= word_count + 1;
                    word_addr  <= std_logic_vector(unsigned(word_addr) + 4);
                    txn_side   <= TXN_FETCH;
                  end if;

                when others =>

                  txn_side <= TXN_FETCH;

              end case;

            else
              -- All words read, go back to IDLE state
              iuw_state <= IUW_IDLE;
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
                    if (uart_rx_fifo_nempty = '1') then
                      uart_rx_fifo_rd_en                                                                <= '1';
                      word_data(31 - to_integer(byte_count) * 8 downto 24 - to_integer(byte_count) * 8) <= uart_rx_fifo_rd_data;
                      byte_count                                                                        <= byte_count + 1;
                    end if;
                  else
                    -- All bytes received, initiate AXI4Lite write transaction
                    s_axil_awaddr  <= std_logic_vector(word_addr);
                    s_axil_wdata   <= word_data;
                    s_axil_awvalid <= '1';
                    s_axil_wvalid  <= '1';
                    txn_side       <= TXN_WRITE;
                  end if;

                when TXN_WRITE =>

                  -- Wait for AXI4Lite write response
                  if (s_axil_bvalid = '1') then
                    s_axil_awvalid <= '0';
                    s_axil_wvalid  <= '0';
                    s_axil_bready  <= '1';                                                               -- Acknowledge the write response
                    word_count     <= word_count + 1;
                    word_addr      <= std_logic_vector(unsigned(word_addr) + 4);
                    byte_count     <= (others => '0');
                    txn_side       <= TXN_FETCH;
                  end if;

                when others =>

                  txn_side <= TXN_FETCH;

              end case;

            else
              -- All words written, go back to IDLE state
              iuw_state <= IUW_IDLE;
            end if;

          when others =>

            iuw_state <= IUW_IDLE;

        end case;

      end if;
    end if;

  end process p_main;

-------------------------------------------------------------------

end architecture rtl;
