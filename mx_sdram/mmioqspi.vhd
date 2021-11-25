--***********************************************************
-- CPU86 QSPI MMIO module
-- Module Name  : mmio_qspi
--***********************************************************

library ieee;
use ieee.std_logic_1164.ALL;

entity mmio_qspi is
   port(abus   : in  std_logic_vector(3 downto 0);
		  clock	: in STD_LOGIC := '1';
		  data	: in STD_LOGIC_VECTOR(7 DOWNTO 0);
		  wren	: in STD_LOGIC;
        dbus   : out std_logic_vector(7 downto 0);
		  reset_n: in STD_LOGIC
);
end mmio_qspi;

architecture rtl of mmio_qspi is

signal qdata : std_logic_vector(31 downto 0);
signal qaddress : std_logic_vector(31 downto 0);
signal qcontrol : std_logic_vector(7 downto 0);

begin
 process(abus, clock, wren, reset_n)
  begin
		if (reset_n = '0') then
			qdata <= X"00000000";
			qaddress <= X"00000000";
			qcontrol <= X"00";
		elsif rising_edge(clock) then
			if (wren='0') then
				case abus is
				 when "0000"  => dbus <= qdata(7 downto 0);
             when "0001"  => dbus <= qdata(15 downto 8);
             when "0010"  => dbus <= qdata(23 downto 16);
             when "0011"  => dbus <= qdata(31 downto 24);
             when "0100"  => dbus <= qaddress(7 downto 0);
             when "0101"  => dbus <= qaddress(15 downto 8);
             when "0110"  => dbus <= qaddress(23 downto 16);
             when "0111"  => dbus <= qaddress(31 downto 24);
             when "1000"  => dbus <= X"00";
             when "1001"  => dbus <= X"00";
             when "1010"  => dbus <= X"00";
             when "1011"  => dbus <= X"00";
             when "1100"  => dbus <= qcontrol(7 downto 0);
             when "1101"  => dbus <= X"00";
             when "1110"  => dbus <= X"00";
             when "1111"  => dbus <= X"00";
             when others    => dbus <= "--------";
				end case;
			else -- wren='1'
				case abus is
				 when "0000"  => qdata(7 downto 0) <= data;
             when "0001"  => qdata(15 downto 8) <= data;
             when "0010"  => qdata(23 downto 16) <= data;
             when "0011"  => qdata(31 downto 24) <= data;
             when "0100"  => qaddress(7 downto 0) <= data;
             when "0101"  => qaddress(15 downto 8) <= data;
             when "0110"  => qaddress(23 downto 16) <= data;
             when "0111"  => qaddress(31 downto 24) <= data;
             when "1000"  => null;
             when "1001"  => null;
             when "1010"  => null;
             when "1011"  => null;
             when "1100"  => qcontrol(7 downto 0) <= data;
             when "1101"  => null;
             when "1110"  => null;
             when "1111"  => null;
             when others    => null;
				end case;
			end if;
		end if;
end process;
end rtl;
