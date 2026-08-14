---------------------------------------------------------------------
-- File: heartbeat.vhdl
-- Author: Y.U.P.
--
-- Scale down the clock to 1 Hz
-- Serves as a indicator to see the fabric working
-- The scale down can be done to 1 kHz to check the frequency via
-- DSO easily.
---------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;

-- Generate a heartbeat signal at 1 Hz

entity heartbeat is
  generic (
    CLK_FREQ : integer := 100000000 -- 1 second at 50MHz, should be multiple of two
  );
  --  Port ( );
  port (
    i_clk  : in    std_logic;
    i_nrst : in    std_logic;
    o_rst  : out   std_logic;
    o_hb   : out   std_logic
  );
end entity heartbeat;

architecture behavioral of heartbeat is

  signal counter : integer;
  signal hb      : std_logic;

begin

  o_rst <= not i_nrst;

  p_main : process (i_clk) is
  begin

    if rising_edge(i_clk) then
      if (counter < CLK_FREQ / 2 - 1) then
        counter <= counter + 1;
      else
        counter <= 0;
        hb      <= not hb; -- Toggle heartbeat signal
      end if;
    end if;

  end process p_main;

  o_hb <= hb;

end architecture behavioral;
