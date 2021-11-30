--***********************************************************
-- CPU86 QSPI MMIO module
-- Module Name  : mmio_qspi
--***********************************************************

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;

entity mmio_qspi is
   port(
		  wb_cyc	: out std_logic;
		  wb_stb	: out std_logic;
		  cfg_stb: out std_logic;
		  wb_we	: out std_logic;
		  wb_addr: out std_logic_vector(21 downto 0);
		  i_wb_data		: out std_logic_vector(31 downto 0);
		  wb_stall		: in std_logic;
		  wb_ack			: in std_logic;
		  o_wb_data		: in std_logic_vector(31 downto 0);
		  abus   : in  std_logic_vector(3 downto 0);
		  clock	: in STD_LOGIC := '1';
		  clockmem		: in STD_LOGIC := '1';
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
signal qduration : std_logic_vector(7 downto 0);
signal q_next_is_data : std_logic;
signal priorclockmem : std_logic;

begin
 process(abus, clock, clockmem, wren, reset_n, qcontrol, q_next_is_data, wb_ack, o_wb_data)
  begin
		if (reset_n = '0') then
			qdata <= X"00000000";
			qaddress <= X"00000000";
			qcontrol <= X"00";
			qduration <= X"00";
			q_next_is_data <= '0';
			wb_stb <= '0';
			wb_cyc <= '0';
			cfg_stb <= '0';
			i_wb_data <= X"00000000";
			priorclockmem <= '0';
		elsif rising_edge(clock) then
			if (qcontrol(7) = '1') then
				if (q_next_is_data = '1') then
					if (qcontrol(6) = '0') then
						qdata <= o_wb_data;
					end if;
					wb_stb <= '0';
					cfg_stb <= '0';
					wb_cyc <= '0';
					qcontrol(6) <= '0';
					qcontrol(7) <= '0';
					q_next_is_data <= '0';
				elsif (wb_ack = '1') then
					q_next_is_data <= '1';
				else
					qduration <= std_logic_vector(unsigned(qduration) + 1);
				end if;
			end if;
		if (clockmem = '0') then
			priorclockmem <= '0';
		end if;
		if (clockmem = '1' and priorclockmem = '0') then
			priorclockmem <= '1';
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
             when "1101"  => dbus <= qduration(7 downto 0);
             when "1110"  => dbus <= X"00";
             when "1111"  => dbus <= X"00";
             when others    => dbus <= "--------";
				end case;
			else -- wren='1'
				if (abus="1100") then
					if (data(0) = '1') then
						wb_addr <= qaddress(21 downto 0);
						wb_we <= '0';
						wb_cyc <= '1';
						wb_stb <= '1';
						qcontrol(7) <= '1';
						qduration <= X"00";
					elsif (data(2) = '1') then
						wb_we <= '0';
						wb_cyc <= '1';
						cfg_stb <= '1';
						qcontrol(7) <= '1';
						qduration <= X"00";
					elsif (data(3) = '1') then
						i_wb_data(31 downto 16) <= (others => '0');
					   i_wb_data(15 downto 0) <= qdata(15 downto 0);
						wb_we <= '1';
						wb_cyc <= '1';
						cfg_stb <= '1';
						qcontrol(6) <= '1';
						qcontrol(7) <= '1';
						qduration <= X"00";
					end if;
				else
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
             when "1100"  => null;
             -- when "1100"  => qcontrol(7 downto 0) <= data;
             when "1101"  => null;
             when "1110"  => null;
             when "1111"  => null;
             when others    => null;
				end case;
				end if;
			end if;
			end if;
		end if;
end process;
end rtl;
