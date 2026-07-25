-------------------------------------------------------------------------------
-- File: fifo.vhdl
-- Author: Y.U.P.
-- Last modified: 2026-07-24 Fri 20:47
--
-- Description: Synchronous FIFO made out of registers
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity fifo is
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
end entity fifo;

architecture rtl of fifo is

  constant C_ADDR_WIDTH : integer := integer(ceil(log2(real(G_DEPTH))));

  type t_fifo_data is array (0 to g_DEPTH - 1) of std_logic_vector(g_WIDTH - 1 downto 0);

  signal r_fifo_data : t_fifo_data := (others => (others => '0'));

  signal r_wr_index : unsigned(C_ADDR_WIDTH  downto 0) := (others => '0');
  signal r_rd_index : unsigned(C_ADDR_WIDTH  downto 0) := (others => '0');

  signal w_full  : std_logic;
  signal w_empty : std_logic;

begin

  w_empty <= '1' when (r_wr_index = r_rd_index) else
             '0';
  w_full  <= '1' when (r_wr_index(C_ADDR_WIDTH - 1 downto 0) = r_rd_index(C_ADDR_WIDTH - 1 downto 0) and
                        r_wr_index(C_ADDR_WIDTH) /= r_rd_index(C_ADDR_WIDTH)) else
             '0';

  o_nfull   <= not w_full;
  o_nempty  <= not w_empty;
  o_rd_data <= r_fifo_data(to_integer(r_rd_index(C_ADDR_WIDTH - 1 downto 0)));

  p_write : process (i_clk) is
  begin

    if rising_edge(i_clk) then
      if (i_rst_sync = '1') then
        r_wr_index <= (others => '0');
      elsif (i_wr_en = '1' and w_full = '0') then
        r_fifo_data(to_integer(r_wr_index( c_ADDR_WIDTH - 1 downto 0))) <= i_wr_data;
        r_wr_index                                                      <= r_wr_index + 1;
      end if;
    end if;

  end process p_write;

  p_read : process (i_clk) is
  begin

    if rising_edge(i_clk) then
      if (i_rst_sync = '1') then
        r_rd_index <= (others => '0');
      elsif (i_rd_en = '1' and w_empty = '0') then
        r_rd_index <= r_rd_index + 1;
      end if;
    end if;

  end process p_read;

end architecture rtl;
